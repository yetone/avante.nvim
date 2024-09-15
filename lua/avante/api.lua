local Config = require("avante.config")
local Utils = require("avante.utils")

---@class avante.ApiToggle
---@operator call(): boolean
---@field debug ToggleBind.wrap
---@field hint ToggleBind.wrap

---@class avante.Api
---@field toggle avante.ApiToggle
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

---@param opts? {source: boolean}
M.build = function(opts)
  opts = opts or { source = true }
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
      "-BuildFromSource",
      string.format("%s", opts.source == true and "true" or "false"),
    }
  else
    error("Unsupported operating system: " .. os_name, 2)
  end

  ---@type integer
  local pid
  local exit_code = { 0 }

  local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(obj)
    local stderr = obj.stderr and vim.split(obj.stderr, "\n") or {}
    local stdout = obj.stdout and vim.split(obj.stdout, "\n") or {}
    if vim.tbl_contains(exit_code, obj.code) then
      local output = stdout
      if #output == 0 then
        table.insert(output, "")
        Utils.debug(output)
      else
        Utils.debug(stderr)
      end
    end
  end)
  if not ok then Utils.error("Failed to build the command: " .. cmd .. "\n" .. job_or_err, { once = true }) end
  pid = job_or_err.pid
  return pid
end

---@class AskOptions
---@field question? string optional questions
---@field win? table<string, any> windows options similar to |nvim_open_win()|
---@field ask? boolean

---@param opts? AskOptions
M.ask = function(opts)
  opts = opts or {}
  if type(opts) == "string" then
    Utils.warn("passing 'ask' as string is deprecated, do {question = '...'} instead", { once = true })
    opts = { question = opts }
  end

  if not require("avante").toggle_sidebar(opts) then return false end
  if opts.question == nil or opts.question == "" then return true end
  vim.api.nvim_exec_autocmds("User", { pattern = "AvanteInputSubmitted", data = { request = opts.question } })
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

---@param opts? AskOptions
M.refresh = function(opts)
  opts = opts or {}
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
  sidebar:render(opts)
end

return setmetatable(M, {
  __index = function(t, k)
    local module = require("avante")
    ---@class AvailableApi: ApiCaller
    ---@field api? boolean
    local has = module[k]
    if type(has) ~= "table" or not has.api then
      Utils.warn(k .. " is not a valid avante's API method", { once = true })
      return
    end
    t[k] = has
    return t[k]
  end,
}) --[[@as avante.Api]]
