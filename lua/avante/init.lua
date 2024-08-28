local api = vim.api

local Utils = require("avante.utils")
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
    local sidebar, _ = M._get()
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
  vim.keymap.set({ "n", "v" }, Config.mappings.ask, M.toggle, { noremap = true, desc = "avante: Ask" })
  vim.keymap.set("v", Config.mappings.edit, M.edit, { noremap = true, desc = "avante: Edit" })
  vim.keymap.set("n", Config.mappings.refresh, M.refresh, { noremap = true, desc = "avante: Refresh" })

  Utils.toggle_map("n", Config.mappings.toggle.debug, {
    name = "debug",
    get = function()
      return Config.debug
    end,
    set = function(state)
      Config.override({ debug = state })
    end,
  })
  Utils.toggle_map("n", Config.mappings.toggle.hint, {
    name = "hint",
    get = function()
      return Config.hints.enabled
    end,
    set = function(state)
      Config.override({ hints = { enabled = state } })
    end,
  })
end

H.signs = function()
  vim.fn.sign_define("AvanteInputPromptSign", { text = Config.windows.input.prefix })
end

H.augroup = api.nvim_create_augroup("avante_autocmds", { clear = true })

H.autocmds = function()
  api.nvim_create_autocmd("TabEnter", {
    group = H.augroup,
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

  api.nvim_create_autocmd("VimResized", {
    group = H.augroup,
    callback = function()
      local sidebar, _ = M._get()
      if not sidebar then
        return
      end
      if not sidebar:is_open() then
        return
      end
      sidebar:resize()
    end,
  })

  api.nvim_create_autocmd("TabClosed", {
    group = H.augroup,
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

  api.nvim_create_autocmd("ColorSchemePre", {
    group = H.augroup,
    callback = function()
      require("avante.highlights").setup()
    end,
  })

  -- automatically setup Avante filetype to markdown
  vim.treesitter.language.register("markdown", "Avante")
end

---@param current boolean? false to disable setting current, otherwise use this to track across tabs.
---@return avante.Sidebar, avante.Selection
function M._get(current)
  local tab = api.nvim_get_current_tabpage()
  local sidebar = M.sidebars[tab]
  local selection = M.selections[tab]
  if current ~= false then
    M.current.sidebar = sidebar
    M.current.selection = selection
  end
  return sidebar, selection
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
  local sidebar, _ = M._get()
  if not sidebar then
    M._init(api.nvim_get_current_tabpage())
    M.current.sidebar:open()
    return true
  end

  return sidebar:toggle()
end

M.edit = function()
  local _, selection = M._get()
  if not selection then
    return
  end
  selection:create_editing_input()
end

M.refresh = function()
  local sidebar, _ = M._get()
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

  ---PERF: we can still allow running require("avante").setup() multiple times to override config if users wish to
  ---but most of the other functionality will only be called once from lazy.nvim
  Config.setup(opts)

  if M.did_setup then
    return
  end

  require("avante.history").setup()
  require("avante.highlights").setup()
  require("avante.diff").setup()
  require("avante.providers").setup()
  require("avante.clipboard").setup()

  -- setup helpers
  H.autocmds()
  H.commands()
  H.keymaps()
  H.signs()

  M.did_setup = true
end

return M
