---NOTE: this module is inspired by https://github.com/HakonHarnes/img-clip.nvim/tree/main
---@see https://github.com/ekickx/clipboard-image.nvim/blob/main/lua/clipboard-image/paste.lua

local Path = require("plenary.path")
local Utils = require("avante.utils")
local Config = require("avante.config")

---@class AvanteClipboard
---@field clip_cmd string
---@field get_clip_cmd fun(): string
---@field has_content fun(): boolean
---@field get_base64_content fun(): string
---@field save_content fun(filename: string): boolean
---
---@class avante.Clipboard: AvanteClipboard
local M = {}

M.paste_directory = Path:new(Config.history.storage_path):joinpath("pasted_images")

M.setup = function()
  if not M.paste_directory:exists() then
    M.paste_directory:mkdir({ parent = true })
  end
end

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
