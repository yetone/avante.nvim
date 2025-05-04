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
  CONFIRM_TITLE = { name = "AvanteConfirmTitle", fg = "#1e222a", bg = "#e06c75" },
  BUTTON_DEFAULT = { name = "AvanteButtonDefault", fg = "#1e222a", bg = "#ABB2BF" },
  BUTTON_DEFAULT_HOVER = { name = "AvanteButtonDefaultHover", fg = "#1e222a", bg = "#a9cf8a" },
  BUTTON_PRIMARY = { name = "AvanteButtonPrimary", fg = "#1e222a", bg = "#ABB2BF" },
  BUTTON_PRIMARY_HOVER = { name = "AvanteButtonPrimaryHover", fg = "#1e222a", bg = "#56b6c2" },
  BUTTON_DANGER = { name = "AvanteButtonDanger", fg = "#1e222a", bg = "#ABB2BF" },
  BUTTON_DANGER_HOVER = { name = "AvanteButtonDangerHover", fg = "#1e222a", bg = "#e06c75" },
  AVANTE_PROMPT_INPUT = { name = "AvantePromptInput" },
  AVANTE_PROMPT_INPUT_BORDER = { name = "AvantePromptInputBorder", link = "NormalFloat" },
  AVANTE_SIDEBAR_WIN_SEPARATOR = {
    name = "AvanteSidebarWinSeparator",
    fg_link_bg = "NormalFloat",
    bg_link = "NormalFloat",
  },
  AVANTE_SIDEBAR_WIN_HORIZONTAL_SEPARATOR = {
    name = "AvanteSidebarWinHorizontalSeparator",
    fg_link = "WinSeparator",
    bg_link = "NormalFloat",
  },
  AVANTE_SIDEBAR_NORMAL = { name = "AvanteSidebarNormal", link = "NormalFloat" },
  AVANTE_COMMENT_FG = { name = "AvanteCommentFg", fg_link = "Comment" },
  AVANTE_REVERSED_NORMAL = { name = "AvanteReversedNormal", fg_link_bg = "Normal", bg_link_fg = "Normal" },
  AVANTE_STATE_SPINNER_GENERATING = { name = "AvanteStateSpinnerGenerating", fg = "#1e222a", bg = "#ab9df2" },
  AVANTE_STATE_SPINNER_TOOL_CALLING = { name = "AvanteStateSpinnerToolCalling", fg = "#1e222a", bg = "#56b6c2" },
  AVANTE_STATE_SPINNER_FAILED = { name = "AvanteStateSpinnerFailed", fg = "#1e222a", bg = "#e06c75" },
  AVANTE_STATE_SPINNER_SUCCEEDED = { name = "AvanteStateSpinnerSucceeded", fg = "#1e222a", bg = "#98c379" },
  AVANTE_STATE_SPINNER_SEARCHING = { name = "AvanteStateSpinnerSearching", fg = "#1e222a", bg = "#c678dd" },
  AVANTE_STATE_SPINNER_THINKING = { name = "AvanteStateSpinnerThinking", fg = "#1e222a", bg = "#c678dd" },
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

local function has_set_colors(hl_group) return next(Utils.get_hl(hl_group)) ~= nil end

local first_setup = true
local already_set_highlights = {}

function M.setup()
  if Config.behaviour.auto_set_highlight_group then
    vim
      .iter(Highlights)
      :filter(function(k, _)
        -- return all uppercase key with underscore or fully uppercase key
        return k:match("^%u+_") or k:match("^%u+$")
      end)
      :each(function(_, hl)
        if first_setup and has_set_colors(hl.name) then already_set_highlights[hl.name] = true end
        if not already_set_highlights[hl.name] then
          local bg = hl.bg
          local fg = hl.fg
          if hl.bg_link ~= nil then bg = Utils.get_hl(hl.bg_link).bg end
          if hl.fg_link ~= nil then fg = Utils.get_hl(hl.fg_link).fg end
          if hl.bg_link_fg ~= nil then bg = Utils.get_hl(hl.bg_link_fg).fg end
          if hl.fg_link_bg ~= nil then fg = Utils.get_hl(hl.fg_link_bg).bg end
          api.nvim_set_hl(
            0,
            hl.name,
            { fg = fg or nil, bg = bg or nil, link = hl.link or nil, strikethrough = hl.strikethrough }
          )
        end
      end)
  end

  if first_setup then
    vim.iter(Highlights.conflict):each(function(_, hl)
      if hl.name and has_set_colors(hl.name) then already_set_highlights[hl.name] = true end
    end)
  end
  first_setup = false

  M.setup_conflict_highlights()
end

function M.setup_conflict_highlights()
  local custom_hls = Config.highlights.diff

  ---@return number | nil
  local function get_bg(hl_name) return Utils.get_hl(hl_name).bg end

  local function get_bold(hl_name) return Utils.get_hl(hl_name).bold end

  vim.iter(Highlights.conflict):each(function(key, hl)
    --- set none shade linked highlights first
    if hl.shade_link ~= nil and hl.shade ~= nil then return end

    if already_set_highlights[hl.name] then return end

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

    if already_set_highlights[hl.name] then return end

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
  vim.validate({ rgb_24bit = { rgb_24bit, "number", true } })
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
