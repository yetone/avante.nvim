local Helpers = require("avante.llm_tools.helpers")
local Base = require("avante.llm_tools.base")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "glob"

M.description = 'Fast file pattern matching using glob patterns like "**/*.js", in current project scope'

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "pattern",
      description = "Glob pattern",
      type = "string",
    },
    {
      name = "rel_path",
      description = "Relative path to the project directory, as cwd",
      type = "string",
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "matches",
    description = "List of matched files",
    type = "string",
  },
  {
    name = "err",
    description = "Error message",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ rel_path: string, pattern: string }>
function M.func(opts, on_log)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  if on_log then on_log("pattern: " .. opts.pattern) end
  local files = vim.fn.glob(abs_path .. "/" .. opts.pattern, true, true)
  return vim.json.encode(files), nil
end

return M
