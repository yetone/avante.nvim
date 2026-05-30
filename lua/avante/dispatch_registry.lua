--- Dispatch registry: tracks all dispatched sub-agents across the sidebar session.
---
--- Each dispatch is fire-and-forget from the primary chat's perspective.  The
--- registry provides:
---   * `register()`   - create a new dispatch entry (status = "running")
---   * `complete()`   - mark a dispatch as done and store its result
---   * `fail()`       - mark a dispatch as failed
---   * `get()`        - retrieve a single dispatch by id
---   * `get_all()`    - all dispatches for a session
---   * `get_context()` - formatted string for injection into prompts
---   * `pick_cheapest_provider()` - select lowest-cost provider that fits payload

local Config = require("avante.config")
local Providers = require("avante.providers")

---@class avante.Dispatch
---@field id string
---@field prompt string
---@field status "running" | "completed" | "failed"
---@field last_message string
---@field result string | nil
---@field error string | nil
---@field provider string | nil
---@field model string | nil
---@field created_at number
---@field completed_at number | nil

---@class avante.DispatchRegistry
local M = {}

---@type table<string, avante.Dispatch[]>
M._sessions = {}

---@type table<string, integer>
M._counters = {}

---@type table<string, fun(dispatch: avante.Dispatch): nil>
M._on_complete_callbacks = {}

---@param session_id string
---@param cb fun(dispatch: avante.Dispatch): nil
function M.set_on_complete(session_id, cb) M._on_complete_callbacks[session_id] = cb end

--- Register a new dispatch and return its id.
---@param session_id string
---@param prompt string
---@param provider_name? string
---@param model_name? string
---@return string dispatch_id
function M.register(session_id, prompt, provider_name, model_name)
  if not M._sessions[session_id] then
    M._sessions[session_id] = {}
    M._counters[session_id] = 0
  end
  M._counters[session_id] = M._counters[session_id] + 1
  local id = tostring(M._counters[session_id])
  ---@type avante.Dispatch
  local dispatch = {
    id = id,
    prompt = prompt,
    status = "running",
    last_message = "Starting...",
    result = nil,
    error = nil,
    provider = provider_name,
    model = model_name,
    created_at = os.clock(),
    completed_at = nil,
  }
  table.insert(M._sessions[session_id], dispatch)
  return id
end

--- Update the "last_message" for a running dispatch (progress reporting).
---@param session_id string
---@param dispatch_id string
---@param message string
function M.update_progress(session_id, dispatch_id, message)
  local dispatch = M.get(session_id, dispatch_id)
  if dispatch then dispatch.last_message = message end
end

--- Mark a dispatch as completed.
---@param session_id string
---@param dispatch_id string
---@param result string
function M.complete(session_id, dispatch_id, result)
  local dispatch = M.get(session_id, dispatch_id)
  if not dispatch then return end
  dispatch.status = "completed"
  dispatch.result = result
  dispatch.last_message = "Completed"
  dispatch.completed_at = os.clock()
  local cb = M._on_complete_callbacks[session_id]
  if cb then vim.schedule(function() cb(dispatch) end) end
end

--- Mark a dispatch as failed.
---@param session_id string
---@param dispatch_id string
---@param error_msg string
function M.fail(session_id, dispatch_id, error_msg)
  local dispatch = M.get(session_id, dispatch_id)
  if not dispatch then return end
  dispatch.status = "failed"
  dispatch.error = error_msg
  dispatch.last_message = "Failed: " .. error_msg
  dispatch.completed_at = os.clock()
  local cb = M._on_complete_callbacks[session_id]
  if cb then vim.schedule(function() cb(dispatch) end) end
end

--- Retrieve a single dispatch.
---@param session_id string
---@param dispatch_id string
---@return avante.Dispatch | nil
function M.get(session_id, dispatch_id)
  local dispatches = M._sessions[session_id]
  if not dispatches then return nil end
  for _, d in ipairs(dispatches) do
    if d.id == dispatch_id then return d end
  end
  return nil
end

--- Retrieve all dispatches for a session.
---@param session_id string
---@return avante.Dispatch[]
function M.get_all(session_id) return M._sessions[session_id] or {} end

--- Build a human-readable context block describing all active and recently
--- completed dispatches. Injected into prompts so the primary agent knows
--- what is in flight.
---@param session_id string
---@return string
function M.get_context(session_id)
  local dispatches = M._sessions[session_id]
  if not dispatches or #dispatches == 0 then return "" end

  -- Count running dispatches so we can advise the agent how to proceed.
  local running_count = 0
  for _, d in ipairs(dispatches) do
    if d.status == "running" then running_count = running_count + 1 end
  end

  local lines = { "## Active & Recent Dispatches" }
  if running_count > 0 then
    table.insert(
      lines,
      string.format(
        "%d dispatch(es) still running. If your only remaining work is to wait on them, "
          .. "call `dispatch_await` (NOT `dispatch_status` in a loop). `dispatch_await` blocks "
          .. "until one finishes, returns its full result inline, and compacts the polling "
          .. "noise out of your context.",
        running_count
      )
    )
  end
  for _, d in ipairs(dispatches) do
    local status_icon = d.status == "running" and "running" or d.status == "completed" and "completed" or "failed"
    local prompt_preview = d.prompt:sub(1, 120) .. (#d.prompt > 120 and "..." or "")
    local summary = string.format("- Dispatch #%s [%s]: %s", d.id, status_icon, prompt_preview)
    table.insert(lines, summary)
    if d.status == "running" then
      table.insert(lines, "  Last update: " .. d.last_message)
    elseif d.status == "completed" and d.result then
      local result_preview = d.result:sub(1, 2000)
      if #d.result > 2000 then result_preview = result_preview .. "\n...[truncated]" end
      table.insert(lines, "  Result: " .. result_preview)
    elseif d.status == "failed" and d.error then
      table.insert(lines, "  Error: " .. d.error)
    end
  end

  return table.concat(lines, "\n")
end

--- Remove all dispatches for a session (e.g. on sidebar close).
---@param session_id string
function M.clear(session_id)
  M._sessions[session_id] = nil
  M._counters[session_id] = nil
  M._on_complete_callbacks[session_id] = nil
end

--- Pick the cheapest provider whose context_window can fit the given
--- token count within the configured max_context_ratio.
--- Returns nil if no provider fits.
---@param estimated_tokens integer
---@return string | nil provider_name
---@return table | nil provider_config
function M.pick_cheapest_provider(estimated_tokens)
  local dispatch_config = Config.dispatch or {}
  local max_ratio = dispatch_config.max_context_ratio or 0.6

  ---@type {name: string, config: AvanteDefaultBaseProvider, cost: number}[]
  local candidates = {}

  for name, _ in pairs(Config.providers) do
    local ok, provider_conf = pcall(function() return Providers.parse_config(Providers.get_config(name)) end)
    if ok and provider_conf then
      local context_window = provider_conf.context_window
      if context_window and context_window > 0 then
        local max_allowed = math.floor(context_window * max_ratio)
        if estimated_tokens <= max_allowed then
          local cost = provider_conf.cost_per_input_token or math.huge
          table.insert(candidates, { name = name, config = provider_conf, cost = cost })
        end
      end
    end
  end

  if #candidates == 0 then return nil, nil end

  table.sort(candidates, function(a, b) return a.cost < b.cost end)

  local best = candidates[1]
  return best.name, best.config
end

return M
