local M = {}
local Path = require("plenary.path")
local n = require("nui-components")
local diff = require("avante.diff")
local tiktoken = require("avante.tiktoken")
local config = require("avante.config")
local ai_bot = require("avante.ai_bot")
local api = vim.api
local fn = vim.fn

local RESULT_BUF_NAME = "AVANTE_RESULT"
local CONFLICT_BUF_NAME = "AVANTE_CONFLICT"

local CODEBLOCK_KEYBINDING_NAMESPACE = vim.api.nvim_create_namespace("AVANTE_CODEBLOCK_KEYBINDING")
local PRIORITY = vim.highlight.priorities.user

local function parse_codeblocks(buf)
  local codeblocks = {}
  local in_codeblock = false
  local start_line = nil
  local lang = nil

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("^```") then
      -- parse language
      local lang_ = line:match("^```(%w+)")
      if in_codeblock and not lang_ then
        table.insert(codeblocks, { start_line = start_line, end_line = i - 1, lang = lang })
        in_codeblock = false
      elseif lang_ then
        lang = lang_
        start_line = i - 1
        in_codeblock = true
      end
    end
  end

  return codeblocks
end

local function is_cursor_in_codeblock(codeblocks)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1] - 1 -- 转换为 0-indexed 行号

  for _, block in ipairs(codeblocks) do
    if cursor_line >= block.start_line and cursor_line <= block.end_line then
      return block
    end
  end

  return nil
end

local function create_result_buf()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("swapfile", false, { buf = buf })
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  api.nvim_buf_set_name(buf, RESULT_BUF_NAME)
  return buf
end

local result_buf = create_result_buf()

local function is_code_buf(buf)
  local ignored_filetypes = {
    "dashboard",
    "alpha",
    "neo-tree",
    "NvimTree",
    "TelescopePrompt",
    "Prompt",
    "qf",
    "help",
  }

  if api.nvim_buf_is_valid(buf) and api.nvim_get_option_value("buflisted", { buf = buf }) then
    local buftype = api.nvim_get_option_value("buftype", { buf = buf })
    local filetype = api.nvim_get_option_value("filetype", { buf = buf })

    if buftype == "" and filetype ~= "" and not vim.tbl_contains(ignored_filetypes, filetype) then
      local bufname = api.nvim_buf_get_name(buf)
      if bufname ~= "" and bufname ~= RESULT_BUF_NAME and bufname ~= CONFLICT_BUF_NAME then
        return true
      end
    end
  end

  return false
end

local _cur_code_buf = nil

local function get_cur_code_buf()
  return _cur_code_buf
end

local function get_cur_code_buf_name()
  local code_buf = get_cur_code_buf()
  if code_buf == nil then
    print("Error: cannot get code buffer")
    return
  end
  return api.nvim_buf_get_name(code_buf)
end

local function get_cur_code_win()
  local code_buf = get_cur_code_buf()
  if code_buf == nil then
    print("Error: cannot get code buffer")
    return
  end
  return fn.bufwinid(code_buf)
end

local function get_cur_code_buf_content()
  local code_buf = get_cur_code_buf()
  if code_buf == nil then
    print("Error: cannot get code buffer")
    return {}
  end
  local lines = api.nvim_buf_get_lines(code_buf, 0, -1, false)
  return table.concat(lines, "\n")
end

local function prepend_line_number(content)
  local lines = vim.split(content, "\n")
  local result = {}
  for i, line in ipairs(lines) do
    table.insert(result, "L" .. i .. ": " .. line)
  end
  return table.concat(result, "\n")
end

local function extract_code_snippets(content)
  local snippets = {}
  local current_snippet = {}
  local in_code_block = false
  local lang, start_line, end_line
  local explanation = ""

  for line in content:gmatch("[^\r\n]+") do
    local start_line_str, end_line_str = line:match("^Replace lines: (%d+)-(%d+)")
    if start_line_str ~= nil and end_line_str ~= nil then
      start_line = tonumber(start_line_str)
      end_line = tonumber(end_line_str)
    end
    if line:match("^```") then
      if in_code_block then
        if start_line ~= nil and end_line ~= nil then
          table.insert(snippets, {
            range = { start_line, end_line },
            content = table.concat(current_snippet, "\n"),
            lang = lang,
            explanation = explanation,
          })
        end
        current_snippet = {}
        start_line, end_line = nil, nil
        explanation = ""
        in_code_block = false
      else
        lang = line:match("^```(%w+)")
        if not lang or lang == "" then
          lang = "text"
        end
        in_code_block = true
      end
    elseif in_code_block then
      table.insert(current_snippet, line)
    else
      explanation = explanation .. line .. "\n"
    end
  end

  return snippets
