local Path = require("plenary.path")
local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "view"

M.description =
  [[The view tool allows you to examine the contents of a file or list the contents of a directory. It can read the entire file or a specific range of lines. If the file content is already in the context, do not use this tool.
IMPORTANT NOTE: If the file content exceeds a certain size, the returned content will be truncated, and `is_truncated` will be set to true. If `is_truncated` is true, use the `view_range` parameter to specify the range to view.
]]

M.enabled = function(opts)
  if opts.user_input:match("@read_global_file") then return false end
  for _, message in ipairs(opts.history_messages) do
    if message.role == "user" then
      local content = message.content
      if type(content) == "string" and content:match("@read_global_file") then return false end
      if type(content) == "table" then
        for _, item in ipairs(content) do
          if type(item) == "string" and item:match("@read_global_file") then return false end
        end
      end
    end
  end
  return true
end

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      description = "The path to the file in the current project scope",
      type = "string",
    },
    {
      name = "view_range",
      description = "The range of the file to view. This parameter only applies when viewing files, not directories.",
      type = "object",
      optional = true,
      fields = {
        {
          name = "start_line",
          description = "The start line of the range, 1-indexed",
          type = "integer",
        },
        {
          name = "end_line",
          description = "The end line of the range, 1-indexed, and -1 for the end line means read to the end of the file",
          type = "integer",
        },
      },
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "content",
    description = "Contents of the file",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the file was not read successfully",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ path: string, view_range?: { start_line: integer, end_line: integer } }>
function M.func(opts, on_log, on_complete, session_ctx)
  if on_log then on_log("path: " .. opts.path) end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "Path not found: " .. abs_path end
  if Path:new(abs_path):is_dir() then return false, "Path is a directory: " .. abs_path end
  local file = io.open(abs_path, "r")
  if not file then return false, "file not found: " .. abs_path end
  local lines = Utils.read_file_from_buf_or_disk(abs_path)
  if opts.view_range then
    local start_line = opts.view_range.start_line
    local end_line = opts.view_range.end_line
    if start_line and end_line and lines then lines = vim.list_slice(lines, start_line, end_line) end
  end
  local truncated_lines = {}
  local is_truncated = false
  local size = 0
  for _, line in ipairs(lines or {}) do
    size = size + #line
    if size > 2048 * 10 then
      is_truncated = true
      break
    end
    table.insert(truncated_lines, line)
  end
  local content = truncated_lines and table.concat(truncated_lines, "\n") or ""
  local result = vim.json.encode({
    content = content,
    is_truncated = is_truncated,
  })
  if not on_complete then return result, nil end
  on_complete(result, nil)
end

return M
