local tiktoken = require("avante.tiktoken")
local Sidebar = require("avante.sidebar")
local config = require("avante.config")
local diff = require("avante.diff")

local api = vim.api

local M = {
  ---@type avante.Sidebar[]
  sidebars = {},
  ---@type avante.Sidebar
  current = nil,
}

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

---Run a sidebar method by getting the sidebar of current tabpage, with args
---noop if sidebar is nil
---@param method "open"|"close"|"toggle"|"focus"
---@param args table? arguments to parse
---@return any return_of_method
function M._call(method, args)
  local sidebar = M._get()
  if not sidebar then
    return
  end

  args = args or {}
  return sidebar[method](sidebar, unpack(args))
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

M.close = function()
  return M._call("close")
end

M.focus = function()
  return M._call("focus")
end

M.toggle = function()
  local sidebar = M._get()
  if not sidebar then
    M.open()
    return true
  end

  return sidebar:toggle()
end

function M.setup(opts)
  local ok, LazyConfig = pcall(require, "lazy.core.config")

  local load_path = function()
    require("tiktoken_lib").load()

    tiktoken.setup("gpt-4o")
  end

  if ok then
    local name = "avante.nvim"
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

  config.update(opts)

  diff.setup({
    debug = false, -- log output to console
    default_mappings = config.get().mappings.diff, -- disable buffer local mapping created by this plugin
    default_commands = true, -- disable commands created by this plugin
    disable_diagnostics = true, -- This will disable the diagnostics in a buffer whilst it is conflicted
    list_opener = "copen",
    highlights = config.get().highlights.diff,
  })

  api.nvim_create_user_command("AvanteAsk", function()
    M.toggle()
  end, { nargs = 0 })
  api.nvim_set_keymap("n", config.get().mappings.show_sidebar, "<cmd>AvanteAsk<CR>", { noremap = true, silent = true })

  api.nvim_create_autocmd("FileType", {
    group = api.nvim_create_augroup("Avante", { clear = true }),
    pattern = "Avante",
    callback = function(event)
      api.nvim_buf_set_keymap(event.buf, "n", "q", '<cmd>:lua require("avante").close()<cr>', { silent = true })
    end,
  })

  vim.treesitter.language.register("markdown", "Avante")
end

return M
