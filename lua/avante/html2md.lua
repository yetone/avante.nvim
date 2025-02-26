---@class AvanteHtml2Md
---@field fetch_md fun(url: string): string
local _html2md_lib = nil

local M = {}

---@return AvanteHtml2Md|nil
function M._init_html2md_lib()
  if _html2md_lib ~= nil then return _html2md_lib end

  local ok, core = pcall(require, "avante_html2md")
  if not ok then return nil end

  _html2md_lib = core
  return _html2md_lib
end

function M.setup() vim.defer_fn(M._init_html2md_lib, 1000) end

function M.fetch_md(url)
  local html2md_lib = M._init_html2md_lib()
  if not html2md_lib then return nil, "Failed to load avante_html2md" end

  return html2md_lib.fetch_md(url)
end

return M
