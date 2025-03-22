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
---@param callback fun(yes: boolean)
---@param opts? { focus?: boolean }
---@return avante.ui.Confirm | nil
function M.confirm(message, callback, opts)
  local Confirm = require("avante.ui.confirm")
  local sidebar = require("avante").get()
  if not sidebar or not sidebar.input_container or not sidebar.input_container.winid then
    Utils.error("Avante sidebar not found", { title = "Avante" })
    callback(false)
    return
  end
  local confirm_opts = vim.tbl_deep_extend("force", { container_winid = sidebar.input_container.winid }, opts or {})
  M.confirm_popup = Confirm:new(message, callback, confirm_opts)
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

return M
