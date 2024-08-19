local api = vim.api
local fn = vim.fn

local Path = require("plenary.path")
local N = require("nui-components")

local Config = require("avante.config")
local View = require("avante.view")
local Diff = require("avante.diff")
local Llm = require("avante.llm")
local Utils = require("avante.utils")

local VIEW_BUFFER_UPDATED_PATTERN = "AvanteViewBufferUpdated"
local CODEBLOCK_KEYBINDING_NAMESPACE = api.nvim_create_namespace("AVANTE_CODEBLOCK_KEYBINDING")
local PRIORITY = vim.highlight.priorities.user

---@class avante.Sidebar
local Sidebar = {}

---@class avante.SidebarState
---@field win integer
---@field buf integer
---@field selection avante.SelectionResult | nil

---@class avante.Sidebar
---@field id integer
---@field view avante.View
---@field augroup integer
---@field code avante.SidebarState
---@field renderer NuiRenderer
---@field winid {result: integer, input: integer}
---@field bufnr {result: integer, input: integer}

---@param id integer the tabpage id retrieved from vim.api.nvim_get_current_tabpage()
function Sidebar:new(id)
  return setmetatable({
    id = id,
    code = { buf = 0, win = 0, selection = nil },
    winid = { result = 0, input = 0 },
    bufnr = { result = 0, input = 0 },
    view = View:new(),
    renderer = nil,
  }, { __index = self })
end

--- This function should only be used on TabClosed, nothing else.
function Sidebar:destroy()
  self:delete_autocmds()
  self.view = nil
  self.code = nil
  self.winid = nil
  self.renderer = nil
end

function Sidebar:delete_autocmds()
  if self.augroup then
    vim.api.nvim_del_augroup_by_id(self.augroup)
  end
  self.augroup = nil
end

function Sidebar:reset()
  self.code = { buf = 0, win = 0 }
  self.winid = { result = 0, input = 0 }
  self.bufnr = { result = 0, input = 0 }
  self:delete_autocmds()
end

function Sidebar:open()
  local in_visual_mode = Utils.in_visual_mode() and self:in_code_win()
  if not self.view:is_open() then
    self:intialize()
    self:render()
  else
    if in_visual_mode then
      self:close()
      self:intialize()
      self:render()
      return self
    end
    self:focus()
  end
  return self
end

function Sidebar:close()
  if self.renderer ~= nil then
    self.renderer:close()
  end
  if self.code ~= nil and api.nvim_win_is_valid(self.code.win) then
    fn.win_gotoid(self.code.win)
  end
end

---@return boolean
function Sidebar:focus()
  if self.view:is_open() then
    fn.win_gotoid(self.view.win)
    return true
  end
  return false
end

function Sidebar:in_code_win()
  return self.code.win == api.nvim_get_current_win()
end

function Sidebar:toggle()
  local in_visual_mode = Utils.in_visual_mode() and self:in_code_win()
  if self.view:is_open() and not in_visual_mode then
    self:close()
    return false
  else
    self:open()
    return true
  end
end

