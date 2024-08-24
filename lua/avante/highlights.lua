local api = vim.api
local Config = require("avante.config")

local M = {
  TITLE = "AvanteTitle",
  REVERSED_TITLE = "AvanteReversedTitle",
  SUBTITLE = "AvanteSubtitle",
  REVERSED_SUBTITLE = "AvanteReversedSubtitle",
  THIRDTITLE = "AvanteThirdTitle",
  REVERSED_THIRDTITLE = "AvanteReversedThirdTitle",
  REVERSED_NORMAL = "AvanteReversedNormal",
}

M.input_ns = api.nvim_create_namespace("avante_input")
M.hint_ns = api.nvim_create_namespace("avante_hint")

M.setup = function()
  local normal = api.nvim_get_hl(0, { name = "Normal" })
  local normal_float = api.nvim_get_hl(0, { name = "NormalFloat" })

  api.nvim_set_hl(0, M.REVERSED_NORMAL, { fg = normal.bg })

  if Config.defaults.theme == "light" then
    api.nvim_set_hl(0, M.TITLE, { fg = "#1e222a", bg = "#98c379" })
    api.nvim_set_hl(0, M.REVERSED_TITLE, { fg = "#98c379" })
    api.nvim_set_hl(0, M.SUBTITLE, { fg = "#1e222a", bg = "#7998c3" })
    api.nvim_set_hl(0, M.REVERSED_SUBTITLE, { fg = "#7998c3" })
    api.nvim_set_hl(0, M.THIRDTITLE, { fg = "#1e222a", bg = "#a479c3" })
    api.nvim_set_hl(0, M.REVERSED_THIRDTITLE, { fg = "#a479c3" })
  else
    api.nvim_set_hl(0, M.TITLE, { fg = "#1e222a", bg = "#98c379" })
    api.nvim_set_hl(0, M.REVERSED_TITLE, { fg = "#98c379" })
    api.nvim_set_hl(0, M.SUBTITLE, { fg = "#1e222a", bg = "#56b6c2" })
    api.nvim_set_hl(0, M.REVERSED_SUBTITLE, { fg = "#56b6c2" })
    api.nvim_set_hl(0, M.THIRDTITLE, { fg = "#ABB2BF", bg = "#353B45" })
    api.nvim_set_hl(0, M.REVERSED_THIRDTITLE, { fg = "#353B45" })
  end

  api.nvim_set_hl(M.hint_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })

  api.nvim_set_hl(M.input_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })
  api.nvim_set_hl(M.input_ns, "FloatBorder", { fg = normal.fg, bg = normal.bg })
end

return M
