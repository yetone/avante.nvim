local Path = require("plenary.path")
local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "view"

M.description = [[
Use this tool to view the content of a file within the current project.
- Use it to examine code, configuration files, or any text-based file.
- Specify the 'path' parameter as the relative path to the file within the project.
- You MUST provide a valid file path that exists in the project.
- If you have just listed files using the 'ls' tool, you can use the file paths from that list as input to this 'view' tool.
- Do NOT use this tool if the file content is already provided in the current context.

Example:
To view the file 'init.lua' in the current directory, use:
{ "name": "view", "parameters": { "path": "init.lua" } }
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
      description = [[
REQUIRED: The relative path to the file you want to view within the current project.
- Example: "lua/avante/llm.lua"
- MUST be a valid file path that exists in the project.
- If you just used the 'ls' tool, use the file paths from its 'entries' output here.
      ]],
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
  if not on_complete then return false, "on_complete not provided" end

  -- Validate required 'path' parameter
  if not opts.path or type(opts.path) ~= "string" or opts.path == "" then
    return nil, "Error: The 'path' parameter is required for the view tool and must be a non-empty string."
  end
  if on_log then on_log("path: " .. opts.path) end
  if Helpers.already_in_context(opts.path) then
    on_complete(nil, "Ooooops! This file is already in the context! Why you are trying to read it again?")
    return
  end
  if session_ctx then
    local view_history = session_ctx.view_history or {}
    local uniform_path = Utils.uniform_path(opts.path)
    if view_history[uniform_path] then
      on_complete(nil, "Ooooops! You have already viewed this file! Why you are trying to read it again?")
      return
    end
    view_history[uniform_path] = true
    session_ctx.view_history = view_history
  end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "Path not found: " .. abs_path end
  if Path:new(abs_path):is_dir() then
    local files = vim.fn.glob(abs_path .. "/*", false, true)
    if #files == 0 then return false, "Directory is empty: " .. abs_path end
    local result = {}
    for _, file in ipairs(files) do
      if not Path:new(file):is_file() then goto continue end
      local lines = Utils.read_file_from_buf_or_disk(file)
      local content = lines and table.concat(lines, "\n") or ""
      table.insert(result, { path = file, content = content })
      ::continue::
    end
    on_complete(vim.json.encode(result), nil)
    return
  end
  local file = io.open(abs_path, "r")
  if not file then return false, "file not found: " .. abs_path end
  local lines = Utils.read_file_from_buf_or_disk(abs_path)
  if opts.view_range then
    local start_line = opts.view_range.start_line
    local end_line = opts.view_range.end_line
    if start_line and end_line and lines then lines = vim.list_slice(lines, start_line, end_line) end
  end
  local content = lines and table.concat(lines, "\n") or ""
  on_complete(content, nil)
end

return M
