---@meta

---@class vim.api.create_autocmd.callback.args
---@field id number
---@field event string
---@field group number?
---@field match string
---@field buf number
---@field file string
---@field data any

---@class vim.api.keyset.create_autocmd.opts: vim.api.keyset.create_autocmd
---@field callback? fun(ev:vim.api.create_autocmd.callback.args):boolean?

--- @param event string | string[] (string|array) Event(s) that will trigger the handler
--- @param opts vim.api.keyset.create_autocmd.opts
--- @return integer
function vim.api.nvim_create_autocmd(event, opts) end

---@type boolean
vim.g.avante_login = vim.g.avante_login
