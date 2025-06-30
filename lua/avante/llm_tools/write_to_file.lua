local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "write_to_file"

M.description =
  "Request to write content to a file at the specified path. If the file exists, it will be overwritten with the provided content. If the file doesn't exist, it will be created. This tool will automatically create any directories needed to write the file."

function M.enabled() return require("avante.config").mode == "agentic" end

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      get_description = function()
        local res = ("The path of the file to write to (relative to the current working directory {{cwd}})"):gsub(
          "{{cwd}}",
          Utils.get_project_root()
        )
        return res
      end,
      type = "string",
    },
    {
      --- IMPORTANT: Using "the_content" instead of "content" is to avoid LLM streaming generating function parameters in alphabetical order, which would result in generating "path" after "content", making it impossible to achieve a stream diff view.
      name = "the_content",
      description = "The content to write to the file. ALWAYS provide the COMPLETE intended content of the file, without any truncation or omissions. You MUST include ALL parts of the file, even if they haven't been modified.",
      type = "string",
    },
  },
  usage = {
    path = "File path here",
    the_content = "File content here",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "Whether the file was created successfully",
    type = "boolean",
  },
  {
    name = "error",
    description = "Error message if the file was not created successfully",
    type = "string",
    optional = true,
  },
}

--- IMPORTANT: Using "the_content" instead of "content" is to avoid LLM streaming generating function parameters in alphabetical order, which would result in generating "path" after "content", making it impossible to achieve a stream diff view.
---@type AvanteLLMToolFunc<{ path: string, content: string, the_content?: string, streaming?: boolean, tool_use_id?: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  if opts.the_content ~= nil then
    opts.content = opts.the_content
    opts.the_content = nil
  end
  if not on_complete then return false, "on_complete not provided" end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if opts.content == nil then return false, "content not provided" end
  local old_lines = Utils.read_file_from_buf_or_disk(abs_path)
  local old_content = table.concat(old_lines or {}, "\n")
  local str_replace = require("avante.llm_tools.str_replace")
  local new_opts = {
    path = opts.path,
    old_str = old_content,
    new_str = opts.content,
    streaming = opts.streaming,
    tool_use_id = opts.tool_use_id,
  }
  return str_replace.func(new_opts, on_log, on_complete, session_ctx)
end

return M
