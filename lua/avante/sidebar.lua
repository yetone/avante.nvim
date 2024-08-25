local api = vim.api
local fn = vim.fn

local Path = require("plenary.path")
local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local Config = require("avante.config")
local Diff = require("avante.diff")
local Llm = require("avante.llm")
local Utils = require("avante.utils")
local Highlights = require("avante.highlights")
local FloatingWindow = require("avante.floating_window")

local RESULT_BUF_NAME = "AVANTE_RESULT"
local VIEW_BUFFER_UPDATED_PATTERN = "AvanteViewBufferUpdated"
local CODEBLOCK_KEYBINDING_NAMESPACE = api.nvim_create_namespace("AVANTE_CODEBLOCK_KEYBINDING")
local PRIORITY = vim.highlight.priorities.user

---@class avante.Sidebar
local Sidebar = {}

---@class avante.CodeState
---@field winid integer
---@field bufnr integer
---@field selection avante.SelectionResult | nil

---@class avante.Sidebar
---@field id integer
---@field registered_cmp boolean
---@field augroup integer
---@field code avante.CodeState
---@field winids table<string, integer> this table stores the winids of the sidebar components (result_container, result, selected_code_container, selected_code, input_container, input), even though they are destroyed.
---@field result_container NuiSplit | nil
---@field result FloatingWindow | nil
---@field selected_code_container NuiSplit | nil
---@field selected_code FloatingWindow | nil
---@field input_container NuiSplit | nil
---@field input FloatingWindow | nil

---@param id integer the tabpage id retrieved from api.nvim_get_current_tabpage()
function Sidebar:new(id)
  return setmetatable({
    id = id,
    registered_cmp = false,
    code = { bufnr = 0, winid = 0, selection = nil },
    winids = {
      result_container = 0,
      result = 0,
      selected_code_container = 0,
      selected_code = 0,
      input = 0,
    },
    result = nil,
    selected_code_container = nil,
    selected_code = nil,
    input_container = nil,
    input = nil,
  }, { __index = self })
end

function Sidebar:delete_autocmds()
  if self.augroup then
    api.nvim_del_augroup_by_id(self.augroup)
  end
  self.augroup = nil
end

function Sidebar:reset()
  self:delete_autocmds()
  self.code = { bufnr = 0, winid = 0, selection = nil }
  self.winids = { result_container = 0, result = 0, selected_code = 0, input = 0 }
  self.result_container = nil
  self.result = nil
  self.selected_code_container = nil
  self.selected_code = nil
  self.input_container = nil
  self.input = nil
end

function Sidebar:open()
  local in_visual_mode = Utils.in_visual_mode() and self:in_code_win()
  if not self:is_open() then
    self:reset()
    self:initialize()
    self:render()
  else
    if in_visual_mode then
      self:close()
      self:reset()
      self:initialize()
      self:render()
      return self
    end
    self:focus()
  end

  vim.cmd("wincmd =")
  return self
end

function Sidebar:close()
  self:delete_autocmds()
  for _, comp in pairs(self) do
    if comp and type(comp) == "table" and comp.unmount then
      comp:unmount()
    end
  end
  if self.code ~= nil and api.nvim_win_is_valid(self.code.winid) then
    fn.win_gotoid(self.code.winid)
  end

  vim.cmd("wincmd =")
end

---@return boolean
function Sidebar:focus()
  if self:is_open() then
    fn.win_gotoid(self.result.winid)
    return true
  end
  return false
end

function Sidebar:is_open()
  return self.result
    and self.result.bufnr
    and api.nvim_buf_is_valid(self.result.bufnr)
    and self.result.winid
    and api.nvim_win_is_valid(self.result.winid)
end

function Sidebar:in_code_win()
  return self.code.winid == api.nvim_get_current_win()
end

function Sidebar:toggle()
  local in_visual_mode = Utils.in_visual_mode() and self:in_code_win()
  if self:is_open() and not in_visual_mode then
    self:close()
    return false
  else
    self:open()
    return true
  end
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

---@param codeblocks table<integer, any>
local function is_cursor_in_codeblock(codeblocks)
  local cursor_line, _ = Utils.get_cursor_pos()
  cursor_line = cursor_line - 1 -- 转换为 0-indexed 行号

  for _, block in ipairs(codeblocks) do
    if cursor_line >= block.start_line and cursor_line <= block.end_line then
      return block
    end
  end

  return nil
end

---@class AvanteCodeblock
---@field start_line integer
---@field end_line integer
---@field lang string

---@param buf integer
---@return AvanteCodeblock[]
local function parse_codeblocks(buf)
  local codeblocks = {}
  local in_codeblock = false
  local start_line = nil
  local lang = nil

  local lines = Utils.get_buf_lines(0, -1, buf)
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

