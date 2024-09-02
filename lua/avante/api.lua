local Config = require("avante.config")
local Utils = require("avante.utils")

---@class avante.ApiToggle
---@operator call(): boolean
---@field debug ToggleBind.wrap
---@field hint ToggleBind.wrap
---
---@class avante.Api
---@field ask fun(question:string?): boolean
---@field edit fun(question:string?): nil
---@field refresh fun(): nil
---@field build fun(): boolean
---@field switch_provider fun(target: string): nil
---@field toggle avante.ApiToggle

local M = {}

---@param target Provider
M.switch_provider = function(target)
  require("avante.providers").refresh(target)
end

---@param question? string
M.ask = function(question)
  if not require("avante").toggle() then
    return false
  end
  if question == nil or question == "" then
    return true
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "AvanteInputSubmitted", data = { request = question } })
  return true
end

---@param question? string
M.edit = function(question)
  local _, selection = require("avante").get()
  if not selection then
    return
  end
  selection:create_editing_input()
  if question ~= nil or question ~= "" then
    vim.api.nvim_exec_autocmds("User", { pattern = "AvanteEditSubmitted", data = { request = question } })
  end
end

M.refresh = function()
  local sidebar, _ = require("avante").get()
  if not sidebar then
    return
  end
  if not sidebar:is_open() then
    return
  end
  local curbuf = vim.api.nvim_get_current_buf()

  local focused = sidebar.result.bufnr == curbuf or sidebar.input.bufnr == curbuf
  if focused or not sidebar:is_open() then
    return
  end
  local listed = vim.api.nvim_get_option_value("buflisted", { buf = curbuf })

  if Utils.is_sidebar_buffer(curbuf) or not listed then
    return
  end

  local curwin = vim.api.nvim_get_current_win()

  sidebar:close()
  sidebar.code.winid = curwin
  sidebar.code.bufnr = curbuf
  sidebar:render()
end

return setmetatable(M, {
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
