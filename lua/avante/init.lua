local api = vim.api

local Utils = require("avante.utils")
local Sidebar = require("avante.sidebar")
local Selection = require("avante.selection")
local Suggestion = require("avante.suggestion")
local Config = require("avante.config")
local Diff = require("avante.diff")

---@class Avante
local M = {
  ---@type avante.Sidebar[] we use this to track chat command across tabs
  sidebars = {},
  ---@type avante.Selection[]
  selections = {},
  ---@type avante.Suggestion[]
  suggestions = {},
  ---@type {sidebar?: avante.Sidebar, selection?: avante.Selection, suggestion?: avante.Suggestion}
  current = { sidebar = nil, selection = nil, suggestion = nil },
}

M.did_setup = false

local H = {}

H.commands = function()
  ---@param n string
  ---@param c vim.api.keyset.user_command.callback
  ---@param o vim.api.keyset.user_command.opts
  local cmd = function(n, c, o)
    o = vim.tbl_extend("force", { nargs = 0 }, o or {})
    api.nvim_create_user_command("Avante" .. n, c, o)
  end

  cmd(
    "Ask",
    function(opts) require("avante.api").ask(vim.trim(opts.args)) end,
    { desc = "avante: ask AI for code suggestions", nargs = "*" }
  )
  cmd("Toggle", function() M.toggle() end, { desc = "avante: toggle AI panel" })
  cmd(
    "Edit",
    function(opts) require("avante.api").edit(vim.trim(opts.args)) end,
    { desc = "avante: edit selected block", nargs = "*" }
  )
  cmd("Refresh", function() require("avante.api").refresh() end, { desc = "avante: refresh windows" })
  cmd("Build", function(opts)
    local args = {}
    for _, arg in ipairs(opts.fargs) do
      local key, value = arg:match("(%w+)=(%w+)")
      if key and value then args[key] = value == "true" end
    end
    if args.source == nil then args.source = true end

    require("avante.api").build(args)
  end, {
    desc = "avante: build dependencies",
    nargs = "*",
    complete = function(_, _, _) return { "source=true", "source=false" } end,
  })
  cmd("SwitchProvider", function(opts) require("avante.api").switch_provider(vim.trim(opts.args or "")) end, {
    nargs = 1,
    desc = "avante: switch provider",
    complete = function(_, line, _)
      local prefix = line:match("AvanteSwitchProvider%s*(.*)$") or ""
      ---@param key string
      return vim.tbl_filter(function(key) return key:find(prefix, 1, true) == 1 end, Config.providers)
    end,
  })
end

H.keymaps = function()
  vim.keymap.set({ "n", "v" }, "<Plug>(AvanteAsk)", function() require("avante.api").ask() end, { noremap = true })
  vim.keymap.set("v", "<Plug>(AvanteEdit)", function() require("avante.api").edit() end, { noremap = true })
  vim.keymap.set("n", "<Plug>(AvanteRefresh)", function() require("avante.api").refresh() end, { noremap = true })
  vim.keymap.set("n", "<Plug>(AvanteToggle)", function() M.toggle() end, { noremap = true })
  vim.keymap.set("n", "<Plug>(AvanteToggleDebug)", function() M.toggle.debug() end)
  vim.keymap.set("n", "<Plug>(AvanteToggleHint)", function() M.toggle.hint() end)

  vim.keymap.set({ "n", "v" }, "<Plug>(AvanteConflictOurs)", function() Diff.choose("ours") end)
  vim.keymap.set({ "n", "v" }, "<Plug>(AvanteConflictBoth)", function() Diff.choose("both") end)
  vim.keymap.set({ "n", "v" }, "<Plug>(AvanteConflictTheirs)", function() Diff.choose("theirs") end)
  vim.keymap.set({ "n", "v" }, "<Plug>(AvanteConflictAllTheirs)", function() Diff.choose("all_theirs") end)
  vim.keymap.set({ "n", "v" }, "<Plug>(AvanteConflictCursor)", function() Diff.choose("cursor") end)
  vim.keymap.set("n", "<Plug>(AvanteConflictNextConflict)", function() Diff.find_next("ours") end)
  vim.keymap.set("n", "<Plug>(AvanteConflictPrevConflict)", function() Diff.find_prev("ours") end)

  if Config.behaviour.auto_set_keymaps then
    Utils.safe_keymap_set(
      { "n", "v" },
      Config.mappings.ask,
      function() require("avante.api").ask() end,
      { desc = "avante: ask" }
    )
    Utils.safe_keymap_set(
      "v",
      Config.mappings.edit,
      function() require("avante.api").edit() end,
      { desc = "avante: edit" }
    )
    Utils.safe_keymap_set(
      "n",
      Config.mappings.refresh,
      function() require("avante.api").refresh() end,
      { desc = "avante: refresh" }
    )
    Utils.safe_keymap_set("n", Config.mappings.toggle.default, function() M.toggle() end, { desc = "avante: toggle" })
    Utils.safe_keymap_set(
      "n",
      Config.mappings.toggle.debug,
      function() M.toggle.debug() end,
      { desc = "avante: toggle debug" }
    )
    Utils.safe_keymap_set(
      "n",
      Config.mappings.toggle.hint,
      function() M.toggle.hint() end,
      { desc = "avante: toggle hint" }
    )
  end
