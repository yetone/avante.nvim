---@class avante.extensions
local M = {}

setmetatable(M, {
  __index = function(t, k)
    ---@diagnostic disable-next-line: no-unknown
    t[k] = require("avante.extensions." .. k)
    return t[k]
  end,
})