end

local function update_result_buf_content(content)
  local current_win = api.nvim_get_current_win()
  local result_win = fn.bufwinid(result_buf)

  vim.defer_fn(function()
    api.nvim_set_option_value("modifiable", true, { buf = result_buf })
    api.nvim_buf_set_lines(result_buf, 0, -1, false, vim.split(content, "\n"))
    api.nvim_set_option_value("modifiable", false, { buf = result_buf })
    api.nvim_set_option_value("filetype", "markdown", { buf = result_buf })
    if result_win ~= -1 then
      -- Move to the bottom
      api.nvim_win_set_cursor(result_win, { api.nvim_buf_line_count(result_buf), 0 })
      api.nvim_set_current_win(current_win)
    end
  end, 0)
end

-- Add a new function to display notifications
local function show_notification(message)
  vim.notify(message, vim.log.levels.INFO, {
    title = "AI Assistant",
    timeout = 3000,
  })
end

-- Function to get the current project root directory
local function get_project_root()
  local current_file = fn.expand("%:p")
  local current_dir = fn.fnamemodify(current_file, ":h")
  local git_root = fn.systemlist("git -C " .. fn.shellescape(current_dir) .. " rev-parse --show-toplevel")[1]
  return git_root or current_dir
end

local function get_chat_history_filename()
  local code_buf_name = get_cur_code_buf_name()
  if code_buf_name == nil then
    print("Error: cannot get code buffer name")
    return
  end
  local relative_path = fn.fnamemodify(code_buf_name, ":~:.")
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(relative_path, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  return fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g")
end

-- Function to get the chat history file path
local function get_chat_history_file()
  local project_root = get_project_root()
  local filename = get_chat_history_filename()
  local history_dir = Path:new(project_root, ".avante_chat_history")
  return history_dir:joinpath(filename .. ".json")
end

-- Function to get current timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- Function to load chat history
local function load_chat_history()
  local history_file = get_chat_history_file()
  if history_file:exists() then
    local content = history_file:read()
    return fn.json_decode(content)
  end
  return {}
end

-- Function to save chat history
local function save_chat_history(history)
  local history_file = get_chat_history_file()
  local history_dir = history_file:parent()

  -- Create the directory if it doesn't exist
  if not history_dir:exists() then
    history_dir:mkdir({ parents = true })
  end

  history_file:write(fn.json_encode(history), "w")
end

local function update_result_buf_with_history(history)
  local content = ""
  for _, entry in ipairs(history) do
    content = content .. "## " .. entry.timestamp .. "\n\n"
    content = content .. "> " .. entry.requirement:gsub("\n", "\n> ") .. "\n\n"
    content = content .. entry.response .. "\n\n"
    content = content .. "---\n\n"
  end
  update_result_buf_content(content)
end

local function trim_line_number_prefix(line)
  return line:gsub("^L%d+: ", "")
end

local function get_conflict_content(content, snippets)
  -- sort snippets by start_line
  table.sort(snippets, function(a, b)
    return a.range[1] < b.range[1]
  end)

  local lines = vim.split(content, "\n")
  local result = {}
  local current_line = 1

  for _, snippet in ipairs(snippets) do
    local start_line, end_line = unpack(snippet.range)

    while current_line < start_line do
      table.insert(result, lines[current_line])
      current_line = current_line + 1
    end

    table.insert(result, "<<<<<<< HEAD")
    for i = start_line, end_line do
      table.insert(result, lines[i])
    end
    table.insert(result, "=======")

    for _, line in ipairs(vim.split(snippet.content, "\n")) do
      line = trim_line_number_prefix(line)
      table.insert(result, line)
    end

    table.insert(result, ">>>>>>> Snippet")

    current_line = end_line + 1
  end

  while current_line <= #lines do
    table.insert(result, lines[current_line])
    current_line = current_line + 1
  end

  return result
end

local function get_content_between_separators()
  local separator = "---"
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start_line, end_line

  for i = cursor_line, 1, -1 do
    if lines[i] == separator then
      start_line = i + 1
      break
    end
  end
  start_line = start_line or 1

  for i = cursor_line, #lines do
    if lines[i] == separator then
      end_line = i - 1
      break
    end
  end
  end_line = end_line or #lines

  if lines[cursor_line] == separator then
    if cursor_line > 1 and lines[cursor_line - 1] ~= separator then
      end_line = cursor_line - 1
    elseif cursor_line < #lines and lines[cursor_line + 1] ~= separator then
      start_line = cursor_line + 1
    end
  end

  local content = table.concat(vim.list_slice(lines, start_line, end_line), "\n")
  return content
end

local get_renderer_size_and_position = function()
  local renderer_width = math.ceil(vim.o.columns * 0.3)
  local renderer_height = vim.o.lines
  local renderer_position = vim.o.columns - renderer_width
  return renderer_width, renderer_height, renderer_position
end

function M.render_sidebar()
  if result_buf ~= nil and api.nvim_buf_is_valid(result_buf) then
    api.nvim_buf_delete(result_buf, { force = true })
  end

  result_buf = create_result_buf()

  local current_apply_extmark_id = nil

  local function show_apply_button(block)
    if current_apply_extmark_id then
      api.nvim_buf_del_extmark(result_buf, CODEBLOCK_KEYBINDING_NAMESPACE, current_apply_extmark_id)
    end

    current_apply_extmark_id =
      api.nvim_buf_set_extmark(result_buf, CODEBLOCK_KEYBINDING_NAMESPACE, block.start_line, -1, {
        virt_text = { { " [Press <A> to Apply these patches] ", "Keyword" } },
        virt_text_pos = "right_align",
        hl_group = "Keyword",
        priority = PRIORITY,
      })
  end

  local function apply()
    local code_buf = get_cur_code_buf()
    if code_buf == nil then
      error("Error: cannot get code buffer")
      return
    end
    local content = get_cur_code_buf_content()
    local response = get_content_between_separators()
    local snippets = extract_code_snippets(response)
    local conflict_content = get_conflict_content(content, snippets)

    vim.defer_fn(function()
      api.nvim_buf_set_lines(code_buf, 0, -1, false, conflict_content)
      local code_win = get_cur_code_win()
      if code_win == nil then
        error("Error: cannot get code window")
        return
      end
      api.nvim_set_current_win(code_win)
      api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
      diff.add_visited_buffer(code_buf)
      diff.process(code_buf)
      api.nvim_feedkeys("gg", "n", false)
      vim.defer_fn(function()
        vim.cmd("AvanteConflictNextConflict")
        api.nvim_feedkeys("zz", "n", false)
      end, 1000)
    end, 10)
  end

  local function bind_apply_key()
    vim.keymap.set("n", "A", apply, { buffer = result_buf, noremap = true, silent = true })
  end

  local function unbind_apply_key()
    pcall(vim.keymap.del, "n", "A", { buffer = result_buf })
  end

  local codeblocks = {}

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = result_buf,
    callback = function()
      local block = is_cursor_in_codeblock(codeblocks)

      if block then
        show_apply_button(block)
        bind_apply_key()
      else
        api.nvim_buf_clear_namespace(result_buf, CODEBLOCK_KEYBINDING_NAMESPACE, 0, -1)
        unbind_apply_key()
      end
    end,
  })

  api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    buffer = result_buf,
    callback = function()
      codeblocks = parse_codeblocks(result_buf)
    end,
  })

  local renderer_width, renderer_height, renderer_position = get_renderer_size_and_position()

  local renderer = n.create_renderer({
    width = renderer_width,
    height = renderer_height,
    position = renderer_position,
    relative = "editor",
  })

  local autocmd_id
  renderer:on_mount(function()
    autocmd_id = api.nvim_create_autocmd("VimResized", {
      callback = function()
        local width, height, _ = get_renderer_size_and_position()
        renderer:set_size({ width = width, height = height })
      end,
    })
  end)

  renderer:on_unmount(function()
    if autocmd_id ~= nil then
      api.nvim_del_autocmd(autocmd_id)
    end
  end)

  local signal = n.create_signal({
    is_loading = false,
    text = "",
  })

  local chat_history = load_chat_history()
  update_result_buf_with_history(chat_history)

  local function handle_submit()
    local state = signal:get_value()
    local user_input = state.text

    local timestamp = get_timestamp()
    update_result_buf_content(
      "## "
        .. timestamp
        .. "\n\n> "
        .. user_input:gsub("\n", "\n> ")
        .. "\n\nGenerating response from "
        .. config.get().provider
        .. " ...\n"
    )

    local code_buf = get_cur_code_buf()
    if code_buf == nil then
      error("Error: cannot get code buffer")
      return
    end
    local content = get_cur_code_buf_content()
    local content_with_line_numbers = prepend_line_number(content)
    local full_response = ""

    signal.is_loading = true

    local filetype = api.nvim_get_option_value("filetype", { buf = code_buf })

    ai_bot.call_ai_api_stream(user_input, filetype, content_with_line_numbers, function(chunk)
      full_response = full_response .. chunk
      update_result_buf_content(
        "## " .. timestamp .. "\n\n> " .. user_input:gsub("\n", "\n> ") .. "\n\n" .. full_response
      )
      vim.schedule(function()
        vim.cmd("redraw")
      end)
    end, function(err)
      signal.is_loading = false

      if err ~= nil then
        update_result_buf_content(
          "## "
            .. timestamp
            .. "\n\n> "
            .. user_input:gsub("\n", "\n> ")
            .. "\n\n"
            .. full_response
            .. "\n\n🚨 Error: "
            .. vim.inspect(err)
        )
        return
      end

      -- Execute when the stream request is actually completed
      update_result_buf_content(
        "## "
          .. timestamp
          .. "\n\n> "
          .. user_input:gsub("\n", "\n> ")
          .. "\n\n"
          .. full_response
          .. "\n\n**Generation complete!** Please review the code suggestions above.\n\n\n\n"
      )

      -- Display notification
      show_notification("Content generation complete!")

      -- Save chat history
      table.insert(chat_history or {}, { timestamp = timestamp, requirement = user_input, response = full_response })
      save_chat_history(chat_history)
    end)
  end

  local body = function()
    local code_buf = get_cur_code_buf()
    if code_buf == nil then
      error("Error: cannot get code buffer")
      return
    end
    local filetype = api.nvim_get_option_value("filetype", { buf = code_buf })
    local icon = require("nvim-web-devicons").get_icon_by_filetype(filetype, {})
    local code_file_fullpath = api.nvim_buf_get_name(code_buf)
    local code_filename = fn.fnamemodify(code_file_fullpath, ":t")

    return n.rows(
      { flex = 0 },
      n.box(
        {
          direction = "column",
          size = vim.o.lines - 4,
        },
        n.buffer({
          id = "response",
          flex = 1,
          buf = result_buf,
          autoscroll = true,
          border_label = {
            text = "💬 Avante Chat",
            align = "center",
          },
          padding = {
            top = 1,
            bottom = 1,
            left = 1,
            right = 1,
          },
        })
      ),
      n.gap(1),
      n.columns(
        { flex = 0 },
        n.text_input({
          id = "text-input",
          border_label = {
            text = string.format(" 🙋 Your question (with %s %s): ", icon, code_filename),
          },
          autofocus = true,
          wrap = true,
          flex = 1,
          on_change = function(value)
            local state = signal:get_value()
            local is_enter = value:sub(-1) == "\n" and #state.text < #value
            if is_enter then
              value = value:sub(1, -2)
            end
            signal.text = value
            if is_enter and #value > 0 then
              handle_submit()
            end
          end,
          padding = { left = 1, right = 1 },
        }),
        n.gap(1),
        n.spinner({
          is_loading = signal.is_loading,
          padding = { top = 1, right = 1 },
          ---@diagnostic disable-next-line: undefined-field
          hidden = signal.is_loading:negate(),
        })
      )
    )
  end

  renderer:render(body)
end

function M.setup()
  local bufnr = vim.api.nvim_get_current_buf()
  if is_code_buf(bufnr) then
    _cur_code_buf = bufnr
  end

  tiktoken.setup("gpt-4o")

  diff.setup({
    debug = false, -- log output to console
    default_mappings = config.get().mappings.diff, -- disable buffer local mapping created by this plugin
    default_commands = true, -- disable commands created by this plugin
    disable_diagnostics = true, -- This will disable the diagnostics in a buffer whilst it is conflicted
    list_opener = "copen",
    highlights = config.get().highlights.diff,
  })

  local function on_buf_enter()
    bufnr = vim.api.nvim_get_current_buf()
    if is_code_buf(bufnr) then
      _cur_code_buf = bufnr
    end
  end

  api.nvim_create_autocmd("BufEnter", {
    callback = on_buf_enter,
  })

  api.nvim_create_user_command("AvanteAsk", function()
    M.render_sidebar()
  end, {
    nargs = 0,
  })

  api.nvim_set_keymap("n", config.get().mappings.show_sidebar, "<cmd>AvanteAsk<CR>", { noremap = true, silent = true })
end

return M