end

---@class ApiCaller
---@operator call(...): any

H.api = function(fun)
  return setmetatable({ api = true }, {
    __call = function(...) return fun(...) end,
  }) --[[@as ApiCaller]]
end

H.signs = function() vim.fn.sign_define("AvanteInputPromptSign", { text = Config.windows.input.prefix }) end

H.augroup = api.nvim_create_augroup("avante_autocmds", { clear = true })

H.autocmds = function()
  local ok, LazyConfig = pcall(require, "lazy.core.config")

  if ok then
    local name = "avante.nvim"
    local load_path = function() require("avante_lib").load() end

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
    group = H.augroup,
    pattern = "*",
    once = true,
    callback = function(ev)
      local tab = tonumber(ev.file)
      M._init(tab or api.nvim_get_current_tabpage())
      if Config.hints.enabled and not M.current.selection.did_setup then M.current.selection:setup_autocmds() end
    end,
  })

  api.nvim_create_autocmd("VimResized", {
    group = H.augroup,
    callback = function()
      local sidebar = M.get()
      if not sidebar then return end
      if not sidebar:is_open() then return end
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
      if s then s:reset() end
      if sl then sl:delete_autocmds() end
      if tab ~= nil then M.sidebars[tab] = nil end
    end,
  })

  vim.schedule(function()
    M._init(api.nvim_get_current_tabpage())
    if Config.hints.enabled then M.current.selection:setup_autocmds() end
  end)

  api.nvim_create_autocmd("ColorSchemePre", {
    group = H.augroup,
    callback = function() require("avante.highlights").setup() end,
  })

  -- automatically setup Avante filetype to markdown
  vim.treesitter.language.register("markdown", "Avante")

  vim.filetype.add({
    extension = {
      ["avanterules"] = "jinja",
    },
    pattern = {
      ["%.avanterules%.[%w_.-]+"] = "jinja",
    },
  })
end

---@param current boolean? false to disable setting current, otherwise use this to track across tabs.
---@return avante.Sidebar, avante.Selection, avante.Suggestion
function M.get(current)
  local tab = api.nvim_get_current_tabpage()
  local sidebar = M.sidebars[tab]
  local selection = M.selections[tab]
  local suggestion = M.suggestions[tab]
  if current ~= false then
    M.current.sidebar = sidebar
    M.current.selection = selection
    M.current.suggestion = suggestion
  end
  return sidebar, selection, suggestion
end

---@param id integer
function M._init(id)
  local sidebar = M.sidebars[id]
  local selection = M.selections[id]
  local suggestion = M.suggestions[id]

  if not sidebar then
    sidebar = Sidebar:new(id)
    M.sidebars[id] = sidebar
  end
  if not selection then
    selection = Selection:new(id)
    M.selections[id] = selection
  end
  if not suggestion then
    suggestion = Suggestion:new(id)
    M.suggestions[id] = suggestion
  end
  M.current = { sidebar = sidebar, selection = selection, suggestion = suggestion }
  return M
end

M.toggle = { api = true }

M.toggle.debug = H.api(Utils.toggle_wrap({
  name = "debug",
  get = function() return Config.debug end,
  set = function(state) Config.override({ debug = state }) end,
}))

M.toggle.hint = H.api(Utils.toggle_wrap({
  name = "hint",
  get = function() return Config.hints.enabled end,
  set = function(state) Config.override({ hints = { enabled = state } }) end,
}))

setmetatable(M.toggle, {
  __index = M.toggle,
  __call = function()
    local sidebar = M.get()
    if not sidebar then
      M._init(api.nvim_get_current_tabpage())
      M.current.sidebar:open()
      return true
    end

    return sidebar:toggle()
  end,
})

---@param opts? avante.Config
function M.setup(opts)
  ---PERF: we can still allow running require("avante").setup() multiple times to override config if users wish to
  ---but most of the other functionality will only be called once from lazy.nvim
  Config.setup(opts)

  if M.did_setup then return end

  require("avante.path").setup()
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
