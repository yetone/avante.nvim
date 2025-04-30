local Path = require("plenary.path")
local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "create"

M.description = "The create tool allows you to create a new file with specified content."

function M.enabled() return require("avante.config").mode == "agentic" end

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      description = "The path where the new file should be created",
      type = "string",
    },
    {
      name = "file_text",
      description = "The content to write to the new file",
      type = "string",
    },
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

---@type AvanteLLMToolFunc<{ path: string, file_text: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  if not on_complete then return false, "on_complete not provided" end
  if on_log then on_log("path: " .. opts.path) end
  if Helpers.already_in_context(opts.path) then
    on_complete(nil, "Ooooops! This file is already in the context! Why you are trying to create it again?")
    return
  end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if opts.file_text == nil then return false, "file_text not provided" end
  if Path:new(abs_path):exists() then return false, "File already exists: " .. abs_path end
  local lines = vim.split(opts.file_text, "\n")
  local bufnr, err = Helpers.get_bufnr(abs_path)
  if err then return false, err end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  Helpers.confirm("Are you sure you want to create this file?", function(ok, reason)
    if not ok then
      -- close the buffer
      vim.api.nvim_buf_delete(bufnr, { force = true })
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    -- save the file
    Path:new(abs_path):parent():mkdir({ parents = true, exists_ok = true })
    local current_winid = vim.api.nvim_get_current_win()
    local winid = Utils.get_winid(bufnr)
    vim.api.nvim_set_current_win(winid)
    vim.cmd("noautocmd write")
    vim.api.nvim_set_current_win(current_winid)
    on_complete(true, nil)
  end, { focus = true }, session_ctx)
end

return M
