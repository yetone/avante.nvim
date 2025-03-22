local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "read_file"

M.description =
  "Read the contents of a file in current project scope. If the file content is already in the context, do not use this tool."

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
      name = "rel_path",
      description = "Relative path to the file in current project scope",
      type = "string",
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

---@type AvanteLLMToolFunc<{ rel_path: string }>
function M.func(opts, on_log)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  local file = io.open(abs_path, "r")
  if not file then return "", "file not found: " .. abs_path end
  local lines = Utils.read_file_from_buf_or_disk(abs_path)
  local content = lines and table.concat(lines, "\n") or ""
  return content, nil
end

return M
