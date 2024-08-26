local api = vim.api

local Config = require("avante.config")

local H = {
  TITLE = { name = "AvanteTitle", fg = "#1e222a", bg = "#98c379" },
  REVERSED_TITLE = { name = "AvanteReversedTitle", fg = "#98c379" },
  SUBTITLE = { name = "AvanteSubtitle", fg = "#1e222a", bg = "#56b6c2" },
  REVERSED_SUBTITLE = { name = "AvanteReversedSubtitle", fg = "#56b6c2" },
  THIRD_TITLE = { name = "AvanteThirdTitle", fg = "#ABB2BF", bg = "#353B45" },
  REVERSED_THIRD_TITLE = { name = "AvanteReversedThirdTitle", fg = "#353B45" },
}

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
    vim.iter(H):each(function(_, hl)
      if not has_set_colors(hl.name) then
        api.nvim_set_hl(0, hl.name, { fg = hl.fg, bg = hl.bg or nil })
      end
    end)
  end

  api.nvim_set_hl(M.hint_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })

  api.nvim_set_hl(M.input_ns, "NormalFloat", { fg = normal_float.fg, bg = normal_float.bg })
  api.nvim_set_hl(M.input_ns, "FloatBorder", { fg = normal.fg, bg = normal.bg })
end

setmetatable(M, {
  __index = function(t, k)
    if H[k] ~= nil then
      return H[k].name
    end
    return t[k]
  end,
})

return M
