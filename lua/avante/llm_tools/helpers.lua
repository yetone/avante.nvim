local Utils = require("avante.utils")
local Path = require("plenary.path")

local M = {}

M.CANCEL_TOKEN = "__CANCELLED__"

-- Track cancellation state
M.is_cancelled = false
---@type avante.ui.Confirm
M.confirm_popup = nil

---@param rel_path string
---@return string
function M.get_abs_path(rel_path)
  local project_root = Utils.get_project_root()
  local p = Utils.join_paths(project_root, rel_path)
  if p:sub(-2) == "/." then p = p:sub(1, -3) end
  return p
end

---@param message string
---@param callback fun(yes: boolean, reason?: string)
---@param confirm_opts? { focus?: boolean }
---@param session_ctx? table
---@param tool_name? string -- Optional tool name to check against tool_permissions config
---@return avante.ui.Confirm | nil
function M.confirm(message, callback, confirm_opts, session_ctx, tool_name)
  if session_ctx and session_ctx.always_yes then
    callback(true)
    return
  end

  -- Check behaviour.auto_approve_tool_permissions config for auto-approval
  local Config = require("avante.config")
  local auto_approve = Config.behaviour.auto_approve_tool_permissions

  -- If auto_approve is true, auto-approve all tools
  if auto_approve == true then
    callback(true)
    return
  end

  -- If auto_approve is a table (array of tool names), check if this tool is in the list
  if type(auto_approve) == "table" and vim.tbl_contains(auto_approve, tool_name) then
    callback(true)
    return
  end
  local Confirm = require("avante.ui.confirm")
  local sidebar = require("avante").get()
  if not sidebar or not sidebar.containers.input or not sidebar.containers.input.winid then
    Utils.error("Avante sidebar not found", { title = "Avante" })
    callback(false)
    return
  end
  confirm_opts = vim.tbl_deep_extend("force", { container_winid = sidebar.containers.input.winid }, confirm_opts or {})
  if M.confirm_popup then M.confirm_popup:close() end
  M.confirm_popup = Confirm:new(message, function(type, reason)
    if type == "yes" then
      callback(true)
    elseif type == "all" then
      if session_ctx then session_ctx.always_yes = true end
      callback(true)
    elseif type == "no" then
      callback(false, reason)
    end
    M.confirm_popup = nil
  end, confirm_opts)
  M.confirm_popup:open()
  return M.confirm_popup
end

---@param abs_path string
---@return boolean
local function old_is_ignored(abs_path)
  local project_root = Utils.get_project_root()
  local gitignore_path = project_root .. "/.gitignore"
  local gitignore_patterns, gitignore_negate_patterns = Utils.parse_gitignore(gitignore_path)
  -- The checker should only take care of the path inside the project root
  -- Specifically, it should not check the project root itself
  -- Otherwise if the binary is named the same as the project root (such as Go binary), any paths
  -- insde the project root will be ignored
  local rel_path = Utils.make_relative_path(abs_path, project_root)
  return Utils.is_ignored(rel_path, gitignore_patterns, gitignore_negate_patterns)
end

---@param abs_path string
---@return boolean
function M.is_ignored(abs_path)
  local project_root = Utils.get_project_root()
  local cmd =
    string.format("git -C %s check-ignore %s", vim.fn.shellescape(project_root), vim.fn.shellescape(abs_path))

  local result = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  -- If command failed or git is not available, fall back to old method
  if exit_code ~= 0 and exit_code ~= 1 then return old_is_ignored(abs_path) end

  -- Check if result indicates this is not a git repository
  if result:sub(1, 26) == "fatal: not a git repository" then return old_is_ignored(abs_path) end

  -- git check-ignore returns:
  -- - exit code 0 and outputs the path if the file is ignored
  -- - exit code 1 and no output if the file is not ignored
  return exit_code == 0
end

---@param abs_path string
---@return boolean
function M.has_permission_to_access(abs_path)
  if not Path:new(abs_path):is_absolute() then return false end
  local project_root = Utils.get_project_root()
  -- allow if inside project root OR inside user config dir
  local config_dir = vim.fn.stdpath("config")
  local in_project = abs_path:sub(1, #project_root) == project_root
  local in_config = abs_path:sub(1, #config_dir) == config_dir
  if not in_project and not in_config then return false end
  return not M.is_ignored(abs_path)
end

---@param path string
---@return boolean
function M.already_in_context(path)
  local sidebar = require("avante").get()
  if sidebar and sidebar.file_selector then
    local rel_path = Utils.uniform_path(path)
    return vim.tbl_contains(sidebar.file_selector.selected_filepaths, rel_path)
  end
  return false
end

---@param path string
---@param session_ctx table
---@return boolean
function M.already_viewed(path, session_ctx)
  local view_history = session_ctx.view_history or {}
  local uniform_path = Utils.uniform_path(path)
  if view_history[uniform_path] then return true end
  return false
end

---@param path string
---@param session_ctx table
function M.mark_as_viewed(path, session_ctx)
  local view_history = session_ctx.view_history or {}
  local uniform_path = Utils.uniform_path(path)
  view_history[uniform_path] = true
  session_ctx.view_history = view_history
end

function M.mark_as_not_viewed(path, session_ctx)
  local view_history = session_ctx.view_history or {}
  local uniform_path = Utils.uniform_path(path)
  view_history[uniform_path] = nil
  session_ctx.view_history = view_history
end

---@param abs_path string
---@return integer bufnr
---@return string | nil error
function M.get_bufnr(abs_path)
  local sidebar = require("avante").get()
  if not sidebar then return 0, "Avante sidebar not found" end
  local bufnr ---@type integer
  vim.api.nvim_win_call(sidebar.code.winid, function()
    ---@diagnostic disable-next-line: param-type-mismatch
    pcall(vim.cmd, "edit " .. abs_path)
    bufnr = vim.api.nvim_get_current_buf()
  end)
  return bufnr, nil
end

return M
