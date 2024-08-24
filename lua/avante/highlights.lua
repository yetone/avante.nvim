local api = vim.api

local M = {
  TITLE = "AvanteTitle",
  REVERSED_TITLE = "AvanteReversedTitle",
  SUBTITLE = "AvanteSubtitle",
  REVERSED_SUBTITLE = "AvanteReversedSubtitle",
  THRIDTITLE = "AvanteThirdTitle",
  REVERSED_THRIDTITLE = "AvanteReversedThirdTitle",
  REVERSED_NORMAL = "AvanteReversedNormal",
}

M.input_ns = api.nvim_create_namespace("avante_input")
M.hint_ns = api.nvim_create_namespace("avante_hint")

M.setup = function()
  local normal = api.nvim_get_hl(0, { name = "Normal" })
  local normal_float = api.nvim_get_hl(0, { name = "NormalFloat" })

  api.nvim_set_hl(0, M.REVERSED_NORMAL, { fg = normal.bg })
  api.nvim_set_hl(0, M.TITLE, { fg = "#1e222a", bg = "#98c379" })
  api.nvim_set_hl(0, M.REVERSED_TITLE, { fg = "#98c379" })
  api.nvim_set_hl(0, M.SUBTITLE, { fg = "#1e222a", bg = "#56b6c2" })
  api.nvim_set_hl(0, M.REVERSED_SUBTITLE, { fg = "#56b6c2" })
  api.nvim_set_hl(0, M.THRIDTITLE, { fg = "#ABB2BF", bg = "#353B45" })
  api.nvim_set_hl(0, M.REVERSED_THRIDTITLE, { fg = "#353B45" })

  api.nvim_set_hl(M.hint_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })

  api.nvim_set_hl(M.input_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })
  api.nvim_set_hl(M.input_ns, "FloatBorder", { fg = normal.fg, bg = normal.bg })
end

return M
