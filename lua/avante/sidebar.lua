local View = require("avante.view")

local Path = require("plenary.path")
local N = require("nui-components")
local Renderer = require("nui-components.renderer")
local diff = require("avante.diff")
local config = require("avante.config")
local ai_bot = require("avante.ai_bot")
local api = vim.api
local fn = vim.fn

local CODEBLOCK_KEYBINDING_NAMESPACE = api.nvim_create_namespace("AVANTE_CODEBLOCK_KEYBINDING")
local PRIORITY = vim.highlight.priorities.user

---@class avante.Sidebar
local Sidebar = {}

---@class avante.SidebarState
---@field win integer
---@field buf integer

---@class avante.Renderer
---@field close fun(): nil
---@field focus fun(): nil

---@class avante.Sidebar
---@field id integer
---@field view avante.View
---@field code avante.SidebarState
---@field renderer avante.Renderer

function Sidebar:new(id)
  return setmetatable({
    id = id,
    code = { buf = 0, win = 0 },
    view = View:new(),
    renderer = nil,
  }, { __index = Sidebar })
end

function Sidebar:destroy()
  self.view = nil
  self.code = nil
  self.renderer = nil
end

function Sidebar:reset()
  self.code = { buf = 0, win = 0 }
end

function Sidebar:open()
  if not self.view:is_open() then
    self:intialize()
    self:render()
    self:focus()
  else
    self:focus()
  end
  return self
end

function Sidebar:toggle()
  if self.view:is_open() then
    self:close()
    return false
  else
    self:open()
    return true
  end
end

function Sidebar:has_code_win()
  return self.code.win
    and self.code.buf
    and self.code.win ~= 0
    and self.code.buf ~= 0
    and api.nvim_win_is_valid(self.code.win)
    and api.nvim_buf_is_valid(self.code.buf)
end

function Sidebar:focus_code()
  if self:has_code_win() then
    fn.win_gotoid(self.code.win)
    return true
  end
  return false
end

function Sidebar:focus_toggle()
  if self.view:is_open() and self:has_code_win() then
    local winid = fn.win_getid()
    if winid == self.code.win then
      fn.win_gotoid(self.view.win)
    else
      fn.win_gotoid(self.code.win)
    end
    return true
  end
  return false
end

local get_renderer_size_and_position = function()
  local renderer_width = math.ceil(vim.o.columns * 0.3)
  local renderer_height = vim.o.lines
  local renderer_position = vim.o.columns - renderer_width
  return renderer_width, renderer_height, renderer_position
end

function Sidebar:intialize()
  self.code.win = api.nvim_get_current_win()
  self.code.buf = api.nvim_get_current_buf()

  local split_command = "botright vs"
  local renderer_width, renderer_height, renderer_position = get_renderer_size_and_position()

  self.view:setup(split_command, renderer_width)

  local winid = fn.bufwinid(self.view.buf)
  --- setup coord
  self.renderer = Renderer.create({
    width = api.nvim_win_get_width(winid),
    height = renderer_height,
    position = renderer_position,
    relative = { type = "win", winid = winid },
  })

  -- reset states when buffer is closed
  api.nvim_buf_attach(self.code.buf, false, {
    on_detach = function(_, _)
      self:reset()
    end,
  })
end

function Sidebar:close()
  self.renderer:close()
  fn.win_gotoid(self.code.win)
end

---@return boolean
function Sidebar:focus()
  if self.view:is_open() then
    fn.win_gotoid(self.view.win)
    self.renderer:focus()
    return true
  end
  return false
end

function Sidebar:get_current_code_content()
  local lines = api.nvim_buf_get_lines(self.code.buf, 0, -1, false)
  return table.concat(lines, "\n")
end

