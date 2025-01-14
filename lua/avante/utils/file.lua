local LRUCache = require("avante.utils.lru_cache")
local Filetype = require("plenary.filetype")

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

function M.exists(filepath)
  local stat = vim.loop.fs_stat(filepath)
  return stat ~= nil
end

function M.is_in_cwd(filepath)
  local cwd = vim.fn.getcwd()
  -- Make both paths absolute for comparison
  local abs_filepath = vim.fn.fnamemodify(filepath, ":p")
  local abs_cwd = vim.fn.fnamemodify(cwd, ":p")
  -- Check if filepath starts with cwd
  return abs_filepath:sub(1, #abs_cwd) == abs_cwd
end

function M.get_file_icon(filepath)
  local filetype = Filetype.detect(filepath, {}) or "unknown"
  ---@type string
  local icon
  ---@diagnostic disable-next-line: undefined-field
  if _G.MiniIcons ~= nil then
    ---@diagnostic disable-next-line: undefined-global
    icon, _, _ = MiniIcons.get("filetype", filetype) -- luacheck: ignore
  else
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if ok then
      icon = devicons.get_icon(filepath, filetype, { default = false })
      if not icon then
        icon = devicons.get_icon(filepath, nil, { default = true })
        icon = icon or " "
      end
    else
      icon = ""
    end
  end
  return icon
end

local function _detect_filetype(path)
  local filetype = vim.filetype.match({ filename = path })
  -- vim.filetype.match is not guaranteed to work on filename alone (see https://github.com/neovim/neovim/issues/27265)
  if not filetype then
    for _, buf in ipairs(vim.fn.getbufinfo()) do
      if vim.fn.fnamemodify(buf.name, ":p") == path then return vim.filetype.match({ buf = buf.bufnr }) end
    end
    local bufn = vim.fn.bufadd(path)
    vim.fn.bufload(bufn)
    filetype = vim.filetype.match({ buf = bufn })
  end
  return filetype
end

local _detected_filetypes = {}

local function _get_filetype(path)
  local ext = vim.fn.fnamemodify(path, ":e")
  if _detected_filetypes[ext] then return _detected_filetypes[ext] end
  local filetype = _detect_filetype(path)
  _detected_filetypes[ext] = filetype
  return filetype
end

---@class DetectFileTypeOpts
---@field bufnr number
---@field content string[]
---
---detect the file type using builtin vim.filetype or plenary filetype as a fallback
---@param filepath string
---@return string
function M.detect_filetype(filepath) return _get_filetype(filepath) or "unknown" end

return M