function Sidebar:apply()
  local content = table.concat(Utils.get_buf_lines(0, -1, self.code.bufnr), "\n")
  local response = self:get_content_between_separators()
  local snippets = extract_code_snippets(response)
  local conflict_content = get_conflict_content(content, snippets)

  vim.defer_fn(function()
    api.nvim_buf_set_lines(self.code.bufnr, 0, -1, false, conflict_content)

    api.nvim_set_current_win(self.code.winid)
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
    Diff.add_visited_buffer(self.code.bufnr)
    Diff.process(self.code.bufnr)
    api.nvim_win_set_cursor(self.code.winid, { 1, 0 })
    vim.defer_fn(function()
      vim.cmd("AvanteConflictNextConflict")
      vim.cmd("normal! zz")
    end, 1000)
  end, 10)
end

local buf_options = {
  modifiable = false,
  swapfile = false,
  buftype = "nofile",
}

local base_win_options = {
  spell = false,
  signcolumn = "no",
  foldcolumn = "0",
  number = false,
  relativenumber = false,
  winfixwidth = true,
  list = false,
  winhl = "",
  linebreak = true,
  breakindent = true,
  wrap = false,
  cursorline = false,
  -- winhighlight = "Normal:NormalFloat,Border:FloatBorder,VertSplit:NormalFloat,WinSeparator:NormalFloat,CursorLine:NormalFloat",
  fillchars = "eob: ",
  winhighlight = "CursorLine:Normal,CursorColumn:Normal",
  winbar = "",
  statusline = "",
}

local function get_win_options()
  -- return vim.tbl_deep_extend("force", base_win_options, {
  --   fillchars = "eob: ,vert: ,horiz: ,horizup: ,horizdown: ,vertleft: ,vertright:" .. (code_vert_char ~= nil and code_vert_char or " ") .. ",verthoriz: ",
  -- })
  return base_win_options
end