--- Initialize the sidebar instance.
--- @return avante.Sidebar The Sidebar instance.
function Sidebar:intialize()
  self.code.win = api.nvim_get_current_win()
  self.code.buf = api.nvim_get_current_buf()
  self.code.selection = Utils.get_visual_selection_and_range()

  local split_command = "botright vs"
  local layout = Config.get_renderer_layout_options()

  self.view:setup(split_command, layout.width)

  --- setup coord
  self.renderer = N.create_renderer({
    width = layout.width,
    height = layout.height,
    position = layout.position,
    relative = { type = "win", winid = fn.bufwinid(self.view.buf) },
  })

  self.renderer:add_mappings({
    {
      mode = { "n" },
      key = "q",
      handler = function()
        api.nvim_exec_autocmds("User", { pattern = Llm.CANCEL_PATTERN })
        self.renderer:close()
      end,
    },
    {
      mode = { "n" },
      key = "<Esc>",
      handler = function()
        api.nvim_exec_autocmds("User", { pattern = Llm.CANCEL_PATTERN })
        self.renderer:close()
      end,
    },
  })

  self.renderer:on_mount(function()
    self.winid.result = self.renderer:get_component_by_id("result").winid
    self.winid.input = self.renderer:get_component_by_id("input").winid
    self.bufnr.result = vim.api.nvim_win_get_buf(self.winid.result)
    self.bufnr.input = vim.api.nvim_win_get_buf(self.winid.input)
    self.augroup = api.nvim_create_augroup("avante_" .. self.id .. self.view.win, { clear = true })

    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.buf })
    local selected_code_buf = self.renderer:get_component_by_id("selected_code").bufnr
    api.nvim_set_option_value("filetype", filetype, { buf = selected_code_buf })
    api.nvim_set_option_value("wrap", false, { win = self.renderer:get_component_by_id("selected_code").winid })

    api.nvim_create_autocmd("BufEnter", {
      group = self.augroup,
      buffer = self.view.buf,
      callback = function()
        self:focus()
        vim.api.nvim_set_current_win(self.winid.input)
        return true
      end,
    })

    api.nvim_create_autocmd("VimResized", {
      group = self.augroup,
      callback = function()
        if not self.view:is_open() then
          return
        end
        local new_layout = Config.get_renderer_layout_options()
        vim.api.nvim_win_set_width(self.view.win, new_layout.width)
        vim.api.nvim_win_set_height(self.view.win, new_layout.height)
        self.renderer:set_size({ width = new_layout.width, height = new_layout.height })
        vim.defer_fn(function()
          vim.cmd("AvanteRefresh")
        end, 200)
      end,
    })

    local previous_winid = nil

    api.nvim_create_autocmd("WinLeave", {
      group = self.augroup,
      callback = function()
        previous_winid = vim.api.nvim_get_current_win()
      end,
    })

    api.nvim_create_autocmd("WinEnter", {
      group = self.augroup,
      callback = function()
        local current_win_id = vim.api.nvim_get_current_win()

        if current_win_id ~= self.view.win then
          return
        end

        if self.winid.result == previous_winid and api.nvim_win_is_valid(self.code.win) then
          api.nvim_set_current_win(self.code.win)
          return
        end

        if api.nvim_win_is_valid(self.winid.result) then
          api.nvim_set_current_win(self.winid.result)
          return
        end
      end,
    })
  end)

  self.renderer:on_unmount(function()
    self.view:close()
  end)

  -- reset states when buffer is closed
  api.nvim_buf_attach(self.code.buf, false, {
    on_detach = function(_, _)
      self:reset()
    end,
  })

  return self
end

function Sidebar:is_focused()
  return self.view:is_open() and self.code.win == api.nvim_get_current_win()
end

