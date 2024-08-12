local M = {}

local bit = require("bit")
local rshift, band = bit.rshift, bit.band

--- Returns a table containing the RGB values encoded inside 24 least
--- significant bits of the number @rgb_24bit
---
--@param rgb_24bit (number) 24-bit RGB value
--@returns (table) with keys 'r', 'g', 'b' in [0,255]
local function decode_24bit_rgb(rgb_24bit)
  vim.validate({ rgb_24bit = { rgb_24bit, "n", true } })
  local r = band(rshift(rgb_24bit, 16), 255)
  local g = band(rshift(rgb_24bit, 8), 255)
  local b = band(rgb_24bit, 255)
  return { r = r, g = g, b = b }
end

local function alter(attr, percent)
  return math.floor(attr * (100 + percent) / 100)
end

---@source https://stackoverflow.com/q/5560248
---@see: https://stackoverflow.com/a/37797380
---Darken a specified hex color
---@param color string
---@param percent number
---@return string
function M.shade_color(color, percent)
  local rgb = decode_24bit_rgb(color)
  if not rgb.r or not rgb.g or not rgb.b then
    return "NONE"
  end
  local r, g, b = alter(rgb.r, percent), alter(rgb.g, percent), alter(rgb.b, percent)
  r, g, b = math.min(r, 255), math.min(g, 255), math.min(b, 255)
  return string.format("#%02x%02x%02x", r, g, b)
end

return M
