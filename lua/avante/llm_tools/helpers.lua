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
  if Path:new(rel_path):is_absolute() then return rel_path end
  local project_root = Utils.get_project_root()
  local p = tostring(Path:new(project_root):joinpath(rel_path):absolute())
  if p:sub(-2) == "/." then p = p:sub(1, -3) end
  return p
end

---@param message string
---@param callback fun(yes: boolean, reason?: string)
---@param confirm_opts? { focus?: boolean }
---@param session_ctx? table
---@return avante.ui.Confirm | nil
function M.confirm(message, callback, confirm_opts, session_ctx)
  if session_ctx and session_ctx.always_yes then
    callback(true)
    return
  end
  local Confirm = require("avante.ui.confirm")
  local sidebar = require("avante").get()
  if not sidebar or not sidebar.input_container or not sidebar.input_container.winid then
    Utils.error("Avante sidebar not found", { title = "Avante" })
    callback(false)
    return
  end
  confirm_opts = vim.tbl_deep_extend("force", { container_winid = sidebar.input_container.winid }, confirm_opts or {})
  M.confirm_popup = Confirm:new(message, function(type, reason)
    if type == "yes" then
      callback(true)
      return
    end
    if type == "all" then
      if session_ctx then session_ctx.always_yes = true end
      callback(true)
      return
    end
    if type == "no" then
      callback(false, reason)
      return
    end
  end, confirm_opts)
  M.confirm_popup:open()
  return M.confirm_popup
end

---@param abs_path string
---@return boolean
function M.is_ignored(abs_path)
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
function M.has_permission_to_access(abs_path)
  if not Path:new(abs_path):is_absolute() then return false end
  local project_root = Utils.get_project_root()
  if abs_path:sub(1, #project_root) ~= project_root then return false end
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
  local current_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(sidebar.code.winid)
  local bufnr = Utils.get_or_create_buffer_with_filepath(abs_path)
  vim.api.nvim_set_current_win(current_winid)
  return bufnr, nil
end

return M
