local Utils = require("avante.utils")
local Helpers = require("avante.llm_tools.helpers")
local Base = require("avante.llm_tools.base")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "ls"

M.description =
  "Lists files and directories within the project scope. Can target specific subdirectories using 'rel_path' and control recursion depth with 'max_depth'. Use initially to see the project root, then use 'rel_path' to explore specific subdirectories found in the initial listing."

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "rel_path",
      description = "Optional. The directory path relative to the project root to list. Use this parameter AFTER an initial listing to explore a specific subdirectory seen in the results. If omitted or '.', lists the project root. Example: To list contents of 'src/utils', set this to 'src/utils'.",
      type = "string",
      optional = true, -- Mark rel_path as optional
    },
    {
      name = "max_depth",
      description = "Optional. Controls recursion depth. `0` means fully recursive (list everything). `1` lists only the immediate contents. `6` (default) lists contents up to 6 levels deep. Omit for default depth 6.",
      type = "integer",
      optional = true, -- Explicitly mark as optional in schema terms
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "entries",
    description = "List of file paths and directorie paths in the given directory",
    type = "string[]",
  },
  {
    name = "error",
    description = "Error message if the directory was not listed successfully",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ rel_path?: string, max_depth?: integer }>
function M.func(opts, on_log)
  Utils.debug("ls.func: Received opts:", opts) -- Debug: Log the entire opts table

  -- Handle optional rel_path, default to project root "."
  Utils.debug("ls.func: opts.rel_path before assignment:", opts.rel_path) -- Debug: Log raw rel_path
  local rel_path = opts.rel_path
  if not rel_path or rel_path == "" then
    rel_path = "." -- Default to current directory (project root)
    if on_log then on_log("using default path") end
  end

  local abs_path = Helpers.get_abs_path(rel_path) -- Use the potentially defaulted rel_path
  -- Check if get_abs_path failed
  if not abs_path then return "", "Failed to resolve or access the specified path: " .. rel_path end

  -- Debug: Log the path being checked for permissions
  Utils.debug("ls: Checking permission for abs_path:", abs_path)
  if not Helpers.has_permission_to_access(abs_path) then
    Utils.debug("ls: Permission denied for abs_path:", abs_path) -- Debug: Confirm permission denied
    return "", "No permission to access path: " .. abs_path
  end
  if on_log then on_log("path: " .. abs_path) end

  -- Set default max_depth if not provided by the LLM
  Utils.debug("ls.func: opts.max_depth before assignment:", opts.max_depth) -- Debug: Log raw max_depth
  local max_depth = opts.max_depth
  if max_depth == nil then
    max_depth = 6 -- Default to depth 6
    if on_log then on_log("using default depth") end
  else
    if on_log then on_log("max depth: " .. tostring(max_depth)) end
  end

  local files = Utils.scan_directory({
    directory = abs_path,
    add_dirs = true,
    max_depth = max_depth, -- Use the potentially defaulted value
  })
  local filepaths = {}
  for _, file in ipairs(files) do
    local uniform_path = Utils.uniform_path(file)
    table.insert(filepaths, uniform_path)
  end
  return vim.json.encode(filepaths), nil
end

return M
