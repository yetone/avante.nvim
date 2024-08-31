local fn, api = vim.fn, vim.api
local Path = require("plenary.path")
local Config = require("avante.config")

---@class avante.Path
---@field history_path Path
---@field cache_path Path
local P = {}

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

P.history = M

P.setup = function()
  local history_path = Path:new(Config.history.storage_path)
  if not history_path:exists() then
    history_path:mkdir({ parents = true })
  end
  P.history_path = history_path

  local cache_path = Path:new(vim.fn.stdpath("cache") .. "/avante")
  if not cache_path:exists() then
    cache_path:mkdir({ parents = true })
  end
  P.cache_path = cache_path
end

return P
