local fn, api = vim.fn, vim.api
local Path = require("plenary.path")
local Config = require("avante.config")

local M = {}

local H = {}

---@param bufnr integer
---@return string
H.filename = function(bufnr)
  local code_buf_name = api.nvim_buf_get_name(bufnr)
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(code_buf_name, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  return fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g") .. ".json"
end

---@param bufnr integer
---@return Path
M.get = function(bufnr)
  return Path:new(Config.history.storage_path):joinpath(H.filename(bufnr))
end

---@param bufnr integer
M.load = function(bufnr)
  local history_file = M.get(bufnr)
  if history_file:exists() then
    local content = history_file:read()
    return content ~= nil and vim.json.decode(content) or {}
  end
  return {}
end

---@param bufnr integer
---@param history table
M.save = function(bufnr, history)
  local history_file = M.get(bufnr)
  history_file:write(vim.json.encode(history), "w")
end

M.setup = function()
  local history_dir = Path:new(Config.history.storage_path)
  if not history_dir:exists() then
    history_dir:mkdir({ parents = true })
  end
end

return M