function Sidebar:render_header(winid, bufnr, header_text, hl, reverse_hl)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  local reversed_hl_off = 0
  if Config.windows.sidebar_header.rounded then
    reversed_hl_off = 1
    header_text = "" .. header_text .. ""
  else
    header_text = " " .. header_text .. " "
  end

  local width = api.nvim_win_get_width(winid)
  local header_text_length = vim.fn.strdisplaywidth(header_text)
  local prefix_padding, suffix_padding = 0, 0

  if Config.windows.sidebar_header.align == "center" then
    prefix_padding = math.floor((width - header_text_length) / 2)
    suffix_padding = width - header_text_length - prefix_padding
  elseif Config.windows.sidebar_header.align == "right" then
    prefix_padding = width - header_text_length
    suffix_padding = 0
  elseif Config.windows.sidebar_header.align == "left" then
    suffix_padding = width - header_text_length
    prefix_padding = 0
  end

  local prefix_padding_text = string.rep(" ", prefix_padding)
  local suffix_padding_text = string.rep(" ", suffix_padding)
  Utils.unlock_buf(bufnr)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, { prefix_padding_text .. header_text .. suffix_padding_text })
  api.nvim_buf_add_highlight(bufnr, -1, "WinSeparator", 0, 0, #prefix_padding_text - reversed_hl_off)
  api.nvim_buf_add_highlight(bufnr, -1, reverse_hl, 0, #prefix_padding_text, #prefix_padding_text + reversed_hl_off)
  api.nvim_buf_add_highlight(
    bufnr,
    -1,
    hl,
    0,
    #prefix_padding_text + reversed_hl_off,
    #prefix_padding_text + #header_text - reversed_hl_off * 3
  )
  api.nvim_buf_add_highlight(
    bufnr,
    -1,
    reverse_hl,
    0,
    #prefix_padding_text + #header_text - reversed_hl_off * 3,
    #prefix_padding_text + #header_text - reversed_hl_off * 2
  )
  api.nvim_buf_add_highlight(bufnr, -1, "WinSeparator", 0, #prefix_padding_text + #header_text - reversed_hl_off, -1)
  Utils.lock_buf(bufnr)
end

function Sidebar:render_result_container()
  if
    not self.result_container
    or not self.result_container.bufnr
    or not api.nvim_buf_is_valid(self.result_container.bufnr)
  then
    return
  end
  local header_text = "󰭻 Avante"
  self:render_header(
    self.result_container.winid,
    self.result_container.bufnr,
    header_text,
    Highlights.TITLE,
    Highlights.REVERSED_TITLE
  )
end

function Sidebar:render_input_container()
  if
    not self.input_container
    or not self.input_container.bufnr
    or not api.nvim_buf_is_valid(self.input_container.bufnr)
  then
    return
  end

  local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })
  local code_file_fullpath = api.nvim_buf_get_name(self.code.bufnr)
  local icon = require("nvim-web-devicons").get_icon_by_filetype(filetype, {})
  local code_filename = fn.fnamemodify(code_file_fullpath, ":t")
  local header_text = string.format("󱜸 Chat with %s %s (<Tab>: switch focus)", icon, code_filename)

  if self.code.selection ~= nil then
    header_text = string.format(
      "󱜸 Chat with %s %s(%d:%d) (<Tab>: switch focus)",
      icon,
      code_filename,
      self.code.selection.range.start.line,
      self.code.selection.range.finish.line
    )
  end

  self:render_header(
    self.input_container.winid,
    self.input_container.bufnr,
    header_text,
    Highlights.THIRD_TITLE,
    Highlights.REVERSED_THIRD_TITLE
  )
end

function Sidebar:render_selected_code_container()
  if
    not self.selected_code_container
    or not self.selected_code_container.bufnr
    or not api.nvim_buf_is_valid(self.selected_code_container.bufnr)
  then
    return
  end

  local selected_code_lines_count = 0
  local selected_code_max_lines_count = 10

  if self.code.selection ~= nil then
    local selected_code_lines = vim.split(self.code.selection.content, "\n")
    selected_code_lines_count = #selected_code_lines
  end

  local header_text = " Selected Code"
    .. (
      selected_code_lines_count > selected_code_max_lines_count
        and " (Show only the first " .. tostring(selected_code_max_lines_count) .. " lines)"
      or ""
    )

  self:render_header(
    self.selected_code_container.winid,
    self.selected_code_container.bufnr,
    header_text,
    Highlights.SUBTITLE,
    Highlights.REVERSED_SUBTITLE
  )
end

function Sidebar:on_mount()
  self:refresh_winids()

  api.nvim_set_option_value("wrap", Config.windows.wrap, { win = self.result.winid })

  local current_apply_extmark_id = nil

  local function show_apply_button(block)
    if current_apply_extmark_id then
      api.nvim_buf_del_extmark(self.result.bufnr, CODEBLOCK_KEYBINDING_NAMESPACE, current_apply_extmark_id)
    end

    current_apply_extmark_id =
      api.nvim_buf_set_extmark(self.result.bufnr, CODEBLOCK_KEYBINDING_NAMESPACE, block.start_line, -1, {
        virt_text = { { " [Press <A> to Apply these patches] ", "Keyword" } },
        virt_text_pos = "right_align",
        hl_group = "Keyword",
        priority = PRIORITY,
      })
  end

  local function bind_apply_key()
    vim.keymap.set("n", "A", function()
      self:apply()
    end, { buffer = self.result.bufnr, noremap = true, silent = true })
  end

  local function unbind_apply_key()
    pcall(vim.keymap.del, "n", "A", { buffer = self.result.bufnr })
  end

  ---@type AvanteCodeblock[]
  local codeblocks = {}

  ---@param direction "next" | "prev"
  local function jump_to_codeblock(direction)
    local cursor_line = api.nvim_win_get_cursor(self.result.winid)[1]
    ---@type AvanteCodeblock
    local target_block

    if direction == "next" then
      for _, block in ipairs(codeblocks) do
        if block.start_line > cursor_line then
          target_block = block
          break
        end
      end
      if not target_block and #codeblocks > 0 then
        target_block = codeblocks[1]
      end
    elseif direction == "prev" then
      for i = #codeblocks, 1, -1 do
        if codeblocks[i].end_line < cursor_line then
          target_block = codeblocks[i]
          break
        end
      end
      if not target_block and #codeblocks > 0 then
        target_block = codeblocks[#codeblocks]
      end
    end

    if target_block then
      api.nvim_win_set_cursor(self.result.winid, { target_block.start_line + 1, 0 })
    end
  end

  local function bind_jump_keys()
    vim.keymap.set("n", Config.mappings.jump.next, function()
      jump_to_codeblock("next")
    end, { buffer = self.result.bufnr, noremap = true, silent = true })
    vim.keymap.set("n", Config.mappings.jump.prev, function()
      jump_to_codeblock("prev")
    end, { buffer = self.result.bufnr, noremap = true, silent = true })
  end

  local function unbind_jump_keys()
    if self.result and self.result.bufnr and api.nvim_buf_is_valid(self.result.bufnr) then
      pcall(vim.keymap.del, "n", Config.mappings.jump.next, { buffer = self.result.bufnr })
      pcall(vim.keymap.del, "n", Config.mappings.jump.prev, { buffer = self.result.bufnr })
    end
  end

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = self.result.bufnr,
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
    buffer = self.result.bufnr,
    callback = function(ev)
      codeblocks = parse_codeblocks(ev.buf)
      bind_jump_keys()
    end,
  })

  api.nvim_create_autocmd("User", {
    pattern = VIEW_BUFFER_UPDATED_PATTERN,
    callback = function()
      if self.result == nil then
        return
      end
      codeblocks = parse_codeblocks(self.result.bufnr)
      bind_jump_keys()
    end,
  })

  api.nvim_create_autocmd("BufLeave", {
    buffer = self.result.bufnr,
    callback = function()
      unbind_jump_keys()
    end,
  })

  self:render_result_container()
  self:render_input_container()
  self:render_selected_code_container()

  self.augroup = api.nvim_create_augroup("avante_" .. self.id .. self.result.winid, { clear = true })

  local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })

  if self.selected_code ~= nil then
    local selected_code_buf = self.selected_code.bufnr
    if selected_code_buf ~= nil then
      if self.code.selection ~= nil then
        Utils.unlock_buf(selected_code_buf)
        local lines = vim.split(self.code.selection.content, "\n")
        api.nvim_buf_set_lines(selected_code_buf, 0, -1, false, lines)
        Utils.lock_buf(selected_code_buf)
      end
      api.nvim_set_option_value("filetype", filetype, { buf = selected_code_buf })
    end
  end

  api.nvim_create_autocmd("BufEnter", {
    group = self.augroup,
    buffer = self.result.bufnr,
    callback = function()
      if self.input and self.input.winid and api.nvim_win_is_valid(self.input.winid) then
        api.nvim_set_current_win(self.input.winid)
      end
      return true
    end,
  })

  api.nvim_create_autocmd("VimResized", {
    group = self.augroup,
    callback = function()
      if not self:is_open() then
        return
      end
      self:resize()
    end,
  })

  api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    callback = function(args)
      local closed_winid = tonumber(args.match)
      if not self:is_focused_on(closed_winid) then
        return
      end
      self:close()
    end,
  })

  local previous_winid = nil

  api.nvim_create_autocmd("WinLeave", {
    group = self.augroup,
    callback = function()
      previous_winid = api.nvim_get_current_win()
    end,
  })

  api.nvim_create_autocmd("WinEnter", {
    group = self.augroup,
    callback = function()
      local current_win_id = api.nvim_get_current_win()

      if not self.result_container or current_win_id ~= self.result_container.winid then
        return
      end

      if previous_winid == self.result.winid and self.input.winid and api.nvim_win_is_valid(self.input.winid) then
        api.nvim_set_current_win(self.input.winid)
        return
      end

      if self.result and self.result.winid and api.nvim_win_is_valid(self.result.winid) then
        api.nvim_set_current_win(self.result.winid)
        return
      end
    end,
  })

  api.nvim_create_autocmd("WinEnter", {
    group = self.augroup,
    callback = function()
      local current_win_id = api.nvim_get_current_win()

      if not self.input_container or current_win_id ~= self.input_container.winid then
        return
      end

      if previous_winid == self.input.winid then
        if self.selected_code and self.selected_code.winid and api.nvim_win_is_valid(self.selected_code.winid) then
          api.nvim_set_current_win(self.selected_code.winid)
          return
        end
        if self.result and self.result.winid and api.nvim_win_is_valid(self.result.winid) then
          api.nvim_set_current_win(self.result.winid)
          return
        end
      end

      if self.input and self.input.winid and api.nvim_win_is_valid(self.input.winid) then
        api.nvim_set_current_win(self.input.winid)
        return
      end
    end,
  })

  api.nvim_create_autocmd("WinEnter", {
    group = self.augroup,
    callback = function()
      local current_win_id = api.nvim_get_current_win()

      if not self.selected_code_container or current_win_id ~= self.selected_code_container.winid then
        return
      end

      if
        previous_winid == self.result.winid
        and self.selected_code
        and self.selected_code.winid
        and api.nvim_win_is_valid(self.selected_code.winid)
      then
        api.nvim_set_current_win(self.selected_code.winid)
        return
      end

      if self.result and self.result.winid and api.nvim_win_is_valid(self.result.winid) then
        api.nvim_set_current_win(self.result.winid)
        return
      end
    end,
  })

  for _, comp in pairs(self) do
    if comp and type(comp) == "table" and comp.mount and comp.bufnr and api.nvim_buf_is_valid(comp.bufnr) then
      Utils.mark_as_sidebar_buffer(comp.bufnr)
    end
  end
