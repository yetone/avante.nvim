--- dispatch_await tool: synchronously wait for a pending dispatch to complete,
--- then return its full result and compact the related polling/dispatch
--- messages from the chat history.
---
--- Use this tool when the primary agent has nothing else to do except wait
--- for in-flight dispatches. It replaces the noisy "polling dispatch_status
--- repeatedly" pattern with a single blocking call that picks one dispatch,
--- waits for it, returns its result, and removes all the intermediate
--- dispatch_status / dispatch_agent tool calls from the context window so
--- only the final clean result remains.

local Base = require("avante.llm_tools.base")
local DispatchRegistry = require("avante.dispatch_registry")
local History = require("avante.history")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "dispatch_await"

M.description = [[Synchronously wait for a pending dispatch_agent to complete and pull its result into the main chat.

Use this when the only work left to do is waiting on one or more in-flight dispatches.
Instead of polling `dispatch_status` repeatedly, call `dispatch_await` once:

- If `dispatch_id` is supplied, waits for that specific dispatch.
- Otherwise, picks the oldest still-running dispatch and waits for it.

When the dispatch completes, this tool:
1. Returns the dispatch's full result inline (as if you had run the task yourself).
2. COMPACTS the chat history - all prior `dispatch_status` tool calls and the
   original `dispatch_agent` tool_use/tool_result for this dispatch are marked
   as compacted and disappear from your context. Only the final result remains.

This keeps your context window clean and avoids burning tokens on repeated polling.]]

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "dispatch_id",
      description = "Optional: specific dispatch ID to wait for. If omitted, the oldest running dispatch is picked.",
      type = "string",
      optional = true,
    },
    {
      name = "timeout_seconds",
      description = "Optional: max seconds to wait before giving up. Defaults to 600 (10 min).",
      type = "integer",
      optional = true,
    },
  },
  usage = {
    dispatch_id = "Specific dispatch ID to wait for (optional)",
    timeout_seconds = "Max seconds to wait (optional, default 600)",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "result",
    description = "The completed dispatch's result, ready to use inline.",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the await failed or timed out.",
    type = "string",
    optional = true,
  },
}

---Format a completed/failed dispatch into a single concise text block.
---@param dispatch avante.Dispatch
---@return string
local function format_result(dispatch)
  if dispatch.status == "completed" then
    return string.format(
      "[Dispatch #%s completed inline] (provider: %s, model: %s)\nTask: %s\n\nResult:\n%s",
      dispatch.id,
      dispatch.provider or "unknown",
      dispatch.model or "unknown",
      dispatch.prompt:sub(1, 200),
      dispatch.result or "(no result)"
    )
  elseif dispatch.status == "failed" then
    return string.format(
      "[Dispatch #%s failed inline] (provider: %s, model: %s)\nTask: %s\n\nError: %s",
      dispatch.id,
      dispatch.provider or "unknown",
      dispatch.model or "unknown",
      dispatch.prompt:sub(1, 200),
      dispatch.error or "unknown error"
    )
  else
    return string.format("[Dispatch #%s status: %s]", dispatch.id, dispatch.status or "unknown")
  end
end

---Compact all messages related to dispatch_status, the original dispatch_agent
---for the awaited dispatch, and any prior dispatch_result injections for the
---same dispatch id. After compaction, only the dispatch_await tool's own
---result message remains in the LLM context.
---@param session_ctx table
---@param awaited_dispatch_id string
local function compact_dispatch_messages(session_ctx, awaited_dispatch_id)
  if not session_ctx or not session_ctx.get_history_messages then return end
  local ok, messages = pcall(session_ctx.get_history_messages)
  if not ok or type(messages) ~= "table" then return end

  for _, msg in ipairs(messages) do
    if not msg.is_compacted then
      local tool_use = History.Helpers.get_tool_use_data(msg)
      local tool_result = History.Helpers.get_tool_result_data(msg)

      -- 1) All dispatch_status tool calls become obsolete the moment we
      --    synchronously await a dispatch.
      if tool_use and tool_use.name == "dispatch_status" then
        msg.is_compacted = true
      elseif tool_result then
        local use_msg = History.Helpers.get_tool_use_message(tool_result.tool_use_id, messages)
        if use_msg then
          local use_data = History.Helpers.get_tool_use_data(use_msg)
          if use_data and use_data.name == "dispatch_status" then msg.is_compacted = true end
        end
      end

      -- 2) The original dispatch_agent tool_use that started this dispatch
      --    and its tool_result (the "Dispatch #N started..." placeholder).
      if tool_use and tool_use.name == "dispatch_agent" then
        local store = msg.tool_use_store
        if store and store.dispatch_id == awaited_dispatch_id then msg.is_compacted = true end
      elseif tool_result then
        local use_msg = History.Helpers.get_tool_use_message(tool_result.tool_use_id, messages)
        if use_msg then
          local use_data = History.Helpers.get_tool_use_data(use_msg)
          if use_data and use_data.name == "dispatch_agent" then
            local store = use_msg.tool_use_store
            if store and store.dispatch_id == awaited_dispatch_id then msg.is_compacted = true end
          end
        end
      end

      -- 3) Any prior "[Dispatch #X completed/failed]" user messages injected
      --    by the sidebar's on_complete callback - we are about to deliver a
      --    cleaner version inline, so drop the duplicate.
      if msg.is_dispatch_result then
        local text = History.Helpers.get_text_data(msg)
        if text and text:match("Dispatch #" .. awaited_dispatch_id .. "[ %]]") then msg.is_compacted = true end
      end
    end
  end
