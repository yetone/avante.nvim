local Base = require("avante.llm_tools.base")
local DispatchRegistry = require("avante.dispatch_registry")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "dispatch_status"

M.description = [[Check the status of dispatched sub-agents. Returns a summary of all running and completed dispatches.
Use this to check if dispatched work has completed and retrieve their results.]]

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "dispatch_id",
      description = "Optional: specific dispatch ID to check. If omitted, returns all dispatches.",
      type = "string",
      optional = true,
    },
  },
  usage = {
    dispatch_id = "Specific dispatch ID to check (optional)",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "status",
    description = "Status information about dispatches",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the lookup failed",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ dispatch_id?: string }>
function M.func(input, opts)
  local session_ctx = opts.session_ctx or {}
  local session_id = session_ctx.dispatch_session_id or "default"

  if input.dispatch_id then
    local dispatch = DispatchRegistry.get(session_id, input.dispatch_id)
    if not dispatch then return nil, "Dispatch #" .. input.dispatch_id .. " not found" end
    return vim.json.encode({
      id = dispatch.id,
      status = dispatch.status,
      prompt = dispatch.prompt:sub(1, 200),
      last_message = dispatch.last_message,
      result = dispatch.result,
      error = dispatch.error,
      provider = dispatch.provider,
      model = dispatch.model,
    }),
      nil
  end

  -- Return all dispatches
  local context = DispatchRegistry.get_context(session_id)
  if context == "" then return "No dispatches have been created yet.", nil end
  return context, nil
end

return M
