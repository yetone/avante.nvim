local api = vim.api

local Config = require("avante.config")

local M = {
  TITLE = "AvanteTitle",
  REVERSED_TITLE = "AvanteReversedTitle",
  SUBTITLE = "AvanteSubtitle",
  REVERSED_SUBTITLE = "AvanteReversedSubtitle",
  THIRD_TITLE = "AvanteThirdTitle",
  REVERSED_THIRD_TITLE = "AvanteReversedThirdTitle",
}

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
    if not has_set_colors(M.TITLE) then
      api.nvim_set_hl(0, M.TITLE, { fg = "#1e222a", bg = "#98c379" })
    end
    if not has_set_colors(M.REVERSED_TITLE) then
      api.nvim_set_hl(0, M.REVERSED_TITLE, { fg = "#98c379" })
    end
    if not has_set_colors(M.SUBTITLE) then
      api.nvim_set_hl(0, M.SUBTITLE, { fg = "#1e222a", bg = "#56b6c2" })
    end
    if not has_set_colors(M.REVERSED_SUBTITLE) then
      api.nvim_set_hl(0, M.REVERSED_SUBTITLE, { fg = "#56b6c2" })
    end
    if not has_set_colors(M.THIRD_TITLE) then
      api.nvim_set_hl(0, M.THIRD_TITLE, { fg = "#ABB2BF", bg = "#353B45" })
    end
    if not has_set_colors(M.REVERSED_THIRD_TITLE) then
      api.nvim_set_hl(0, M.REVERSED_THIRD_TITLE, { fg = "#353B45" })
    end
  end

  api.nvim_set_hl(M.hint_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })

  api.nvim_set_hl(M.input_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })
  api.nvim_set_hl(M.input_ns, "FloatBorder", { fg = normal.fg, bg = normal.bg })
end

return M