---@type content string
function Sidebar:update_content(content)
  vim.defer_fn(function()
    api.nvim_set_option_value("modifiable", true, { buf = self.view.buf })
    api.nvim_buf_set_lines(self.view.buf, 0, -1, false, vim.split(content, "\n"))
    api.nvim_set_option_value("modifiable", false, { buf = self.view.buf })
    api.nvim_set_option_value("filetype", "Avante", { buf = self.view.buf })

    -- Move to the bottom
    api.nvim_win_set_cursor(self.view.win, { api.nvim_buf_line_count(self.view.buf), 0 })
    api.nvim_set_current_win(self.code.win)
  end, 0)
end

local function parse_codeblocks(buf)
  local codeblocks = {}
  local in_codeblock = false
  local start_line = nil
  local lang = nil

  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
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

---@param codeblocks table<integer, any>
local function is_cursor_in_codeblock(codeblocks)
  local cursor_pos = api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1] - 1 -- 转换为 0-indexed 行号

  for _, block in ipairs(codeblocks) do
    if cursor_line >= block.start_line and cursor_line <= block.end_line then
      return block
    end
  end

  return nil
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

---@param sidebar avante.Sidebar
local function get_chat_history_filename(sidebar)
  local code_buf_name = api.nvim_buf_get_name(sidebar.code.buf)
  local relative_path = fn.fnamemodify(code_buf_name, ":~:.")
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(relative_path, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  return fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g")
end

-- Function to get the chat history file path
local function get_chat_history_file(sidebar)
  local project_root = get_project_root()
  local filename = get_chat_history_filename(sidebar)
  local history_dir = Path:new(project_root, ".avante_chat_history")
  return history_dir:joinpath(filename .. ".json")
end

-- Function to get current timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- Function to load chat history
local function load_chat_history(sidebar)
  local history_file = get_chat_history_file(sidebar)
  if history_file:exists() then
    local content = history_file:read()
    return fn.json_decode(content)
  end
  return {}
end

-- Function to save chat history
local function save_chat_history(sidebar, history)
  local history_file = get_chat_history_file(sidebar)
  local history_dir = history_file:parent()

  -- Create the directory if it doesn't exist
  if not history_dir:exists() then
    history_dir:mkdir({ parents = true })
  end

  history_file:write(fn.json_encode(history), "w")
end

function Sidebar:update_content_with_history(history)
  local content = ""
  for _, entry in ipairs(history) do
    content = content .. "## " .. entry.timestamp .. "\n\n"
    content = content .. "> " .. entry.requirement:gsub("\n", "\n> ") .. "\n\n"
    content = content .. entry.response .. "\n\n"
    content = content .. "---\n\n"
  end
  self:update_content(content)
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

---@param sidebar avante.Sidebar
---@return string
local function get_content_between_separators(sidebar)
  local separator = "---"
  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local lines = api.nvim_buf_get_lines(sidebar.view.buf, 0, -1, false)
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

function Sidebar:render()
  local current_apply_extmark_id = nil

  local function show_apply_button(block)
    if current_apply_extmark_id then
      api.nvim_buf_del_extmark(self.view.buf, CODEBLOCK_KEYBINDING_NAMESPACE, current_apply_extmark_id)
    end

    current_apply_extmark_id =
      api.nvim_buf_set_extmark(self.view.buf, CODEBLOCK_KEYBINDING_NAMESPACE, block.start_line, -1, {
        virt_text = { { " [Press <A> to Apply these patches] ", "Keyword" } },
        virt_text_pos = "right_align",
        hl_group = "Keyword",
        priority = PRIORITY,
      })
  end

  local function apply()
    local content = self:get_current_code_content()
    local response = get_content_between_separators(self)
    local snippets = extract_code_snippets(response)
    local conflict_content = get_conflict_content(content, snippets)

    vim.defer_fn(function()
      api.nvim_buf_set_lines(self.code.buf, 0, -1, false, conflict_content)

      api.nvim_set_current_win(self.code.win)
      api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
      diff.add_visited_buffer(self.code.buf)
      diff.process(self.code.buf)
      api.nvim_feedkeys("gg", "n", false)
      vim.defer_fn(function()
        vim.cmd("AvanteConflictNextConflict")
        api.nvim_feedkeys("zz", "n", false)
      end, 1000)
    end, 10)
  end

  local function bind_apply_key()
    vim.keymap.set("n", "A", apply, { buffer = self.view.buf, noremap = true, silent = true })
  end

  local function unbind_apply_key()
    pcall(vim.keymap.del, "n", "A", { buffer = self.view.buf })
  end

  local codeblocks = {}

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = self.view.buf,
    callback = function()
      local block = is_cursor_in_codeblock(codeblocks)

      if block then
        show_apply_button(block)
        bind_apply_key()
      else
        api.nvim_buf_clear_namespace(self.view.buf, CODEBLOCK_KEYBINDING_NAMESPACE, 0, -1)
        unbind_apply_key()
      end
    end,
  })

  api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    buffer = self.view.buf,
    callback = function()
      codeblocks = parse_codeblocks(self.view.buf)
      self.renderer:focus()
    end,
  })

  local autocmd_id
  self.renderer:on_mount(function()
    autocmd_id = api.nvim_create_autocmd("VimResized", {
      callback = function()
        local width, height, _ = get_renderer_size_and_position()
        self.renderer:set_size({ width = width, height = height })
      end,
    })
  end)

  self.renderer:on_unmount(function()
    if autocmd_id ~= nil then
      api.nvim_del_autocmd(autocmd_id)
    end

    self.view:close()
  end)

  local signal = N.create_signal({
    is_loading = false,
    text = "",
  })

  local chat_history = load_chat_history(self)
  self:update_content_with_history(chat_history)

  local function handle_submit()
    local state = signal:get_value()
    local user_input = state.text

    local timestamp = get_timestamp()
    self:update_content(
      "## "
        .. timestamp
        .. "\n\n> "
        .. user_input:gsub("\n", "\n> ")
        .. "\n\nGenerating response from "
        .. config.get().provider
        .. " ...\n"
    )

    local content = self:get_current_code_content()
    local content_with_line_numbers = prepend_line_number(content)
    local full_response = ""

    signal.is_loading = true

    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.buf })

    ai_bot.call_ai_api_stream(user_input, filetype, content_with_line_numbers, function(chunk)
      full_response = full_response .. chunk
      self:update_content("## " .. timestamp .. "\n\n> " .. user_input:gsub("\n", "\n> ") .. "\n\n" .. full_response)
      vim.schedule(function()
        vim.cmd("redraw")
      end)
    end, function(err)
      signal.is_loading = false

      if err ~= nil then
        self:update_content(
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
      self:update_content(
        "## "
          .. timestamp
          .. "\n\n> "
          .. user_input:gsub("\n", "\n> ")
          .. "\n\n"
          .. full_response
          .. "\n\n**Generation complete!** Please review the code suggestions above.\n\n\n\n"
      )

      -- Display notification
      -- show_notification("Content generation complete!")

      -- Save chat history
      table.insert(chat_history or {}, { timestamp = timestamp, requirement = user_input, response = full_response })
      save_chat_history(self, chat_history)
    end)
  end

  local body = function()
    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.buf })
    local icon = require("nvim-web-devicons").get_icon_by_filetype(filetype, {})
    local code_file_fullpath = api.nvim_buf_get_name(self.code.buf)
    local code_filename = fn.fnamemodify(code_file_fullpath, ":t")

    return N.rows(
      { flex = 0 },
      N.box(
        {
          direction = "column",
          size = vim.o.lines - 4,
        },
        N.buffer({
          id = "response",
          flex = 1,
          buf = self.view.buf,
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
      N.gap(1),
      N.columns(
        { flex = 0 },
        N.text_input({
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
        N.gap(1),
        N.spinner({
          is_loading = signal.is_loading,
          padding = { top = 1, right = 1 },
          ---@diagnostic disable-next-line: undefined-field
          hidden = signal.is_loading:negate(),
        })
      )
    )
  end

  self.renderer:render(body)
  return self
end

return Sidebar
