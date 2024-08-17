local api = vim.api

local Tiktoken = require("avante.tiktoken")
local Sidebar = require("avante.sidebar")
local Config = require("avante.config")
local Diff = require("avante.diff")
local Selection = require("avante.selection")

---@class Avante
local M = {
  ---@type avante.Sidebar[] we use this to track chat command across tabs
  sidebars = {},
  ---@type avante.Sidebar
  current = nil,
  selection = nil,
  _once = false,
}

local H = {}

H.commands = function()
  local cmd = function(n, c, o)
    o = vim.tbl_extend("force", { nargs = 0 }, o or {})
    api.nvim_create_user_command("Avante" .. n, c, o)
  end

  cmd("Ask", function()
    M.toggle()
  end, { desc = "avante: ask AI for code suggestions" })
  cmd("Close", function()
    local sidebar = M._get()
    if not sidebar then
      return
    end
    sidebar:close()
  end, { desc = "avante: close chat window" })
  cmd("Refresh", function()
    M.refresh()
  end, { desc = "avante: refresh windows" })
end

H.keymaps = function()
  vim.keymap.set({ "n", "v" }, Config.mappings.ask, M.toggle, { noremap = true })
  vim.keymap.set("n", Config.mappings.refresh, M.refresh, { noremap = true })
end

H.autocmds = function()
  local ok, LazyConfig = pcall(require, "lazy.core.config")

  if ok then
    local name = "avante.nvim"
    local load_path = function()
      require("tiktoken_lib").load()
      Tiktoken.setup("gpt-4o")
    end

    if LazyConfig.plugins[name] and LazyConfig.plugins[name]._.loaded then
      vim.schedule(load_path)
    else
      api.nvim_create_autocmd("User", {
        pattern = "LazyLoad",
        callback = function(event)
          if event.data == name then
            load_path()
            return true
          end
        end,
      })
    end

    api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = load_path,
    })
  end

  api.nvim_create_autocmd("TabClosed", {
    pattern = "*",
    callback = function(ev)
      local tab = tonumber(ev.file)
      local s = M.sidebars[tab]
      if s then
        s:destroy()
      end
      if tab ~= nil then
        M.sidebars[tab] = nil
      end
    end,
  })

  -- automatically setup Avante filetype to markdown
  vim.treesitter.language.register("markdown", "Avante")
end

---@param current boolean? false to disable setting current, otherwise use this to track across tabs.
---@return avante.Sidebar
function M._get(current)
  local tab = api.nvim_get_current_tabpage()
  local sidebar = M.sidebars[tab]
  if current ~= false then
    M.current = sidebar
  end
  return sidebar
end

M.open = function()
  local tab = api.nvim_get_current_tabpage()
  local sidebar = M.sidebars[tab]

  if not sidebar then
    sidebar = Sidebar:new(tab)
    M.sidebars[tab] = sidebar
  end

  M.current = sidebar

  return sidebar:open()
end

M.toggle = function()
  local sidebar = M._get()
  if not sidebar then
    M.open()
    return true
  end

  return sidebar:toggle()
end

M.refresh = function()
  local sidebar = M._get()
  if not sidebar then
    return
  end
  local curbuf = vim.api.nvim_get_current_buf()

  local focused = sidebar.view.buf == curbuf or sidebar.bufnr.result == curbuf or sidebar.bufnr.input == curbuf
  if focused or not sidebar.view:is_open() then
    return
  end

  local ft = vim.api.nvim_get_option_value("filetype", { buf = curbuf })
  local listed = vim.api.nvim_get_option_value("buflisted", { buf = curbuf })

  if ft == "Avante" or not listed then
    return
  end

  local curwin = vim.api.nvim_get_current_win()

  sidebar.code.win = curwin
  sidebar.code.buf = curbuf
  sidebar:render()
end

---@param opts? avante.Config
function M.setup(opts)
  ---PERF: we can still allow running require("avante").setup() multiple times to override config if users wish to
  ---but most of the other functionality will only be called once from lazy.nvim
  Config.setup(opts)

  if M._once then
    return
  end
  Diff.setup({
    debug = false, -- log output to console
    default_mappings = Config.mappings.diff, -- disable buffer local mapping created by this plugin
    default_commands = true, -- disable commands created by this plugin
    disable_diagnostics = true, -- This will disable the diagnostics in a buffer whilst it is conflicted
    list_opener = "copen",
    highlights = Config.highlights.diff,
  })

  local selection = Selection:new()
  selection:setup()
  M.selection = selection

  -- setup helpers
  H.autocmds()
  H.commands()
  H.keymaps()

  M._once = true
end

return M
