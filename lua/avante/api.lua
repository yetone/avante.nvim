local Config = require("avante.config")
local Utils = require("avante.utils")

---@class avante.ApiToggle
---@operator call(): boolean
---@field debug ToggleBind.wrap
---@field hint ToggleBind.wrap
---
---@class avante.Api
---@field ask fun(): boolean
---@field edit fun(): nil
---@field refresh fun(): nil
---@field build fun(): boolean
---@field toggle avante.ApiToggle

return setmetatable({}, {
  __index = function(t, k)
    local module = require("avante")
    ---@class AvailableApi: ApiCaller
    ---@field api? boolean
    local has = module[k]
    if type(has) ~= "table" or not has.api and not Config.silent_warning then
      Utils.warn(k .. " is not a valid avante's API method", { once = true })
      return
    end
    t[k] = has
    return t[k]
  end,
}) --[[@as avante.Api]]
