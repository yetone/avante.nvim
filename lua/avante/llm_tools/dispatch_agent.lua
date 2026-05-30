local Providers = require("avante.providers")
local Config = require("avante.config")
local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")
local History = require("avante.history")
local Line = require("avante.ui.line")
local Highlights = require("avante.highlights")
local DispatchRegistry = require("avante.dispatch_registry")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "dispatch_agent"

M.get_description = function()
  local provider = Providers[Config.provider]
  if Config.provider:match("copilot") and provider.model and provider.model:match("gpt") then
    return [[Launch a new agent that has access to the following tools: `glob`, `grep`, `ls`, `view`, `attempt_completion`. Use dispatch_agent when you need to search for keywords, files, or patterns across the codebase, or gather and SYNTHESIZE context while you continue working on other tasks.

IMPORTANT: dispatch_agent is ASYNCHRONOUS. It returns immediately with a dispatch ID. The sub-agent runs in the background. Results will be delivered to you automatically when the dispatch completes. You can continue working on other tasks while dispatches are running. Check the dispatch status section at the top of the conversation for updates.

KEY RULE: The sub-agent must REDUCE and SYNTHESIZE information — it must NOT dump raw file contents. Ask specific questions; get concise answers back.]]
  end

  return [[Launch a new agent that has access to the following tools: `glob`, `grep`, `ls`, `view`, `attempt_completion`. Use dispatch_agent when you need to:

- Search for keywords, files, or patterns across the codebase
- Gather and SYNTHESIZE context while you continue working on other tasks

IMPORTANT RULES:
- dispatch_agent is ASYNCHRONOUS and FIRE-AND-FORGET. It returns immediately with a dispatch ID.
- The sub-agent runs in the background. You do NOT wait for results.
- Results are delivered to you automatically when the dispatch completes (appears as a message in the conversation).
- You can dispatch MULTIPLE agents concurrently for maximum parallelism.
- Check the "Active & Recent Dispatches" section in your context for status updates.
- Continue working on other tasks while dispatches are running.
- Each dispatch invocation is stateless - provide all context the agent needs in the prompt.

Usage notes:
1. Launch multiple dispatches concurrently whenever possible for maximum performance.
2. When a dispatch is done, its result will appear in your conversation context automatically.
3. If your only remaining work is to wait for dispatch results, DO NOT poll `dispatch_status`
   in a loop. Instead call `dispatch_await` once — it blocks until the next dispatch finishes,
   returns its full result inline, and compacts the polling noise out of your context.
4. Your prompt should ask SPECIFIC QUESTIONS — the agent must return synthesized answers, not raw file dumps.
5. The agent can NOT use `bash`, `write`, `str_replace` - it can only read/search files.
6. The agent will use the cheapest available LLM provider that can fit the workload within its context window.

## CRITICAL: The sub-agent's job is to REDUCE context, not amplify it.

BAD prompt (wastes tokens — agent reads a file and dumps it back verbatim):
  "Read lib/store.ts and return its complete contents"
  "Read the following files in FULL and return their content verbatim: ..."

GOOD prompt (agent searches, synthesizes, and returns only what matters):
  "In lib/store.ts, find the VideoEntry type definition — list its field names and types only"
  "In lib/processing.ts, what function handles face detection? What are its inputs/outputs?"
  "Search for all callers of updateVideo() across the codebase and list them with file:line"

If you just need to read a file yourself, use the `view` tool directly — do NOT dispatch an agent just to pass file contents back to you.]]
end

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "prompt",
      description = "A specific question or set of questions for the agent to research and answer. "
        .. "The agent must SYNTHESIZE and REDUCE information — do NOT ask it to return raw file contents. "
        .. "Ask targeted questions like 'What fields does the VideoEntry type have?' or "
        .. "'What function handles face detection in lib/processing.ts and what are its parameters?' "
        .. "instead of 'Read lib/store.ts and return it verbatim'.",
      type = "string",
    },
  },
  required = { "prompt" },
  usage = {
    prompt = "Specific question(s) for the agent to research and synthesize (NOT a request to dump raw file contents)",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "result",
    description = "The dispatch ID and status message (agent runs asynchronously)",
    type = "string",
  },
  {
    name = "error",
    description = "The error message if the dispatch could not be started",
    type = "string",
    optional = true,
  },
}

local function get_available_tools()
  return {
    require("avante.llm_tools.ls"),
    require("avante.llm_tools.grep"),
    require("avante.llm_tools.glob"),
    require("avante.llm_tools.view"),
    require("avante.llm_tools.attempt_completion"),
  }
end

