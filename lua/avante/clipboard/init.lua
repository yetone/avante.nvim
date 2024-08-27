---NOTE: this module is inspired by https://github.com/HakonHarnes/img-clip.nvim/tree/main

local Utils = require("avante.utils")

---@class AvanteClipboard
---@field clip_cmd string
---@field get_clip_cmd fun(): string
---@field has_content fun(): boolean
---@field get_content fun(): string
---
---@class avante.Clipboard: AvanteClipboard
local M = {}

return setmetatable(M, {
  __index = function(t, k)
    local os_mapping = Utils.get_os_name()
    ---@type AvanteClipboard
    local impl = require("avante.clipboard." .. os_mapping)
    if impl[k] ~= nil then
      return impl[k]
    elseif t[k] ~= nil then
      return t[k]
    else
      error("Failed to find clipboard implementation for " .. os_mapping)
    end
  end,
})
