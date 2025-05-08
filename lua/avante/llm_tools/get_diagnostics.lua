local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "get_diagnostics"

M.description = "Get diagnostics from a specific file"

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      description = "The path to the file in the current project scope",
      type = "string",
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "diagnostics",
    description = "The diagnostics for the file",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the replacement failed",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ path: string, diff: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  if not opts.path then return false, "pathf are required" end
  if on_log then on_log("path: " .. opts.path) end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not on_complete then return false, "on_complete is required" end
  local diagnostics = Utils.lsp.get_diagnostics_from_filepath(abs_path)
  local jsn_str = vim.json.encode(diagnostics)
  on_complete(true, jsn_str)
end

return M