--- Estimate tokens for a string (rough: ~1.3 tokens per word)
---@param text string
---@return integer
local function estimate_tokens(text)
  local words = 0
  for _ in text:gmatch("%S+") do
    words = words + 1
  end
  return math.ceil(words * 1.3)
end

---@class avante.DispatchAgentInput
---@field prompt string

---@type avante.LLMToolOnRender<avante.DispatchAgentInput>
function M.on_render(input, opts)
  local result_message = opts.result_message
  local store = opts.store or {}
  local messages = store.messages or {}
  local dispatch_id = store.dispatch_id
  local tool_use_summary = {}
  for _, msg in ipairs(messages) do
    local summary
    local tool_use = History.Helpers.get_tool_use_data(msg)
    if tool_use then
      local tool_result = History.Helpers.get_tool_result(tool_use.id, messages)
      if tool_result then
        if tool_use.name == "ls" then
          local path = tool_use.input.path
          if tool_result.is_error then
            summary = string.format("Ls %s: failed", path)
          else
            local ok, filepaths = pcall(vim.json.decode, tool_result.content)
            if ok then summary = string.format("Ls %s: %d paths", path, #filepaths) end
          end
        elseif tool_use.name == "grep" then
          local path = tool_use.input.path
          local query = tool_use.input.query
          if tool_result.is_error then
            summary = string.format("Grep %s in %s: failed", query, path)
          else
            local ok, filepaths = pcall(vim.json.decode, tool_result.content)
            if ok then summary = string.format("Grep %s in %s: %d paths", query, path, #filepaths) end
          end
        elseif tool_use.name == "glob" then
          local path = tool_use.input.path
          local pattern = tool_use.input.pattern
          if tool_result.is_error then
            summary = string.format("Glob %s in %s: failed", pattern, path)
          else
            local ok, result = pcall(vim.json.decode, tool_result.content)
            if ok then
              local matches = result.matches
              if matches then summary = string.format("Glob %s in %s: %d matches", pattern, path, #matches) end
            end
          end
        elseif tool_use.name == "view" then
          local path = tool_use.input.path
          if tool_result.is_error then
            summary = string.format("View %s: failed", path)
          else
            local ok, result = pcall(vim.json.decode, tool_result.content)
            if ok and type(result) == "table" and type(result.content) == "string" then
              local lines = vim.split(result.content, "\n")
              summary = string.format("View %s: %d lines", path, #lines)
            end
          end
        end
      end
      if summary then summary = "  " .. Utils.icon("tool ") .. summary end
    else
      summary = History.Helpers.get_text_data(msg)
    end
    if summary then table.insert(tool_use_summary, summary) end
  end
  local state = "running"
  local icon = Utils.icon("running ")
  local hl = Highlights.AVANTE_TASK_RUNNING
  if result_message then
    local result = History.Helpers.get_tool_result_data(result_message)
    if result then
      if result.is_error then
        state = "failed"
        icon = Utils.icon("failed ")
        hl = Highlights.AVANTE_TASK_FAILED
      else
        state = "completed"
        icon = Utils.icon("completed ")
        hl = Highlights.AVANTE_TASK_COMPLETED
      end
    end
  end
  local lines = {}
  local dispatch_label = dispatch_id and ("Dispatch #" .. dispatch_id) or "Dispatch"
  table.insert(lines, Line:new({ { icon .. dispatch_label .. " " .. state, hl } }))
  table.insert(lines, Line:new({ { "" } }))
  table.insert(lines, Line:new({ { "  Task:" } }))
  local prompt_lines = vim.split(input.prompt or "", "\n")
  for _, line in ipairs(prompt_lines) do
    table.insert(lines, Line:new({ { "    " .. line } }))
  end
  table.insert(lines, Line:new({ { "" } }))
  if #tool_use_summary > 0 then
    table.insert(lines, Line:new({ { "  Task summary:" } }))
    for _, summary in ipairs(tool_use_summary) do
      local summary_lines = vim.split(summary, "\n")
      for _, line in ipairs(summary_lines) do
        table.insert(lines, Line:new({ { "    " .. line } }))
      end
    end
  end
  return lines
end

---@type AvanteLLMToolFunc<avante.DispatchAgentInput>
function M.func(input, opts)
  local on_log = opts.on_log
  local on_complete = opts.on_complete
  local session_ctx = opts.session_ctx

  local Llm = require("avante.llm")

  local prompt = input.prompt
  local tools = get_available_tools()

  if on_log then on_log("prompt: " .. prompt) end

  -- Determine the session_id for the dispatch registry
  local session_id = session_ctx.dispatch_session_id or "default"

  -- Estimate tokens for the prompt to pick the cheapest provider
  local prompt_tokens = estimate_tokens(prompt)
  local dispatch_provider_name, _ = DispatchRegistry.pick_cheapest_provider(prompt_tokens + 2000) -- add headroom

  -- Fall back to default provider if no cheap provider fits
  if not dispatch_provider_name then dispatch_provider_name = Config.provider end

  local dispatch_provider = Providers[dispatch_provider_name]
  local dispatch_model = dispatch_provider and dispatch_provider.model or "unknown"

  -- Register the dispatch in the registry
  local dispatch_id = DispatchRegistry.register(session_id, prompt, dispatch_provider_name, dispatch_model)

  if on_log then
    on_log(string.format(
      "Dispatch #%s started (provider: %s, model: %s)",
      dispatch_id, dispatch_provider_name, dispatch_model
    ))
  end

  -- Store the dispatch_id for rendering
  if opts.set_store then opts.set_store("dispatch_id", dispatch_id) end

  local system_prompt = "You are a focused research assistant with access to file-system tools. "
    .. "Your ONLY job is to answer this specific request: " .. prompt .. "\n\n"
    .. "CRITICAL RULES — follow these or you are wasting tokens and defeating the purpose:\n"
    .. "1. SYNTHESIZE and REDUCE — never return raw file contents or long verbatim excerpts. "
    .. "Extract exactly the information requested and discard everything else.\n"
    .. "2. Use grep/glob FIRST to pinpoint the exact lines/symbols you need before opening a file. "
    .. "Do NOT read an entire file when a targeted search will do.\n"
    .. "3. Your result in attempt_completion should be COMPACT — only the facts needed to answer "
    .. "the question. Think: could someone implement code from your answer without needing to ask "
    .. "follow-up questions? If so, it's complete. Would they need to re-read the source file? "
    .. "Then you're not synthesizing enough.\n"
    .. "4. NEVER read a file and return its full contents verbatim — that is strictly forbidden. "
    .. "If you are tempted to do that, use grep to extract only the relevant section instead.\n"
    .. "When you have gathered exactly what is needed, call attempt_completion with a concise, "
    .. "structured answer."

  local history_messages = {}
  local tool_use_messages = {}
  local total_tokens = 0
  local result = ""

  ---@type avante.AgentLoopOptions
  local agent_loop_options = {
    system_prompt = system_prompt,
    user_input = "start",
    tools = tools,
    on_tool_log = session_ctx.on_tool_log,
    on_messages_add = function(msgs)
      msgs = vim.islist(msgs) and msgs or { msgs }
      for _, msg in ipairs(msgs) do
        local idx = nil
        for i, m in ipairs(history_messages) do
          if m.uuid == msg.uuid then
            idx = i
            break
          end
        end
        if idx ~= nil then
          history_messages[idx] = msg
        else
          table.insert(history_messages, msg)
        end
      end
      if opts.set_store then opts.set_store("messages", history_messages) end
      for _, msg in ipairs(msgs) do
        local tool_use = History.Helpers.get_tool_use_data(msg)
        if tool_use then
          tool_use_messages[msg.uuid] = true
          if tool_use.name == "attempt_completion" and tool_use.input and tool_use.input.result then
            result = tool_use.input.result
          end
        end
      end
      -- Update dispatch progress
      local last_msg = msgs[#msgs]
      if last_msg then
        local text = History.Helpers.get_text_data(last_msg)
        if text and #text > 0 then DispatchRegistry.update_progress(session_id, dispatch_id, text:sub(1, 200)) end
      end
    end,
    session_ctx = session_ctx,
    on_start = session_ctx.on_start,
    on_chunk = function(chunk)
      if not chunk then return end
      total_tokens = total_tokens + (#vim.split(chunk, " ") * 1.3)
    end,
    on_complete = function(err)
      if err ~= nil then
        DispatchRegistry.fail(session_id, dispatch_id, vim.inspect(err))
        return
      end
      DispatchRegistry.complete(session_id, dispatch_id, result)
    end,
  }

  -- Start the agent loop asynchronously (fire-and-forget)
  -- Use vim.schedule to ensure it runs on the next event loop tick
  vim.schedule(function() Llm.agent_loop(agent_loop_options) end)

  -- Return IMMEDIATELY with the dispatch ID - do not wait for completion
  local response = string.format(
    "Dispatch #%s started. The sub-agent is working on your request in the background using provider '%s' (model: %s). "
      .. "Results will be delivered to you automatically when the dispatch completes. "
      .. "You can continue working on other tasks.",
    dispatch_id,
    dispatch_provider_name,
    dispatch_model
  )

  -- Return synchronously - this makes the tool non-blocking
  if on_complete then
    on_complete(response, nil)
    return
  end
  return response, nil
end

return M
