if vim.fn.has("nvim-0.11") == 0 then
  vim.api.nvim_echo({
    { "Avante requires at least nvim-0.11", "ErrorMsg" },
    { "Please upgrade your neovim version", "WarningMsg" },
    { "Press any key to exit", "ErrorMsg" },
  }, true, {})
  vim.fn.getchar()
  vim.cmd([[quit]])
end

if vim.g.avante_loaded ~= nil then return end

vim.g.avante_loaded = 1

--- NOTE: We will override vim.paste if img-clip.nvim is available to work with avante.nvim internal logic paste
local Clipboard = require("avante.clipboard")
local Config = require("avante.config")
local Utils = require("avante.utils")
local P = require("avante.path")
local api = vim.api

if Config.support_paste_image() then
  vim.paste = (function(overridden)
    ---@param lines string[]
    ---@param phase -1|1|2|3
    return function(lines, phase)
      -- NOTE: require("img-clip.util").verbose = false does NOT silence warnings
      -- because img-clip's warn() reads config.get_opt("verbose"), not util.verbose.
      -- Suppress via api_opts which has highest priority in img-clip's config lookup.
      require("img-clip.config").api_opts = { default = { verbose = false } }

      local bufnr = vim.api.nvim_get_current_buf()
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
      if filetype ~= "AvanteInput" then return overridden(lines, phase) end

      ---@type string
      local line = lines[1]

      -- Only attempt image paste if the line looks like an image path/URL,
      -- or if the clipboard actually contains an image. This avoids the
      -- "Content is not an image" warning when Chinese IME commits text via
      -- vim.paste (which is not a real paste from clipboard).
      local img_clip_util = require("img-clip.util")
      local img_clip_clipboard = require("img-clip.clipboard")
      local is_image_candidate = (line and (img_clip_util.is_image_url(line) or img_clip_util.is_image_path(line)))
        or img_clip_clipboard.content_is_image()
      if not is_image_candidate then return overridden(lines, phase) end

      local ok = Clipboard.paste_image(line)
      if not ok then return overridden(lines, phase) end

      -- After pasting, insert a new line and set cursor to this line
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
      local last_line = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
  end)(vim.paste)
end

---@param suffix string command suffix
---@param callback vim.api.keyset.user_command.callback
---@param opts vim.api.keyset.user_command.opts
local function cmd(suffix, callback, opts)
  opts = vim.tbl_extend("force", { nargs = 0 }, opts or {})
  api.nvim_create_user_command("Avante" .. suffix, callback, opts)
end

local function ask_complete(prefix, _, _)
  local candidates = {} ---@type string[]
  vim.list_extend(
    candidates,
    ---@param x string
    vim.tbl_map(function(x) return "position=" .. x end, { "left", "right", "top", "bottom" })
  )
  vim.list_extend(
    candidates,
    ---@param x string
    vim.tbl_map(function(x) return "project_root=" .. x.root end, P.list_projects())
  )
  return vim.tbl_filter(function(candidate) return vim.startswith(candidate, prefix) end, candidates)
end

