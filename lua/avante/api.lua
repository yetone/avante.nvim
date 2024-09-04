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
---@field build fun(opts: {source: boolean}): boolean
---@field switch_provider fun(target: string): nil
---@field toggle avante.ApiToggle
---@field get_suggestion fun(): avante.Suggestion | nil

local M = {}

---@param target Provider
M.switch_provider = function(target) require("avante.providers").refresh(target) end

---@param path string
local function to_windows_path(path)
  local winpath = path:gsub("/", "\\")

  if winpath:match("^%a:") then winpath = winpath:sub(1, 2):upper() .. winpath:sub(3) end

  winpath = winpath:gsub("\\$", "")

  return winpath
end

---@param opts {source: boolean}
M.build = function(opts)
  local dirname = Utils.trim(string.sub(debug.getinfo(1).source, 2, #"/init.lua" * -1), { suffix = "/" })
  local git_root = vim.fs.find(".git", { path = dirname, upward = true })[1]
  local build_directory = git_root and vim.fn.fnamemodify(git_root, ":h") or (dirname .. "/../../")

  if opts.source and not vim.fn.executable("cargo") then
    error("Building avante.nvim requires cargo to be installed.", 2)
  end

  ---@type string[]
  local cmd
  local os_name = Utils.get_os_name()

  if vim.tbl_contains({ "linux", "darwin" }, os_name) then
    cmd = {
      "sh",
      "-c",
      string.format("make BUILD_FROM_SOURCE=%s -C %s", opts.source == true and "true" or "false", build_directory),
    }
  elseif os_name == "windows" then
    build_directory = to_windows_path(build_directory)
    cmd = {
      "powershell",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      string.format("%s\\Build.ps1", build_directory),
      "-WorkingDirectory",
      build_directory,
    }
  else
    error("Unsupported operating system: " .. os_name, 2)
  end

  ---@type integer
  local code
  vim.system(cmd, {
    text = true,
    stdout = function(_, data)
      if data then vim.schedule(function() vim.api.nvim_echo({ { data, "Normal" } }, false, {}) end) end
    end,
    stderr = function(err, _)
      if err then vim.schedule(function() vim.api.nvim_echo({ { err, "ErrorMsg" } }, false, {}) end) end
    end,
  }, function(obj)
    if vim.tbl_contains({ 0 }, obj.code) then
      code = obj.code
    else
      vim.api.nvim_echo({ { "Build failed with exit code: " .. obj.code, "ErrorMsg" } }, false, {})
    end
  end)
  return code
end

---@param question? string
M.ask = function(question)
  if not require("avante").toggle() then return false end
  if question == nil or question == "" then return true end
  vim.api.nvim_exec_autocmds("User", { pattern = "AvanteInputSubmitted", data = { request = question } })
  return true
end

---@param question? string
M.edit = function(question)
  local _, selection = require("avante").get()
  if not selection then return end
  selection:create_editing_input()
  if question ~= nil or question ~= "" then
    vim.api.nvim_exec_autocmds("User", { pattern = "AvanteEditSubmitted", data = { request = question } })
  end
end

---@return avante.Suggestion | nil
M.get_suggestion = function()
  local _, _, suggestion = require("avante").get()
  return suggestion
end

M.refresh = function()
  local sidebar = require("avante").get()
  if not sidebar then return end
  if not sidebar:is_open() then return end
  local curbuf = vim.api.nvim_get_current_buf()

  local focused = sidebar.result.bufnr == curbuf or sidebar.input.bufnr == curbuf
  if focused or not sidebar:is_open() then return end
  local listed = vim.api.nvim_get_option_value("buflisted", { buf = curbuf })

  if Utils.is_sidebar_buffer(curbuf) or not listed then return end

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