end

---Pick the dispatch to await. Prefers the oldest currently-running dispatch.
---Falls back to the most recently-completed dispatch if nothing is running.
---@param session_id string
---@param explicit_id? string
---@return avante.Dispatch | nil dispatch
---@return string | nil error
local function pick_target(session_id, explicit_id)
  if explicit_id then
    local d = DispatchRegistry.get(session_id, explicit_id)
    if not d then return nil, "Dispatch #" .. explicit_id .. " not found" end
    return d, nil
  end

  local all = DispatchRegistry.get_all(session_id)
  for _, d in ipairs(all) do
    if d.status == "running" then return d, nil end
  end
  local recent
  for _, d in ipairs(all) do
    if d.status == "completed" or d.status == "failed" then recent = d end
  end
  if recent then return recent, nil end
  return nil, "No dispatches available to await"
end

---@class avante.DispatchAwaitInput
---@field dispatch_id? string
---@field timeout_seconds? integer

---@type AvanteLLMToolFunc<avante.DispatchAwaitInput>
function M.func(input, opts)
  local on_complete = opts.on_complete
  local on_log = opts.on_log
  local session_ctx = opts.session_ctx or {}
  local session_id = session_ctx.dispatch_session_id or "default"

  local target, err = pick_target(session_id, input.dispatch_id)
  if err or not target then
    if on_complete then
      on_complete(nil, err or "Unknown error")
      return
    end
    return nil, err or "Unknown error"
  end

  if on_log then on_log("Awaiting dispatch #" .. target.id) end

  -- Already finished? Return immediately + compact.
  if target.status ~= "running" then
    local result = format_result(target)
    compact_dispatch_messages(session_ctx, target.id)
    if on_complete then
      on_complete(result, nil)
      return
    end
    return result, nil
  end

  -- Still running - poll the registry on a timer until it terminates.
  local timeout_seconds = input.timeout_seconds or 600
  local poll_interval_ms = 200
  local max_wait_ms = timeout_seconds * 1000
  local elapsed = 0
  local timer = vim.uv.new_timer()
  if not timer then
    local msg = "Failed to create timer for dispatch_await"
    if on_complete then
      on_complete(nil, msg)
      return
    end
    return nil, msg
  end

  -- Guard against multiple scheduled callbacks trying to close the same timer.
  -- vim.schedule_wrap can queue several ticks before any of them runs, so the
  -- first callback that decides to stop must prevent the rest from closing again.
  local timer_active = true
  local function stop_timer()
    if not timer_active then return end
    timer_active = false
    timer:stop()
    timer:close()
  end

  timer:start(
    poll_interval_ms,
    poll_interval_ms,
    vim.schedule_wrap(function()
      if not timer_active then return end
      elapsed = elapsed + poll_interval_ms
      local d = DispatchRegistry.get(session_id, target.id)
      if not d then
        stop_timer()
        if on_complete then on_complete(nil, "Dispatch #" .. target.id .. " disappeared from registry") end
        return
      end
      if d.status ~= "running" then
        stop_timer()
        local result = format_result(d)
        compact_dispatch_messages(session_ctx, d.id)
        if on_complete then on_complete(result, nil) end
        return
      end
      if elapsed >= max_wait_ms then
        stop_timer()
        if on_complete then
          on_complete(
            nil,
            string.format("Timed out after %ds waiting for dispatch #%s (still running)", timeout_seconds, target.id)
          )
        end
        return
      end
    end)
  )

  -- Async: return nothing - the on_complete callback above will deliver.
end

return M
