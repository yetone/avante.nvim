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

  cmd("Ask", function(opts)
    ---@type AskOptions
    local args = { question = nil, win = {} }
    local q_parts = {}
    local q_ask = nil
    for _, arg in ipairs(opts.fargs) do
      local value = arg:match("position=(%w+)")
      local ask = arg:match("ask=(%w+)")
      if ask ~= nil then
        q_ask = ask == "true"
      elseif value then
        args.win.position = value
      else
        table.insert(q_parts, arg)
      end
    end
    require("avante.api").ask(
      vim.tbl_deep_extend(
        "force",
        args,
        { ask = q_ask, question = #q_parts > 0 and table.concat(q_parts, " ") or nil }
      )
    )
  end, {
    desc = "avante: ask AI for code suggestions",
    nargs = "*",
    complete = function(_, _, _)
      local candidates = {} ---@type string[]
      vim.list_extend(
        candidates,
        ---@param x string
        vim.tbl_map(function(x) return "position=" .. x end, { "left", "right", "top", "bottom" })
      )
      vim.list_extend(candidates, vim.tbl_map(function(x) return "ask=" .. x end, { "true", "false" }))
      return candidates
    end,
  })
  cmd("Chat", function() require("avante.api").ask({ ask = false }) end, { desc = "avante: chat with the codebase" })
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
    if args.source == nil then args.source = false end

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
  cmd("Clear", function() require("avante.path").clear() end, { desc = "avante: clear all chat history" })
end

H.keymaps = function()
  vim.keymap.set({ "n", "v" }, "<Plug>(AvanteAsk)", function() require("avante.api").ask() end, { noremap = true })
  vim.keymap.set(
    { "n", "v" },
    "<Plug>(AvanteChat)",
    function() require("avante.api").ask({ ask = false }) end,
    { noremap = true }
  )
  vim.keymap.set("v", "<Plug>(AvanteEdit)", function() require("avante.api").edit() end, { noremap = true })
  vim.keymap.set("n", "<Plug>(AvanteRefresh)", function() require("avante.api").refresh() end, { noremap = true })
  vim.keymap.set("n", "<Plug>(AvanteBuild)", function() require("avante.api").build() end, { noremap = true })
  vim.keymap.set("n", "<Plug>(AvanteToggle)", function() M.toggle() end, { noremap = true })
  vim.keymap.set("n", "<Plug>(AvanteToggleDebug)", function() M.toggle.debug() end)
  vim.keymap.set("n", "<Plug>(AvanteToggleHint)", function() M.toggle.hint() end)
  vim.keymap.set("n", "<Plug>(AvanteToggleSuggestion)", function() M.toggle.suggestion() end)

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
    Utils.safe_keymap_set(
      "n",
      Config.mappings.toggle.suggestion,
      function() M.toggle.suggestion() end,
      { desc = "avante: toggle suggestion" }
    )
  end

  if Config.behaviour.auto_suggestions then
    Utils.safe_keymap_set("i", Config.mappings.suggestion.accept, function()
      local _, _, sg = M.get()
      sg:accept()
    end, {
      desc = "avante: accept suggestion",
      noremap = true,
      silent = true,
    })

    Utils.safe_keymap_set("i", Config.mappings.suggestion.dismiss, function()
      local _, _, sg = M.get()
      if sg:is_visible() then sg:dismiss() end
    end, {
      desc = "avante: dismiss suggestion",
      noremap = true,
      silent = true,
    })

    Utils.safe_keymap_set("i", Config.mappings.suggestion.next, function()
      local _, _, sg = M.get()
      sg:next()
    end, {
      desc = "avante: next suggestion",
      noremap = true,
      silent = true,
    })

    Utils.safe_keymap_set("i", Config.mappings.suggestion.prev, function()
      local _, _, sg = M.get()
      sg:prev()
    end, {
      desc = "avante: previous suggestion",
      noremap = true,
      silent = true,
    })
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

---@param opts? AskOptions
M.toggle_sidebar = function(opts)
  opts = opts or {}
  if opts.ask == nil then opts.ask = true end

  local sidebar = M.get()
  if not sidebar then
    M._init(api.nvim_get_current_tabpage())
    M.current.sidebar:open(opts)
    return true
  end

  return sidebar:toggle(opts)
end

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

M.toggle.suggestion = H.api(Utils.toggle_wrap({
  name = "suggestion",
  get = function() return Config.behaviour.auto_suggestions end,
  set = function(state)
    Config.override({ behaviour = { auto_suggestions = state } })
    local _, _, sg = M.get()
    if state ~= false then
      if sg then sg:setup_autocmds() end
      H.keymaps()
    else
      if sg then sg:delete_autocmds() end
    end
  end,
}))

setmetatable(M.toggle, {
  __index = M.toggle,
  __call = function() M.toggle_sidebar() end,
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
