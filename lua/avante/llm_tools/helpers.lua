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
  Utils.debug("get_abs_path: Input rel_path:", rel_path) -- Debug log
  -- Check if already absolute first (less prone to errors)
  local is_abs_ok, is_abs = pcall(function()
    return Path:new(rel_path):is_absolute()
  end)
  Utils.debug("get_abs_path: is_absolute check result:", is_abs_ok and is_abs) -- Debug log
  if is_abs_ok and is_abs then
    Utils.debug("get_abs_path: Returning early as path is already absolute:", rel_path) -- Debug log
    return rel_path
  end

  local project_root = Utils.get_project_root()
  Utils.debug("get_abs_path: project_root:", project_root) -- Debug log
  if not project_root then
    Utils.error("get_abs_path: Project root not found.")
    return nil
  end

  local ok, abs_path_obj = pcall(function()
    return Path:new(project_root):joinpath(rel_path):absolute()
  end)
  Utils.debug("get_abs_path: pcall result (ok):", ok, "abs_path_obj:", abs_path_obj) -- Debug log
  if not ok or not abs_path_obj then
    Utils.warn(
      "get_abs_path: Failed to calculate absolute path for '" .. rel_path .. "'. Error: " .. tostring(abs_path_obj)
    ) -- abs_path_obj contains error on failure
    return nil
  end

  local p = tostring(abs_path_obj)
  Utils.debug("get_abs_path: Path after tostring:", p) -- Debug log
  -- Remove trailing '/.' if present (e.g., from joining with '.')
  if #p > 1 and p:sub(-2) == "/." then
    p = p:sub(1, -3)
  end
  Utils.debug("get_abs_path: Path after removing trailing /. :", p) -- Debug log
  Utils.debug("get_abs_path: Final return value:", p) -- Debug log (updated to show 'p')
  return p -- Return the absolute path directly
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

  -- Check negation patterns first
  for lua_pattern, original_pattern in pairs(gitignore_negate_patterns) do
    if rel_path:match(lua_pattern) then
      -- If a negation pattern matches, it's definitely NOT ignored
      return false
    end
  end

  -- Check ignore patterns
  for lua_pattern, original_pattern in pairs(gitignore_patterns) do
    if rel_path:match(lua_pattern) then
      -- Pattern matches. If it's a directory pattern, ensure path is actually a dir.
      if original_pattern:sub(-1) == "/" and not Path:new(abs_path):is_dir() then return false end -- Don't ignore file if pattern is for dir
      return true -- Otherwise, ignore
    end
  end

  return false -- Not ignored by any pattern
end

---@param abs_path string
---@return boolean
function M.has_permission_to_access(abs_path)
  Utils.debug("has_permission_to_access: Checking path:", abs_path) -- Debug log
  if not Path:new(abs_path):is_absolute() then return false end
  local project_root = Utils.get_project_root()
  Utils.debug("has_permission_to_access: Project root:", project_root) -- Debug log

  -- Normalize paths before comparison for robustness
  local normalized_abs_path = Utils.norm(abs_path)
  local normalized_project_root = project_root and Utils.norm(project_root) or nil -- Normalize only if project_root exists
  Utils.debug("has_permission_to_access: Normalized abs_path:", normalized_abs_path) -- Debug log
  Utils.debug("has_permission_to_access: Normalized project_root:", normalized_project_root) -- Debug log

  -- Allow access to the project root directory itself, regardless of gitignore
  local is_root = normalized_project_root and normalized_abs_path == normalized_project_root
  Utils.debug("has_permission_to_access: Is root comparison result:", is_root) -- Debug log

  if is_root then
    Utils.debug("has_permission_to_access: Allowing access because it is the project root.") -- Debug log
    return true
  end

  Utils.debug("has_permission_to_access: Path is not root, proceeding with checks.") -- Debug log
  if abs_path:sub(1, #project_root) ~= project_root then return false end

  local ignore_patterns, negate_patterns = Utils.parse_gitignore(project_root and Path:new(project_root):joinpath(".gitignore"):absolute() or nil)
  local ignored = M.is_ignored(abs_path, ignore_patterns, negate_patterns)
  Utils.debug("has_permission_to_access: Is ignored result:", ignored) -- Debug log
  Utils.debug("has_permission_to_access: Final return value:", not ignored) -- Debug log
  return not ignored
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
