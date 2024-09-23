local LRUCache = require("avante.utils.lru_cache")

---@class avante.utils.file
local M = {}

local api = vim.api
local fn = vim.fn

local _file_content_lru_cache = LRUCache:new(60)

api.nvim_create_autocmd("BufWritePost", {
  callback = function()
    local filepath = api.nvim_buf_get_name(0)
    local keys = _file_content_lru_cache:keys()
    if vim.tbl_contains(keys, filepath) then
      local content = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n")
      _file_content_lru_cache:set(filepath, content)
    end
  end,
})

function M.read_content(filepath)
  local cached_content = _file_content_lru_cache:get(filepath)
  if cached_content then return cached_content end

  local content = fn.readfile(filepath)
  if content then
    content = table.concat(content, "\n")
    _file_content_lru_cache:set(filepath, content)
    return content
  end

  return nil
end

return M
