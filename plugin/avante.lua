if vim.fn.has("nvim-0.10") == 0 then
  vim.api.nvim_echo({
    { "Avante requires at least nvim-0.10", "ErrorMsg" },
    { "Please upgrade your neovim version", "WarningMsg" },
    { "Press any key to exit", "ErrorMsg" },
  }, true, {})
  vim.fn.getchar()
  vim.cmd([[quit]])
end

if vim.g.avante ~= nil then return end

vim.g.avante = 1

--- NOTE: We will override vim.paste if img-clip.nvim is available to work with avante.nvim internal logic paste
local Clipboard = require("avante.clipboard")
local Config = require("avante.config")
local Utils = require("avante.utils")
local api = vim.api

if Config.support_paste_image() then
  vim.paste = (function(overridden)
    ---@param lines string[]
    ---@param phase -1|1|2|3
    return function(lines, phase)
      require("img-clip.util").verbose = false

      local bufnr = vim.api.nvim_get_current_buf()
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
      if filetype ~= "AvanteInput" then return overridden(lines, phase) end

      ---@type string
      local line = lines[1]

      local ok = Clipboard.paste_image(line)
      if not ok then return overridden(lines, phase) end

      -- After pasting, insert a new line and set cursor to this line
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
      local last_line = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
  end)(vim.paste)
end

---@param n string
---@param c vim.api.keyset.user_command.callback
---@param o vim.api.keyset.user_command.opts
local function cmd(n, c, o)
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
    vim.tbl_deep_extend("force", args, { ask = q_ask, question = #q_parts > 0 and table.concat(q_parts, " ") or nil })
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
cmd(
  "ChatNew",
  function() require("avante.api").ask({ ask = false, new_chat = true }) end,
  { desc = "avante: create new chat" }
)
cmd("Toggle", function() require("avante").toggle() end, { desc = "avante: toggle AI panel" })
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
cmd(
  "Edit",
  function(opts) require("avante.api").edit(vim.trim(opts.args), opts.line1, opts.line2) end,
  { desc = "avante: edit selected block", nargs = "*", range = 2 }
)
cmd("Refresh", function() require("avante.api").refresh() end, { desc = "avante: refresh windows" })
cmd("Focus", function() require("avante.api").focus() end, { desc = "avante: switch focus windows" })
cmd("SwitchProvider", function(opts) require("avante.api").switch_provider(vim.trim(opts.args or "")) end, {
  nargs = 1,
  desc = "avante: switch provider",
  complete = function(_, line, _)
    local prefix = line:match("AvanteSwitchProvider%s*(.*)$") or ""
    ---@param key string
    return vim.tbl_filter(function(key) return key:find(prefix, 1, true) == 1 end, Config.provider_names)
  end,
})
cmd(
  "SwitchSelectorProvider",
  function(opts) require("avante.api").switch_selector_provider(vim.trim(opts.args or "")) end,
  {
    nargs = 1,
    desc = "avante: switch selector provider",
  }
)
cmd("Clear", function(opts)
  local arg = vim.trim(opts.args or "")
  arg = arg == "" and "history" or arg
  if arg == "history" then
    local sidebar = require("avante").get()
    if not sidebar then
      Utils.error("No sidebar found")
      return
    end
    sidebar:clear_history()
  elseif arg == "cache" then
    local P = require("avante.path")
    local history_path = P.history_path:absolute()
    local cache_path = P.cache_path:absolute()
    local prompt = string.format("Recursively delete %s and %s?", history_path, cache_path)
    if vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1 then require("avante.path").clear() end
  else
    Utils.error("Invalid argument. Valid arguments: 'history', 'memory', 'cache'")
    return
  end
end, {
  desc = "avante: clear history, memory or cache",
  nargs = "?",
  complete = function(_, _, _) return { "history", "memory", "cache" } end,
})
cmd("ShowRepoMap", function() require("avante.repo_map").show() end, { desc = "avante: show repo map" })
cmd("Models", function() require("avante.model_selector").open() end, { desc = "avante: show models" })
cmd("History", function() require("avante.api").select_history() end, { desc = "avante: show histories" })
cmd("Stop", function() require("avante.api").stop() end, { desc = "avante: stop current AI request" })
