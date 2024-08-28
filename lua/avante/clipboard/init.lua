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

---@type Path
local paste_directory = nil

---@return Path
local function get_paste_directory()
  if paste_directory then
    return paste_directory
  end
  paste_directory = Path:new(Config.history.storage_path):joinpath("pasted_images")
  return paste_directory
end

M.setup = function()
  get_paste_directory()

  if not paste_directory:exists() then
    paste_directory:mkdir({ parent = true })
  end
end

return setmetatable(M, {
  __index = function(t, k)
    local os_mapping = Utils.get_os_name()
    ---@type AvanteClipboard
    local impl = require("avante.clipboard." .. os_mapping)
    if impl[k] ~= nil then
      return impl[k]
    end
    return t[k]
  end,
})
