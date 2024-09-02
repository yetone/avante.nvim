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

---@param event string | string[] (string|array) Event(s) that will trigger the handler
---@param opts vim.api.keyset.create_autocmd.opts
---@return integer
function vim.api.nvim_create_autocmd(event, opts) end

---@class vim.api.keyset.user_command.callback_opts
---@field name string
---@field args string
---@field fargs string[]
---@field nargs? integer | string
---@field bang? boolean
---@field line1? integer
---@field line2? integer
---@field range? integer
---@field count? integer
---@field reg? string
---@field mods? string
---@field smods? UserCommandSmods

---@class UserCommandSmods
---@field browse boolean
---@field confirm boolean
---@field emsg_silent boolean
---@field hide boolean
---@field horizontal boolean
---@field keepalt boolean
---@field keepjumps boolean
---@field keepmarks boolean
---@field keeppatterns boolean
---@field lockmarks boolean
---@field noautocmd boolean
---@field noswapfile boolean
---@field sandbox boolean
---@field silent boolean
---@field split string
---@field tab integer
---@field unsilent boolean
---@field verbose integer
---@field vertical boolean

---@class vim.api.keyset.user_command.opts: vim.api.keyset.user_command
---@field nargs? integer | string
---@field range? integer
---@field bang? boolean
---@field desc? string
---@field force? boolean
---@field complete? fun(prefix: string, line: string, pos?: integer): string[]
---@field preview? fun(opts: vim.api.keyset.user_command.callback_opts, ns: integer, buf: integer): nil

---@alias vim.api.keyset.user_command.callback fun(opts?: vim.api.keyset.user_command.callback_opts):nil

---@param name string
---@param command vim.api.keyset.user_command.callback
---@param opts? vim.api.keyset.user_command.opts
function vim.api.nvim_create_user_command(name, command, opts) end

---@type boolean
vim.g.avante_login = vim.g.avante_login
