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
      description = "REQUIRED Glob pattern (e.g., '**/*.lua')",
      type = "string",
    },
    {
      name = "rel_path",
      description = "Relative path to the project directory to use as the current working directory (cwd). Defaults to project root if omitted.",
      type = "string",
      optional = true, -- Mark rel_path as optional, handle default below
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

---@type AvanteLLMToolFunc<{ rel_path?: string, pattern: string }>
function M.func(opts, on_log)
  -- Validate required parameters
  -- Check if pattern is missing, not a string, or empty
  if not opts.pattern or type(opts.pattern) ~= "string" or opts.pattern == "" then
    return nil, "Error: The 'pattern' parameter is required for the glob tool and must be a non-empty string."
  end

  -- Handle optional rel_path, default to project root "."
  local rel_path = opts.rel_path or "."

  local abs_path = Helpers.get_abs_path(rel_path) -- Use the potentially defaulted rel_path
  if not Helpers.has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  if on_log then on_log("pattern: " .. opts.pattern) end
  local files = vim.fn.glob(abs_path .. "/" .. opts.pattern, true, true)
  return vim.json.encode(files), nil
end

return M