end

function Sidebar:refresh_winids()
  self.winids = {}
  for key, comp in pairs(self) do
    if comp and type(comp) == "table" and comp.winid and api.nvim_win_is_valid(comp.winid) then
      self.winids[key] = comp.winid
    end
  end

  local winids = {}
  if self.winids.result then
    table.insert(winids, self.winids.result)
  end
  if self.winids.selected_code then
    table.insert(winids, self.winids.selected_code)
  end
  if self.winids.input then
    table.insert(winids, self.winids.input)
  end

  local function switch_windows()
    local current_winid = api.nvim_get_current_win()
    local current_idx = Utils.tbl_indexof(winids, current_winid) or 1
    if current_idx == #winids then
      current_idx = 1
    else
      current_idx = current_idx + 1
    end
    if api.nvim_win_is_valid(winids[current_idx]) then
      api.nvim_set_current_win(winids[current_idx])
    end
  end

  local function reverse_switch_windows()
    local current_winid = api.nvim_get_current_win()
    local current_idx = Utils.tbl_indexof(winids, current_winid) or 1
    if current_idx == 1 then
      current_idx = #winids
    else
      current_idx = current_idx - 1
    end
    if api.nvim_win_is_valid(winids[current_idx]) then
      api.nvim_set_current_win(winids[current_idx])
    end
  end

  for _, winid in ipairs(winids) do
    local buf = api.nvim_win_get_buf(winid)
    vim.keymap.set({ "n", "i" }, "<Tab>", function()
      switch_windows()
    end, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set({ "n", "i" }, "<S-Tab>", function()
      reverse_switch_windows()
    end, { buffer = buf, noremap = true, silent = true })
  end
end

function Sidebar:resize()
  local new_layout = Config.get_sidebar_layout_options()
  for _, comp in pairs(self) do
    if comp and type(comp) == "table" and comp.winid and api.nvim_win_is_valid(comp.winid) then
      api.nvim_win_set_width(comp.winid, new_layout.width)
    end
  end
  self:render_result_container()
  self:render_input_container()
  self:render_selected_code_container()
  vim.defer_fn(function()
    vim.cmd("AvanteRefresh")
  end, 200)
end

--- Initialize the sidebar instance.
--- @return avante.Sidebar The Sidebar instance.
function Sidebar:initialize()
  self.code.winid = api.nvim_get_current_win()
  self.code.bufnr = api.nvim_get_current_buf()
  self.code.selection = Utils.get_visual_selection_and_range()

  return self
end

function Sidebar:is_focused_on_result()
  return self:is_open() and self.result and self.result.winid == api.nvim_get_current_win()
end

function Sidebar:is_focused_on(winid)
  for _, stored_winid in pairs(self.winids) do
    if stored_winid == winid then
      return true
    end
  end
  return false
end

---@param content string concatenated content of the buffer
---@param opts? {focus?: boolean, stream?: boolean, scroll?: boolean, callback?: fun(): nil} whether to focus the result view
function Sidebar:update_content(content, opts)
  if not self.result or not self.result.bufnr or not api.nvim_buf_is_valid(self.result.bufnr) then
    return
  end
  opts = vim.tbl_deep_extend("force", { focus = true, scroll = true, stream = false, callback = nil }, opts or {})
  if opts.stream then
    local scroll_to_bottom = function()
      local last_line = api.nvim_buf_line_count(self.result.bufnr)

      local current_lines = Utils.get_buf_lines(last_line - 1, last_line, self.result.bufnr)

      if #current_lines > 0 then
        local last_line_content = current_lines[1]
        local last_col = #last_line_content
        xpcall(function()
          api.nvim_win_set_cursor(self.result.winid, { last_line, last_col })
        end, function(err)
          return err
        end)
      end
    end

    vim.schedule(function()
      if not self.result.bufnr or not api.nvim_buf_is_valid(self.result.bufnr) then
        return
      end
      scroll_to_bottom()
      local lines = vim.split(content, "\n")
      Utils.unlock_buf(self.result.bufnr)
      api.nvim_buf_call(self.result.bufnr, function()
        api.nvim_put(lines, "c", true, true)
      end)
      Utils.lock_buf(self.result.bufnr)
      api.nvim_set_option_value("filetype", "Avante", { buf = self.result.bufnr })
      if opts.scroll then
        scroll_to_bottom()
      end
      if opts.callback ~= nil then
        opts.callback()
      end
    end)
  else
    vim.defer_fn(function()
      if not self.result.bufnr or not api.nvim_buf_is_valid(self.result.bufnr) then
        return
      end
      local lines = vim.split(content, "\n")
      Utils.unlock_buf(self.result.bufnr)
      api.nvim_buf_set_lines(self.result.bufnr, 0, -1, false, lines)
      Utils.lock_buf(self.result.bufnr)
      api.nvim_set_option_value("filetype", "Avante", { buf = self.result.bufnr })
      if opts.focus and not self:is_focused_on_result() then
        xpcall(function()
          --- set cursor to bottom of result view
          api.nvim_set_current_win(self.result.winid)
        end, function(err)
          return err
        end)
      end

      if opts.scroll then
        Utils.buf_scroll_to_end(self.result.bufnr)
      end

      if opts.callback ~= nil then
        opts.callback()
      end
    end, 0)
  end
  return self
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

-- Function to get the current project root directory
local function get_project_root()
  local current_file = fn.expand("%:p")
  local current_dir = fn.fnamemodify(current_file, ":h")
  local git_root = vim.fs.root(current_file, { ".git" })
  return git_root ~= nil and git_root or current_dir
end

---@param sidebar avante.Sidebar
local function get_chat_history_filename(sidebar)
  local code_buf_name = api.nvim_buf_get_name(sidebar.code.bufnr)
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
  for idx, entry in ipairs(history) do
    local prefix =
      get_chat_record_prefix(entry.timestamp, entry.provider, entry.model, entry.request or entry.requirement or "")
    content = content .. prefix
    content = content .. entry.response .. "\n\n"
    if idx < #history then
      content = content .. "---\n\n"
    end
  end
  self:update_content(content)
end

---@return string
function Sidebar:get_content_between_separators()
  local separator = "---"
  local cursor_line, _ = Utils.get_cursor_pos()
  local lines = Utils.get_buf_lines(0, -1, self.result.bufnr)
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

function Sidebar:get_commands()
  local function get_help_text(items_)
    local help_text = ""
    for _, item in ipairs(items_) do
      help_text = help_text .. "- " .. item.name .. ": " .. item.description .. "\n"
    end
    return help_text
  end

  local items = {
    { name = "help", description = "Show this help message", command = "help" },
    { name = "clear", description = "Clear chat history", command = "clear" },
    { name = "lines <start>-<end> <question>", description = "Ask a question about specific lines", command = "lines" },
  }

  local cbs = {
    {
      command = "help",
      ---@diagnostic disable-next-line: unused-local
      callback = function(args, cb)
        local help_text = get_help_text(items)
        self:update_content(help_text, { focus = false, scroll = false })
        if cb then
          cb(args)
        end
      end,
    },
    {
      command = "clear",
      ---@diagnostic disable-next-line: unused-local
      callback = function(args, cb)
        local chat_history = {}
        save_chat_history(self, chat_history)
        self:update_content("Chat history cleared", { focus = false, scroll = false })
        vim.defer_fn(function()
          self:close()
          if cb then
            cb(args)
          end
        end, 1000)
      end,
    },
    {
      command = "lines",
      callback = function(args, cb)
        if cb then
          cb(args)
        end
      end,
    },
  }

  local commands = {}
  for _, item in ipairs(items) do
    table.insert(commands, {
      name = item.name,
      command = item.command,
      description = item.description,
      callback = function(args, cb)
        for _, cb_ in ipairs(cbs) do
          if cb_.command == item.command then
            cb_.callback(args, cb)
            break
          end
        end
      end,
    })
  end
  return commands
end

function Sidebar:create_selected_code()
  if self.selected_code ~= nil then
    self.selected_code:unmount()
    self.selected_code = nil
  end
  if self.selected_code_container ~= nil then
    self.selected_code_container:unmount()
    self.selected_code_container = nil
  end

  local selected_code_size = self:get_selected_code_size()

  if self.code.selection ~= nil then
    self.selected_code_container = Split({
      enter = false,
      relative = {
        type = "win",
        winid = self.result_container.winid,
      },
      buf_options = buf_options,
      win_options = get_win_options(),
      position = "bottom",
      size = {
        height = selected_code_size + 3,
      },
    })
    self.selected_code_container:mount()
    self.selected_code = self:create_floating_window_for_split({ split_winid = self.selected_code_container.winid })
    self.selected_code:mount()
  end
end

function Sidebar:create_input()
  if
    not self.input_container
    or not self.input_container.winid
    or not api.nvim_win_is_valid(self.input_container.winid)
  then
    return
  end

  if self.input ~= nil then
    self.input:unmount()
  end

  local chat_history = load_chat_history(self)

  ---@param request string
  local function handle_submit(request)
    local model = Config.has_provider(Config.provider) and Config.get_provider(Config.provider).model or "default"

    local timestamp = get_timestamp()

    local content_prefix = get_chat_record_prefix(timestamp, Config.provider, model, request)

    --- HACK: we need to set focus to true and scroll to false to
    --- prevent the cursor from jumping to the bottom of the
    --- buffer at the beginning
    self:update_content("", { focus = true, scroll = false })
    self:update_content(content_prefix .. "🔄 **Generating response ...**\n")

    local content = table.concat(Utils.get_buf_lines(0, -1, self.code.bufnr), "\n")
    local content_with_line_numbers = prepend_line_number(content)

    local selected_code_content_with_line_numbers = nil
    if self.code.selection ~= nil then
      selected_code_content_with_line_numbers =
        prepend_line_number(self.code.selection.content, self.code.selection.range.start.line)
    end

    if request:sub(1, 1) == "/" then
      local command, args = request:match("^/(%S+)%s*(.*)")
      if command == nil then
        self:update_content("Invalid command", { focus = false, scroll = false })
        return
      end
      local cmds = self:get_commands()
      local cmd
      for _, c in ipairs(cmds) do
        if c.command == command then
          cmd = c
          break
        end
      end
      if cmd then
        if command == "lines" then
          cmd.callback(args, function(args_)
            local start_line, end_line, question = args_:match("(%d+)-(%d+)%s+(.*)")
            ---@cast start_line integer
            start_line = tonumber(start_line)
            ---@cast end_line integer
            end_line = tonumber(end_line)
            if end_line == nil then
              Utils.error("Invalid end line number", { once = true, title = "Avante" })
              return
            end
            selected_code_content_with_line_numbers = prepend_line_number(
              table.concat(api.nvim_buf_get_lines(self.code.bufnr, start_line - 1, end_line, false), "\n"),
              start_line
            )
            request = question
          end)
        else
          cmd.callback(args)
          return
        end
      else
        self:update_content("Unknown command: " .. command, { focus = false, scroll = false })
        return
      end
    end

    local full_response = ""

    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })

    local is_first_chunk = true

    ---@type AvanteChunkParser
    local on_chunk = function(chunk)
      full_response = full_response .. chunk
      if is_first_chunk then
        is_first_chunk = false
        self:update_content(content_prefix .. chunk, { stream = false, scroll = true })
        return
      end
      self:update_content(chunk, { stream = true, scroll = true })
      vim.schedule(function()
        vim.cmd("redraw")
      end)
    end

    ---@type AvanteCompleteParser
    local on_complete = function(err)
      if err ~= nil then
        self:update_content("\n\n🚨 Error: " .. vim.inspect(err), { stream = true, scroll = true })
        return
      end

      -- Execute when the stream request is actually completed
      self:update_content("\n\n🎉🎉🎉 **Generation complete!** Please review the code suggestions above.", {
        stream = true,
        scroll = true,
        callback = function()
          api.nvim_exec_autocmds("User", { pattern = VIEW_BUFFER_UPDATED_PATTERN })
        end,
      })

      vim.defer_fn(function()
        if self.result and self.result.winid and api.nvim_win_is_valid(self.result.winid) then
          api.nvim_set_current_win(self.result.winid)
        end
      end, 0)

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
      self:apply()
    end
  end

  if
    not self.input_container
    or not self.input_container.winid
    or not api.nvim_win_is_valid(self.input_container.winid)
  then
    return
  end

  self.input = self:create_floating_window_for_split({
    split_winid = self.input_container.winid,
    buf_opts = {
      modifiable = true,
    },
    keep_floating_style = true,
  })

  self.input:on_mount(function()
    api.nvim_win_set_hl_ns(self.input.winid, Highlights.input_ns)
  end)

  local function on_submit()
    local lines = api.nvim_buf_get_lines(self.input.bufnr, 0, -1, false)
    local request = table.concat(lines, "\n")
    if request == "" then
      return
    end
    api.nvim_buf_set_lines(self.input.bufnr, 0, -1, false, {})
    handle_submit(request)
  end

  self.input:map("n", Config.mappings.submit.normal, on_submit)
  self.input:map("i", Config.mappings.submit.insert, on_submit)

  self.input:mount()

  api.nvim_set_option_value("filetype", "AvanteInput", { buf = self.input.bufnr })

  -- Setup completion
  api.nvim_create_autocmd("InsertEnter", {
    group = self.augroup,
    buffer = self.input.bufnr,
    once = true,
    desc = "Setup the completion of helpers in the input buffer",
    callback = function()
      local has_cmp, cmp = pcall(require, "cmp")
      if has_cmp then
        if not self.registered_cmp then
          self.registered_cmp = true
          cmp.register_source("avante_commands", require("cmp_avante.commands").new(self))
        end
        cmp.setup.buffer({
          enabled = true,
          sources = {
            { name = "avante_commands" },
          },
        })
      end
    end,
  })

  local hint_window = nil

  -- Close the floating window
  local function close_hint()
    if hint_window and api.nvim_win_is_valid(hint_window) then
      api.nvim_win_close(hint_window, true)
      hint_window = nil
    end
  end

  -- Create a floating window as a hint
  local function show_hint()
    close_hint() -- Close the existing hint window

    local hint_text = "Press " .. Config.mappings.submit.insert .. " to submit"
    if vim.fn.mode() ~= "i" then
      hint_text = "Press " .. Config.mappings.submit.normal .. " to submit"
    end

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, { hint_text })

    -- Get the current window size
    local win_width = api.nvim_win_get_width(self.input.winid)
    local width = #hint_text + 2

    -- Set the floating window options
    local opts = {
      relative = "win",
      win = self.input.winid,
      width = width,
      height = 1,
      row = -1,
      col = math.max(win_width - width, 0), -- Display in the top right corner
      style = "minimal",
      border = "none",
      focusable = false,
      zindex = 100,
    }

    -- Create the floating window
    hint_window = api.nvim_open_win(buf, false, opts)

    api.nvim_win_set_hl_ns(hint_window, Highlights.hint_ns)
  end

  self.input:on(event.InsertEnter, show_hint)

  self.input:on_unmount(function()
    close_hint()
  end)

  -- Show hint in insert mode
  api.nvim_create_autocmd("ModeChanged", {
    group = self.augroup,
    pattern = "*:i",
    callback = function()
      local cur_buf = api.nvim_get_current_buf()
      if self.input and cur_buf == self.input.bufnr then
        show_hint()
      end
    end,
  })

  -- Close hint when exiting insert mode
  api.nvim_create_autocmd("ModeChanged", {
    group = self.augroup,
    pattern = "i:*",
    callback = function()
      local cur_buf = api.nvim_get_current_buf()
      if self.input and cur_buf == self.input.bufnr then
        show_hint()
      end
    end,
  })

  api.nvim_create_autocmd("WinEnter", {
    callback = function()
      local cur_win = api.nvim_get_current_win()
      if self.input and cur_win == self.input.winid then
        show_hint()
      else
        close_hint()
      end
    end,
  })

  self:refresh_winids()
