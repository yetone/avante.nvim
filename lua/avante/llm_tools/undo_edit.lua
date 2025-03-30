local Path = require("plenary.path")
local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "undo_edit"

M.description = "The undo_edit tool allows you to revert the last edit made to a file."

function M.enabled() return require("avante.config").behaviour.enable_claude_text_editor_tool_mode end

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      description = "The path to the file whose last edit should be undone",
      type = "string",
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "True if the edit was undone successfully, false otherwise",
    type = "boolean",
  },
  {
    name = "error",
    description = "Error message if the edit was not undone successfully",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ path: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  if on_log then on_log("path: " .. opts.path) end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
  if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
  local bufnr, err = Helpers.get_bufnr(abs_path)
  if err then return false, err end
  local current_winid = vim.api.nvim_get_current_win()
  local winid = Utils.get_winid(bufnr)
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_set_current_win(current_winid)
  Helpers.confirm("Are you sure you want to undo edit this file?", function(ok, reason)
    if not ok then
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    vim.api.nvim_set_current_win(winid)
    -- run undo
    vim.cmd("undo")
    vim.api.nvim_set_current_win(current_winid)
    on_complete(true, nil)
  end, { focus = true }, session_ctx)
end

return M
