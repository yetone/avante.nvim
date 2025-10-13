---@class avante.Utils
local M = {}

---Join path segments into a single path
---@param ... string Path segments
---@return string Combined path
function M.join_paths(...)
  local args = { ... }
  if #args == 0 then return "" end

  local path = args[1]
  for i = 2, #args do
    local segment = args[i]
    if segment then
      if path:sub(-1) == "/" or path:sub(-1) == "\\" then
        path = path .. segment
      else
        path = path .. "/" .. segment
      end
    end
  end

  return path
end

---Check if path exists
---@param path string
---@return boolean
function M.path_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil
end

---Debug logging
---@param message string
---@param data? table
function M.debug(message, data)
  if vim.g.avante_debug then
    local log_msg = "[Avante Debug] " .. message
    if data then
      log_msg = log_msg .. " | Data: " .. vim.inspect(data)
    end
    vim.notify(log_msg, vim.log.levels.DEBUG)
  end
end

---Warning notifications
---@param message string
---@param opts? table
function M.warn(message, opts)
  opts = opts or {}
  local title = opts.title or "Avante"
  vim.notify(message, vim.log.levels.WARN, { title = title })
end

---Info notifications
---@param message string
---@param opts? table
function M.info(message, opts)
  opts = opts or {}
  local title = opts.title or "Avante"
  vim.notify(message, vim.log.levels.INFO, { title = title })
end

---Check if plugin exists
---@param plugin_name string
---@return boolean
function M.has(plugin_name)
  local ok, _ = pcall(require, plugin_name)
  return ok
end

---Safe keymap setting
---@param mode string|string[]
---@param lhs string
---@param rhs function|string
---@param opts? table
function M.safe_keymap_set(mode, lhs, rhs, opts)
  if not lhs or lhs == "" then return end

  opts = opts or {}
  opts.silent = opts.silent ~= false

  pcall(vim.keymap.set, mode, lhs, rhs, opts)
end

---Toggle wrapper utility
---@param config table
---@return function
function M.toggle_wrap(config)
  return function()
    local current = config.get()
    local new_state = not current
    config.set(new_state)

    local state_text = new_state and "enabled" or "disabled"
    M.info(config.name .. " " .. state_text)

    return new_state
  end
end

---Get project root directory
---@return string
function M.get_project_root()
  local root_patterns = { ".git", ".gitignore", "package.json", "Cargo.toml", "pyproject.toml" }
  local current_dir = vim.fn.expand("%:p:h")

  for _, pattern in ipairs(root_patterns) do
    local root = vim.fn.finddir(pattern, current_dir .. ";")
    if root ~= "" then
      return vim.fn.fnamemodify(root, ":h")
    end

    local file = vim.fn.findfile(pattern, current_dir .. ";")
    if file ~= "" then
      return vim.fn.fnamemodify(file, ":h")
    end
  end

  -- Fallback to current working directory
  return vim.fn.getcwd()
end

---Check if buffer is sidebar buffer
---@param bufnr number
---@return boolean
function M.is_sidebar_buffer(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return bufname:match("Avante") ~= nil or vim.bo[bufnr].filetype == "Avante"
end

---Get chat mentions (placeholder)
---@return table
function M.get_chat_mentions()
  return {}
end

---Get mentions (placeholder)
---@return table
function M.get_mentions()
  return {}
end

return M