end

function Sidebar:get_selected_code_size()
  local selected_code_lines_count = 0
  local selected_code_max_lines_count = 10

  local selected_code_size = 0

  if self.code.selection ~= nil then
    local selected_code_lines = vim.split(self.code.selection.content, "\n")
    selected_code_lines_count = #selected_code_lines
    selected_code_size = math.min(selected_code_lines_count, selected_code_max_lines_count)
  end

  return selected_code_size
end

---@class CreateFloatingWindowForSplitOptions
---@field split_winid integer | nil
---@field buf_opts table | nil
---@field win_opts table | nil
---@field float_opts table | nil
---@field keep_floating_style boolean | nil

---@param opts CreateFloatingWindowForSplitOptions
function Sidebar:create_floating_window_for_split(opts)
  local win_opts_ = vim.tbl_deep_extend("force", get_win_options(), opts.win_opts or {})

  local buf_opts_ = vim.tbl_deep_extend("force", buf_options, opts.buf_opts or {})

  local floating_win = FloatingWindow.from_split_win(opts.split_winid, {
    buf_options = buf_opts_,
    win_options = win_opts_,
    float_options = opts.float_opts,
  })

  return floating_win
end

function Sidebar:render()
  local chat_history = load_chat_history(self)

  local sidebar_height = api.nvim_win_get_height(self.code.winid)
  local selected_code_size = self:get_selected_code_size()

  self.result_container = Split({
    relative = "editor",
    position = "right",
    buf_options = buf_options,
    win_options = get_win_options(),
    size = {
      width = string.format("%d%%", Config.windows.width),
    },
  })

  self.result_container:mount()

  self.result = self:create_floating_window_for_split({
    split_winid = self.result_container.winid,
    buf_opts = {
      modifiable = false,
      swapfile = false,
      buftype = "nofile",
      bufhidden = "wipe",
      filetype = "Avante",
    },
    float_opts = {
      height = math.max(1, sidebar_height - selected_code_size - 3 - 8),
    },
  })

  self.result:on(event.BufWinEnter, function()
    xpcall(function()
      api.nvim_buf_set_name(self.result.bufnr, RESULT_BUF_NAME)
    end, function(_) end)
  end)

  self.result:map("n", "q", function()
    api.nvim_exec_autocmds("User", { pattern = Llm.CANCEL_PATTERN })
    self:close()
  end)

  self.result:map("n", "<Esc>", function()
    api.nvim_exec_autocmds("User", { pattern = Llm.CANCEL_PATTERN })
    self:close()
  end)

  self.result:mount()

  self.input_container = Split({
    enter = false,
    relative = {
      type = "win",
      winid = self.result_container.winid,
    },
    buf_options = buf_options,
    win_options = get_win_options(),
    position = "bottom",
  })

  self.input_container:mount()

  self:update_content_with_history(chat_history)

  -- reset states when buffer is closed
  api.nvim_buf_attach(self.code.bufnr, false, {
    on_detach = function(_, _)
      self:reset()
    end,
  })

  self:create_input()

  self:create_selected_code()

  self:on_mount()

  return self
end

return Sidebar
