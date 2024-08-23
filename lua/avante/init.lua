local api = vim.api

local Sidebar = require("avante.sidebar")
local Selection = require("avante.selection")
local Config = require("avante.config")

---@class Avante
local M = {
  ---@type avante.Sidebar[] we use this to track chat command across tabs
  sidebars = {},
  ---@type avante.Selection[]
  selections = {},
  ---@type {sidebar?: avante.Sidebar, selection?: avante.Selection}
  current = { sidebar = nil, selection = nil },
}

M.did_setup = false

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
      require("avante.tiktoken").setup("gpt-4o")
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

  api.nvim_create_autocmd("TabEnter", {
    pattern = "*",
    once = true,
    callback = function(ev)
      local tab = tonumber(ev.file)
      M._init(tab or api.nvim_get_current_tabpage())
      if Config.hints.enabled and not M.current.selection.did_setup then
        M.current.selection:setup_autocmds()
      end
    end,
  })

  api.nvim_create_autocmd("TabClosed", {
    pattern = "*",
    callback = function(ev)
      local tab = tonumber(ev.file)
      local s = M.sidebars[tab]
      local sl = M.selections[tab]
      if s then
        s:reset()
      end
      if sl then
        sl:delete_autocmds()
      end
      if tab ~= nil then
        M.sidebars[tab] = nil
      end
    end,
  })

  vim.schedule(function()
    M._init(api.nvim_get_current_tabpage())
    if Config.hints.enabled then
      M.current.selection:setup_autocmds()
    end
  end)

  -- automatically setup Avante filetype to markdown
  vim.treesitter.language.register("markdown", "Avante")
end

---@param current boolean? false to disable setting current, otherwise use this to track across tabs.
---@return avante.Sidebar
function M._get(current)
  local tab = api.nvim_get_current_tabpage()
  local sidebar = M.sidebars[tab]
  local selection = M.selections[tab]
  if current ~= false then
    M.current.sidebar = sidebar
    M.current.selection = selection
  end
  return sidebar
end

---@param id integer
function M._init(id)
  local sidebar = M.sidebars[id]
  local selection = M.selections[id]

  if not sidebar then
    sidebar = Sidebar:new(id)
    M.sidebars[id] = sidebar
  end
  if not selection then
    selection = Selection:new(id)
    M.selections[id] = selection
  end
  M.current = { sidebar = sidebar, selection = selection }
  return M
end

M.toggle = function()
  local sidebar = M._get()
  if not sidebar then
    M._init(api.nvim_get_current_tabpage())
    M.current.sidebar:open()
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

  local focused = sidebar.result.bufnr == curbuf or sidebar.input.bufnr == curbuf
  if focused or not sidebar:is_open() then
    return
  end

  local ft = vim.api.nvim_get_option_value("filetype", { buf = curbuf })
  local listed = vim.api.nvim_get_option_value("buflisted", { buf = curbuf })

  if ft == "Avante" or not listed then
    return
  end

  local curwin = vim.api.nvim_get_current_win()

  sidebar:close()
  sidebar.code.winid = curwin
  sidebar.code.bufnr = curbuf
  sidebar:render()
end

---@param opts? avante.Config
function M.setup(opts)
  if vim.fn.has("nvim-0.10") == 0 then
    vim.api.nvim_echo({
      { "Avante requires at least nvim-0.10", "ErrorMsg" },
      { "Please upgrade your neovim version", "WarningMsg" },
      { "Press any key to exit", "ErrorMsg" },
    }, true, {})
    vim.fn.getchar()
    vim.cmd([[quit]])
  end

  -- use a global statusline
  vim.opt.laststatus = 3

  ---PERF: we can still allow running require("avante").setup() multiple times to override config if users wish to
  ---but most of the other functionality will only be called once from lazy.nvim
  Config.setup(opts)

  if M.did_setup then
    return
  end

  require("avante.highlights").setup()
  require("avante.diff").setup()
  require("avante.providers").setup()

  -- setup helpers
  H.autocmds()
  H.commands()
  H.keymaps()

  M.did_setup = true
end

return M