---@param content string concatenated content of the buffer
---@param opts? {focus?: boolean, stream?: boolean, scroll?: boolean, callback?: fun(): nil} whether to focus the result view
function Sidebar:update_content(content, opts)
  if not self.view.buf then
    return
  end
  opts = vim.tbl_deep_extend("force", { focus = true, scroll = true, stream = false, callback = nil }, opts or {})
  if opts.stream then
    local scroll_to_bottom = function()
      local last_line = api.nvim_buf_line_count(self.view.buf)

      local current_lines = api.nvim_buf_get_lines(self.view.buf, last_line - 1, last_line, false)

      if #current_lines > 0 then
        local last_line_content = current_lines[1]
        local last_col = #last_line_content
        xpcall(function()
          api.nvim_win_set_cursor(self.view.win, { last_line, last_col })
        end, function(err)
          return err
        end)
      end
    end

    vim.schedule(function()
      scroll_to_bottom()
      local lines = vim.split(content, "\n")
      api.nvim_set_option_value("modifiable", true, { buf = self.view.buf })
      api.nvim_buf_call(self.view.buf, function()
        api.nvim_put(lines, "c", true, true)
      end)
      api.nvim_set_option_value("modifiable", false, { buf = self.view.buf })
      api.nvim_set_option_value("filetype", "Avante", { buf = self.view.buf })
      if opts.scroll then
        scroll_to_bottom()
      end
      if opts.callback ~= nil then
        opts.callback()
      end
    end)
  else
    vim.defer_fn(function()
      if self.view.buf == nil then
        return
      end
      local lines = vim.split(content, "\n")
      local n_lines = #lines
      local last_line_length = lines[n_lines]
      api.nvim_set_option_value("modifiable", true, { buf = self.view.buf })
      api.nvim_buf_set_lines(self.view.buf, 0, -1, false, lines)
      api.nvim_set_option_value("modifiable", false, { buf = self.view.buf })
      api.nvim_set_option_value("filetype", "Avante", { buf = self.view.buf })
      if opts.focus and not self:is_focused() then
        xpcall(function()
          --- set cursor to bottom of result view
          api.nvim_set_current_win(self.winid.result)
        end, function(err)
          return err
        end)
      end

      if opts.scroll then
        xpcall(function()
          api.nvim_win_set_cursor(self.winid.result, { n_lines, #last_line_length })
        end, function(err)
          return err
        end)
      end

      if opts.callback ~= nil then
        opts.callback()
      end
    end, 0)
  end
  return self
end

---@class AvanteCodeblock
---@field start_line integer
---@field end_line integer
---@field lang string

---@return AvanteCodeblock[]
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

local function prepend_line_number(content, start_line)
  start_line = start_line or 1
  local lines = vim.split(content, "\n")
  local result = {}
  for i, line in ipairs(lines) do
    i = i + start_line - 1
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

  for _, line in ipairs(vim.split(content, "\n")) do
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

local function get_chat_record_prefix(timestamp, provider, model, request)
  provider = provider or "unknown"
  model = model or "unknown"
  return "- Datetime: "
    .. timestamp
    .. "\n\n"
    .. "- Model: "
    .. provider
    .. "/"
    .. model
    .. "\n\n> "
    .. request:gsub("\n", "\n> ")
    .. "\n\n"
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
    local prefix =
      get_chat_record_prefix(entry.timestamp, entry.provider, entry.model, entry.request or entry.requirement or "")
    content = content .. prefix
    content = content .. entry.response .. "\n\n"
    content = content .. "---\n\n"
  end
  self:update_content(content)
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
      line = line:gsub("^L%d+: ", "")
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

---@return string
function Sidebar:get_code_content()
  local lines = api.nvim_buf_get_lines(self.code.buf, 0, -1, false)
  return table.concat(lines, "\n")
end

---@return string
function Sidebar:get_content_between_separators()
  local separator = "---"
  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local lines = api.nvim_buf_get_lines(self.view.buf, 0, -1, false)
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
    local content = self:get_code_content()
    local response = self:get_content_between_separators()
    local snippets = extract_code_snippets(response)
    local conflict_content = get_conflict_content(content, snippets)

    vim.defer_fn(function()
      api.nvim_buf_set_lines(self.code.buf, 0, -1, false, conflict_content)

      api.nvim_set_current_win(self.code.win)
      api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
      Diff.add_visited_buffer(self.code.buf)
      Diff.process(self.code.buf)
      api.nvim_win_set_cursor(self.code.win, { 1, 0 })
      vim.defer_fn(function()
        vim.cmd("AvanteConflictNextConflict")
        vim.cmd("normal! zz")
      end, 1000)
    end, 10)
  end

  local function bind_apply_key()
    vim.keymap.set("n", "A", apply, { buffer = self.view.buf, noremap = true, silent = true })
  end

  local function unbind_apply_key()
    pcall(vim.keymap.del, "n", "A", { buffer = self.view.buf })
  end

  ---@type AvanteCodeblock[]
  local codeblocks = {}

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = self.view.buf,
    callback = function(ev)
      local block = is_cursor_in_codeblock(codeblocks)

      if block then
        show_apply_button(block)
        bind_apply_key()
      else
        api.nvim_buf_clear_namespace(ev.buf, CODEBLOCK_KEYBINDING_NAMESPACE, 0, -1)
        unbind_apply_key()
      end
    end,
  })

  api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    buffer = self.view.buf,
    callback = function(ev)
      codeblocks = parse_codeblocks(ev.buf)
    end,
  })

  api.nvim_create_autocmd("User", {
    pattern = VIEW_BUFFER_UPDATED_PATTERN,
    callback = function()
      codeblocks = parse_codeblocks(self.view.buf)
    end,
  })

  ---@type NuiSignal
  local signal = N.create_signal({ is_loading = false, text = "" })

  local chat_history = load_chat_history(self)
  self:update_content_with_history(chat_history)

  local function handle_submit()
    signal.is_loading = true
    local state = signal:get_value()
    local request = state.text
    ---@type string
    local model

    local builtins_provider_config = Config[Config.provider]
    if builtins_provider_config ~= nil then
      model = builtins_provider_config.model
    else
      local vendor_provider_config = Config.vendors[Config.provider]
      model = vendor_provider_config and vendor_provider_config.model or "default"
    end

    local timestamp = get_timestamp()

    local content_prefix = get_chat_record_prefix(timestamp, Config.provider, model, request)

    --- HACK: we need to set focus to true and scroll to false to
    --- prevent the cursor from jumping to the bottom of the
    --- buffer at the beginning
    self:update_content("", { focus = true, scroll = false })
    self:update_content(content_prefix .. "🔄 **Generating response ...**\n")

    local content = self:get_code_content()
    local content_with_line_numbers = prepend_line_number(content)

    local selected_code_content_with_line_numbers = nil
    if self.code.selection ~= nil then
      selected_code_content_with_line_numbers =
        prepend_line_number(self.code.selection.content, self.code.selection.range.start.line)
    end

    local full_response = ""

    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.buf })

    local is_first_chunk = true

    ---@type AvanteChunkParser
    local on_chunk = function(chunk)
      local append_chunk = function()
        signal.is_loading = true
        full_response = full_response .. chunk
        self:update_content(chunk, { stream = true, scroll = true })
        vim.schedule(function()
          vim.cmd("redraw")
        end)
      end

      if is_first_chunk then
        is_first_chunk = false
        self:update_content(content_prefix, {
          scroll = true,
          callback = function()
            vim.schedule(function()
              vim.cmd("redraw")
              append_chunk()
            end)
          end,
        })
      else
        append_chunk()
      end
    end

    ---@type AvanteCompleteParser
    local on_complete = function(err)
      signal.is_loading = false

      if err ~= nil then
        self:update_content("\n\n🚨 Error: " .. vim.inspect(err), { stream = true, scroll = true })
        return
      end

      -- Execute when the stream request is actually completed
      self:update_content("\n\n🎉🎉🎉 **Generation complete!** Please review the code suggestions above.\n\n", {
        stream = true,
        scroll = true,
        callback = function()
          api.nvim_exec_autocmds("User", { pattern = VIEW_BUFFER_UPDATED_PATTERN })
        end,
      })

      -- Save chat history
      table.insert(chat_history or {}, {
        timestamp = timestamp,
        provider = Config.provider,
        model = model,
        request = request,
        response = full_response,
      })
      save_chat_history(self, chat_history)
    end

    Llm.stream(
      request,
      filetype,
      content_with_line_numbers,
      selected_code_content_with_line_numbers,
      on_chunk,
      on_complete
    )

    if Config.behaviour.auto_apply_diff_after_generation then
      apply()
    end
  end

  local body = function()
    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.buf })
    local icon = require("nvim-web-devicons").get_icon_by_filetype(filetype, {})
    local code_file_fullpath = api.nvim_buf_get_name(self.code.buf)
    local code_filename = fn.fnamemodify(code_file_fullpath, ":t")

    local input_label = string.format(" 🙋 with %s %s (<Tab>: switch focus): ", icon, code_filename)

    if self.code.selection ~= nil then
      input_label = string.format(
        " 🙋 with %s %s(%d:%d) (<Tab>: switch focus): ",
        icon,
        code_filename,
        self.code.selection.range.start.line,
        self.code.selection.range.finish.line
      )
    end

    local selected_code_lines_count = 0
    local selected_code_max_lines_count = 10

    local selected_code_size = 0

    if self.code.selection ~= nil then
      local selected_code_lines = vim.split(self.code.selection.content, "\n")
      selected_code_lines_count = #selected_code_lines
      selected_code_size = math.min(selected_code_lines_count, selected_code_max_lines_count) + 4
    end

    return N.rows(
      { flex = 0 },
      N.box(
        {
          direction = "column",
          size = vim.o.lines - 4 - selected_code_size,
        },
        N.buffer({
          id = "result",
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
      N.paragraph({
        hidden = self.code.selection == nil,
        id = "selected_code",
        lines = self.code.selection and self.code.selection.content or "",
        border_label = {
          text = "💻 Selected Code"
            .. (
              selected_code_lines_count > selected_code_max_lines_count
                and " (Show only the first " .. tostring(selected_code_max_lines_count) .. " lines)"
              or ""
            ),
          align = "center",
        },
        align = "left",
        is_focusable = false,
        max_lines = selected_code_max_lines_count,
        padding = {
          top = 1,
          bottom = 1,
          left = 1,
          right = 1,
        },
      }),
      N.gap(1),
      N.text_input({
        id = "input",
        border_label = {
          text = input_label,
        },
        placeholder = "Enter your question",
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
      })
    )
  end

  self.renderer:render(body)
  return self
end

return Sidebar
