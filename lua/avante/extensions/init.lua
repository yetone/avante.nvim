---@class avante.extensions
---@field tokens avante.utils.tokens
---@field root avante.utils.root
---@field file avante.utils.file
---@field history avante.utils.history
---@field environment avante.utils.environment
---@field lsp avante.utils.lsp
local M = {}

setmetatable(M, {
  __index = function(t, k)
    ---@diagnostic disable-next-line: no-unknown
    t[k] = require("avante.extensions." .. k)
    return t[k]
  end,
})
