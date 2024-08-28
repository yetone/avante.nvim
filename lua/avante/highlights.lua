local api = vim.api

local Config = require("avante.config")
local bit = require("bit")
local rshift, band = bit.rshift, bit.band

local Highlights = {
  TITLE = { name = "AvanteTitle", fg = "#1e222a", bg = "#98c379" },
  REVERSED_TITLE = { name = "AvanteReversedTitle", fg = "#98c379" },
  SUBTITLE = { name = "AvanteSubtitle", fg = "#1e222a", bg = "#56b6c2" },
  REVERSED_SUBTITLE = { name = "AvanteReversedSubtitle", fg = "#56b6c2" },
  THIRD_TITLE = { name = "AvanteThirdTitle", fg = "#ABB2BF", bg = "#353B45" },
  REVERSED_THIRD_TITLE = { name = "AvanteReversedThirdTitle", fg = "#353B45" },
}

Highlights.conflict = {
  CURRENT = { name = "AvanteConflictCurrent", bg = 4218238 }, -- #405d7e
  CURRENT_LABEL = { name = "AvanteConflictCurrentLabel", link = "CURRENT", shade = 60 },
  INCOMING = { name = "AvanteConflictIncoming", bg = 3229523 }, -- #314753
  INCOMING_LABEL = { name = "AvanteConflictIncomingLabel", link = "INCOMING", shade = 60 },
  ANCESTOR = { name = "AvanteConflictAncestor", bg = 6824314 }, -- #68217A
  ANCESTOR_LABEL = { name = "AvanteConflictAncestorLabel", link = "ANCESTOR", shade = 60 },
}

--- helper
local H = {}

local M = {}

M.input_ns = api.nvim_create_namespace("avante_input")
M.hint_ns = api.nvim_create_namespace("avante_hint")

local function has_set_colors(hl_group)
  local hl = api.nvim_get_hl(0, { name = hl_group })
  return next(hl) ~= nil
end

M.setup = function()
  local normal = api.nvim_get_hl(0, { name = "Normal" })
  local normal_float = api.nvim_get_hl(0, { name = "NormalFloat" })

  if Config.behaviour.auto_set_highlight_group then
    vim
      .iter(Highlights)
      :filter(function(k, _)
        -- return all uppercase key with underscore or fully uppercase key
        return k:match("^%u+_") or k:match("^%u+$")
      end)
      :each(function(_, hl)
        if not has_set_colors(hl.name) then
          api.nvim_set_hl(0, hl.name, { fg = hl.fg or nil, bg = hl.bg or nil })
        end
      end)

    M.conflict_highlights()
  end

  api.nvim_set_hl(M.hint_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })
  api.nvim_set_hl(M.input_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })
  api.nvim_set_hl(M.input_ns, "FloatBorder", { fg = normal.fg, bg = normal.bg })
end

---@param opts? AvanteConflictHighlights
M.conflict_highlights = function(opts)
  opts = opts or Config.diff.highlights

  local get_default_colors = function(key, hl)
    --- We will first check for user custom highlight. Then fallback to default name highlight.
    local cl
    cl = api.nvim_get_hl(0, { name = opts[key:lower()] })
    if cl ~= nil then
      return cl.bg or hl.bg
    end
    cl = api.nvim_get_hl(0, { name = hl.name })
    return cl.bg or hl.bg
  end

  local get_shade = function(hl)
    local color = get_default_colors(hl.link, Highlights.conflict[hl.link])
    return H.shade_color(color, hl.shade)
  end

  vim.iter(Highlights.conflict):each(function(key, hl)
    if not has_set_colors(hl.name) then
      if hl.link ~= nil then
        api.nvim_set_hl(0, hl.name, { bg = get_shade(hl), default = true })
      else
        api.nvim_set_hl(0, hl.name, { bg = get_default_colors(key, hl), default = true, bold = true })
      end
    end
  end)
end

setmetatable(M, {
  __index = function(t, k)
    if Highlights[k] ~= nil then
      return Highlights[k].name
    elseif Highlights.conflict[k] ~= nil then
      return Highlights.conflict[k].name
    end
    return t[k]
  end,
})

--- Returns a table containing the RGB values encoded inside 24 least
--- significant bits of the number @rgb_24bit
---
---@param rgb_24bit number 24-bit RGB value
---@return {r: integer, g: integer, b: integer} with keys 'r', 'g', 'b' in [0,255]
H.decode_24bit_rgb = function(rgb_24bit)
  vim.validate({ rgb_24bit = { rgb_24bit, "n", true } })
  local r = band(rshift(rgb_24bit, 16), 255)
  local g = band(rshift(rgb_24bit, 8), 255)
  local b = band(rgb_24bit, 255)
  return { r = r, g = g, b = b }
end

---@param attr integer
---@param percent integer
H.alter = function(attr, percent)
  return math.floor(attr * (100 + percent) / 100)
end

---@source https://stackoverflow.com/q/5560248
---@see https://stackoverflow.com/a/37797380
---Darken a specified hex color
---@param color number
---@param percent number
---@return string
H.shade_color = function(color, percent)
  local rgb = H.decode_24bit_rgb(color)
  if not rgb.r or not rgb.g or not rgb.b then
    return "NONE"
  end
  local r, g, b = H.alter(rgb.r, percent), H.alter(rgb.g, percent), H.alter(rgb.b, percent)
  r, g, b = math.min(r, 255), math.min(g, 255), math.min(b, 255)
  return string.format("#%02x%02x%02x", r, g, b)
end

return M
