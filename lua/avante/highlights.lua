local api = vim.api

local Config = require("avante.config")
local Utils = require("avante.utils")
local bit = require("bit")
local rshift, band = bit.rshift, bit.band

local Highlights = {
  TITLE = { name = "AvanteTitle", fg = "#1e222a", bg = "#98c379" },
  REVERSED_TITLE = { name = "AvanteReversedTitle", fg = "#98c379" },
  SUBTITLE = { name = "AvanteSubtitle", fg = "#1e222a", bg = "#56b6c2" },
  REVERSED_SUBTITLE = { name = "AvanteReversedSubtitle", fg = "#56b6c2" },
  THIRD_TITLE = { name = "AvanteThirdTitle", fg = "#ABB2BF", bg = "#353B45" },
  REVERSED_THIRD_TITLE = { name = "AvanteReversedThirdTitle", fg = "#353B45" },
  SUGGESTION = { name = "AvanteSuggestion", link = "Comment" },
  ANNOTATION = { name = "AvanteAnnotation", link = "Comment" },
  POPUP_HINT = { name = "AvantePopupHint", link = "NormalFloat" },
  INLINE_HINT = { name = "AvanteInlineHint", link = "Keyword" },
  TO_BE_DELETED = { name = "AvanteToBeDeleted", bg = "#ffcccc", strikethrough = true },
  TO_BE_DELETED_WITHOUT_STRIKETHROUGH = { name = "AvanteToBeDeletedWOStrikethrough", bg = "#562C30" },
}

Highlights.conflict = {
  CURRENT = { name = "AvanteConflictCurrent", bg = "#562C30", bold = true },
  CURRENT_LABEL = { name = "AvanteConflictCurrentLabel", shade_link = "AvanteConflictCurrent", shade = 30 },
  INCOMING = { name = "AvanteConflictIncoming", bg = 3229523, bold = true }, -- #314753
  INCOMING_LABEL = { name = "AvanteConflictIncomingLabel", shade_link = "AvanteConflictIncoming", shade = 30 },
}

--- helper
local H = {}

local M = {}

local function has_set_colors(hl_group)
  local hl = api.nvim_get_hl(0, { name = hl_group })
  return next(hl) ~= nil
end

function M.setup()
  if Config.behaviour.auto_set_highlight_group then
    vim
      .iter(Highlights)
      :filter(function(k, _)
        -- return all uppercase key with underscore or fully uppercase key
        return k:match("^%u+_") or k:match("^%u+$")
      end)
      :each(function(_, hl)
        if not has_set_colors(hl.name) then
          api.nvim_set_hl(
            0,
            hl.name,
            { fg = hl.fg or nil, bg = hl.bg or nil, link = hl.link or nil, strikethrough = hl.strikethrough }
          )
        end
      end)
  end

  M.setup_conflict_highlights()
end

function M.setup_conflict_highlights()
  local custom_hls = Config.highlights.diff

  ---@return number | nil
  local function get_bg(hl_name)
    local hl = api.nvim_get_hl(0, { name = hl_name })
    return hl.bg
  end

  local function get_bold(hl_name)
    local hl = api.nvim_get_hl(0, { name = hl_name })
    return hl.bold
  end

  vim.iter(Highlights.conflict):each(function(key, hl)
    --- set none shade linked highlights first
    if hl.shade_link ~= nil and hl.shade ~= nil then return end

    if has_set_colors(hl.name) then return end

    local bg = hl.bg
    local bold = hl.bold

    local custom_hl_name = custom_hls[key:lower()]
    if custom_hl_name ~= nil then
      bg = get_bg(custom_hl_name) or hl.bg
      bold = get_bold(custom_hl_name) or hl.bold
    end

    api.nvim_set_hl(0, hl.name, { bg = bg, default = true, bold = bold })
  end)

  vim.iter(Highlights.conflict):each(function(key, hl)
    --- only set shade linked highlights
    if hl.shade_link == nil or hl.shade == nil then return end

    if has_set_colors(hl.name) then return end

    local bg
    local bold = hl.bold

    local custom_hl_name = custom_hls[key:lower()]
    if custom_hl_name ~= nil then
      bg = get_bg(custom_hl_name)
      bold = get_bold(custom_hl_name) or hl.bold
    else
      local link_bg = get_bg(hl.shade_link)
      if link_bg == nil then
        Utils.warn(string.format("highlights %s don't have bg, use fallback", hl.shade_link))
        link_bg = 3229523
      end
      bg = H.shade_color(link_bg, hl.shade)
    end

    api.nvim_set_hl(0, hl.name, { bg = bg, default = true, bold = bold })
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
function H.decode_24bit_rgb(rgb_24bit)
  vim.validate({ rgb_24bit = { rgb_24bit, "n", true } })
  local r = band(rshift(rgb_24bit, 16), 255)
  local g = band(rshift(rgb_24bit, 8), 255)
  local b = band(rgb_24bit, 255)
  return { r = r, g = g, b = b }
end

---@param attr integer
---@param percent integer
function H.alter(attr, percent) return math.floor(attr * (100 + percent) / 100) end

---@source https://stackoverflow.com/q/5560248
---@see https://stackoverflow.com/a/37797380
---Lighten a specified hex color
---@param color number
---@param percent number
---@return string
function H.shade_color(color, percent)
  percent = vim.opt.background:get() == "light" and percent / 5 or percent
  local rgb = H.decode_24bit_rgb(color)
  if not rgb.r or not rgb.g or not rgb.b then return "NONE" end
  local r, g, b = H.alter(rgb.r, percent), H.alter(rgb.g, percent), H.alter(rgb.b, percent)
  r, g, b = math.min(r, 255), math.min(g, 255), math.min(b, 255)
  return string.format("#%02x%02x%02x", r, g, b)
end

return M
