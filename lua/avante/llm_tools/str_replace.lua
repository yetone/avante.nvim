local Base = require("avante.llm_tools.base")
local Config = require("avante.config")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "str_replace"

M.description =
  "The str_replace tool allows you to replace a specific string in a file with a new string. This is used for making precise edits."

-- function M.enabled() return Config.provider:match("ollama") ~= nil end
function M.enabled() return false end

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
      name = "old_str",
      description = "The text to replace (must match exactly, including whitespace and indentation)",
      type = "string",
    },
    {
      name = "new_str",
      description = "The new text to insert in place of the old text",
      type = "string",
    },
  },
  usage = {
    path = "File path here",
    old_str = "old str here",
    new_str = "new str here",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "True if the replacement was successful, false otherwise",
    type = "boolean",
  },
  {
    name = "error",
    description = "Error message if the replacement failed",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ path: string, old_str: string, new_str: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  local replace_in_file = require("avante.llm_tools.replace_in_file")
  local diff = "<<<<<<< SEARCH\n" .. opts.old_str .. "\n=======\n" .. opts.new_str .. "\n>>>>>>> REPLACE"
  local new_opts = {
    path = opts.path,
    diff = diff,
  }
  return replace_in_file.func(new_opts, on_log, on_complete, session_ctx)
end

return M