cmd("Ask", function(opts)
  ---@type AskOptions
  local args = { question = nil, win = {} }

  local parsed_args, question = Utils.parse_args(opts.fargs, {
    collect_remaining = true,
    boolean_keys = { "ask" },
  })

  if parsed_args.position then args.win.position = parsed_args.position end

  require("avante.api").ask(vim.tbl_deep_extend("force", args, {
    ask = parsed_args.ask,
    project_root = parsed_args.project_root,
    question = question or nil,
  }))
end, {
  desc = "avante: ask AI for code suggestions",
  nargs = "*",
  complete = ask_complete,
})
cmd("Chat", function(opts)
  local args = Utils.parse_args(opts.fargs)
  args.ask = false

  require("avante.api").ask(args)
end, {
  desc = "avante: chat with the codebase",
  nargs = "*",
  complete = ask_complete,
})
cmd("ChatNew", function(opts)
  local args = Utils.parse_args(opts.fargs)
  args.ask = false
  args.new_chat = true
  require("avante.api").ask(args)
end, { desc = "avante: create new chat", nargs = "*", complete = ask_complete })
cmd("Toggle", function() require("avante").toggle() end, { desc = "avante: toggle AI panel" })
cmd("Build", function(opts)
  local args = Utils.parse_args(opts.fargs)

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
cmd("SwitchProvider", function(_opts)
  local providers = vim.tbl_keys(Config.providers)
  vim.list_extend(providers, vim.tbl_keys(Config.acp_providers))
  vim.ui.select(providers, { prompt = "Provider> " }, function(choice, idx)
    if idx ~= nil then require("avante.api").switch_provider(vim.trim(choice)) end
  end)
end, {
  nargs = 0,
  desc = "avante: switch provider",
})
cmd(
  "SwitchSelectorProvider",
  function(opts) require("avante.api").switch_selector_provider(vim.trim(opts.args or "")) end,
  {
    nargs = 1,
    desc = "avante: switch selector provider",
  }
)
cmd("SwitchInputProvider", function(opts) require("avante.api").switch_input_provider(vim.trim(opts.args or "")) end, {
  nargs = 1,
  desc = "avante: switch input provider",
  complete = function(_, line, _)
    local prefix = line:match("AvanteSwitchInputProvider%s*(.*)$") or ""
    local providers = { "native", "dressing", "snacks" }
    return vim.tbl_filter(function(key) return key:find(prefix, 1, true) == 1 end, providers)
  end,
})
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
    local history_path = vim.fs.abspath(tostring(P.history_path))
    local cache_path = vim.fs.abspath(tostring(P.cache_path))
    local prompt = string.format("Recursively delete %s and %s?", history_path, cache_path)
    if vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1 then P.clear() end
  else
    Utils.error("Invalid argument. Valid arguments: 'history', 'memory', 'cache'")
    return
  end
end, {
  desc = "avante: clear history, memory or cache",
  nargs = "?",
  complete = function(_, _, _) return { "history", "cache" } end,
})
cmd("ShowRepoMap", function() require("avante.repo_map").show() end, { desc = "avante: show repo map" })
cmd("TokenBreakdown", function()
  local sidebar = require("avante").get()
  if not sidebar then
    Utils.warn("No Avante sidebar found. Open Avante first (:AvanteAsk or :AvanteChat).")
    return
  end
  sidebar:get_generate_prompts_options("", function(opts)
    local Llm = require("avante.llm")
    local breakdown, total = Llm.calculate_tokens_breakdown(opts)

    if #breakdown == 0 then
      Utils.warn("No token breakdown available (ACP providers are not supported).")
      return
    end

    -- Build display lines
    local max_name_len = 0
    for _, item in ipairs(breakdown) do
      max_name_len = math.max(max_name_len, #item.name)
    end
    local fmt = "  %-" .. max_name_len .. "s  %7d  (%3d%%)"
    local sep = string.rep("─", max_name_len + 20)

    local lines = {
      "  Token breakdown for a fresh request",
      sep,
      "",
    }
    for _, item in ipairs(breakdown) do
      local pct = total > 0 and math.floor(item.tokens / total * 100 + 0.5) or 0
      table.insert(lines, string.format(fmt, item.name, item.tokens, pct))
    end
    table.insert(lines, "")
    table.insert(lines, sep)
    table.insert(lines, string.format("  %-" .. max_name_len .. "s  %7d", "TOTAL", total))
    table.insert(lines, "")
    table.insert(lines, "  Press q or <Esc> to close")

    -- Open a scratch floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("filetype", "avante_token_breakdown", { buf = buf })

    local width = math.min(math.max(60, max_name_len + 22), vim.o.columns - 4)
    local height = math.min(#lines, vim.o.lines - 4)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
      title = " Avante Token Breakdown ",
      title_pos = "center",
    })
    vim.api.nvim_set_option_value("wrap", false, { win = win })

    -- Close keymaps
    for _, key in ipairs({ "q", "<Esc>" }) do
      vim.keymap.set("n", key, function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
    end
  end)
end, { desc = "avante: show per-component token count breakdown" })
cmd("Models", function() require("avante.model_selector").open() end, { desc = "avante: show models" })
cmd("ACPModels", function() require("avante.api").select_acp_model() end, { desc = "avante: switch ACP model" })
cmd("ACPModes", function() require("avante.api").select_acp_mode() end, { desc = "avante: switch ACP mode" })
cmd("History", function() require("avante.api").select_history() end, { desc = "avante: show histories" })
cmd("Stop", function() require("avante.api").stop() end, { desc = "avante: stop current AI request" })
