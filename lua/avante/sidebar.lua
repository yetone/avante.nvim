local api = vim.api
local fn = vim.fn

local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local History = require("avante.history")
local Config = require("avante.config")
local Diff = require("avante.diff")
local Llm = require("avante.llm")
local Utils = require("avante.utils")
local Highlights = require("avante.highlights")

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
---@field winids table<string, integer> this table stores the winids of the sidebar components (result, selected_code, input), even though they are destroyed.
---@field result NuiSplit | nil
---@field selected_code NuiSplit | nil
---@field input NuiSplit | nil

---@param id integer the tabpage id retrieved from api.nvim_get_current_tabpage()
function Sidebar:new(id)
  return setmetatable({
    id = id,
    registered_cmp = false,
    code = { bufnr = 0, winid = 0, selection = nil },
    winids = {
      result = 0,
      selected_code = 0,
      input = 0,
    },
    result = nil,
    selected_code = nil,
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
  self.winids = { result = 0, selected_code = 0, input = 0 }
  self.result = nil
  self.selected_code = nil
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
  if self.code and self.code.winid and api.nvim_win_is_valid(self.code.winid) then
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

local function realign_line_numbers(code_lines, snippet)
  local snippet_lines = vim.split(snippet.content, "\n")
  local snippet_lines_count = #snippet_lines

  local start_line = snippet.range[1]

  local correct_start
  for i = start_line, math.max(1, start_line - snippet_lines_count + 1), -1 do
    local matched = true
    for j = 1, math.min(snippet_lines_count, start_line - i + 1) do
      if code_lines[i + j - 1] ~= snippet_lines[j] then
        matched = false
        break
      end
    end
    if matched then
      correct_start = i
      break
    end
  end

  local end_line = snippet.range[2]

  local correct_end
  for i = snippet_lines_count - 1, 1, -1 do
    local matched = true
    for j = 1, i do
      if code_lines[end_line + j - 1] ~= snippet_lines[snippet_lines_count - j] then
        matched = false
        break
      end
    end
    if matched then
      correct_end = end_line + i
      break
    end
  end

  if correct_start then
    snippet.range[1] = correct_start
  end

  if correct_end then
    snippet.range[2] = correct_end
  end

  return snippet
end

local function extract_code_snippets(code_content, response_content)
  local code_lines = vim.split(code_content, "\n")
  local snippets = {}
  local current_snippet = {}
  local in_code_block = false
  local lang, start_line, end_line
  local explanation = ""

  for _, line in ipairs(vim.split(response_content, "\n")) do
    local start_line_str, end_line_str = line:match("^Replace lines: (%d+)-(%d+)")
    if start_line_str ~= nil and end_line_str ~= nil then
      start_line = tonumber(start_line_str)
      end_line = tonumber(end_line_str)
    end
    if line:match("^```") then
      if in_code_block then
        if start_line ~= nil and end_line ~= nil then
          local snippet = {
            range = { start_line, end_line },
            content = table.concat(current_snippet, "\n"),
            lang = lang,
            explanation = explanation,
          }
          snippet = realign_line_numbers(code_lines, snippet)
          table.insert(snippets, snippet)
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
  local snippets = extract_code_snippets(content, response)
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

  if not Config.windows.sidebar_header.rounded then
    header_text = " " .. header_text .. " "
  end

  local winbar_text = "%#Normal#"

  if Config.windows.sidebar_header.align == "center" then
    winbar_text = winbar_text .. "%="
  elseif Config.windows.sidebar_header.align == "right" then
    winbar_text = winbar_text .. "%="
  end

  if Config.windows.sidebar_header.rounded then
    winbar_text = winbar_text .. "%#" .. reverse_hl .. "#" .. "" .. "%#" .. hl .. "#"
  else
    winbar_text = winbar_text .. "%#" .. hl .. "#"
  end
  winbar_text = winbar_text .. header_text
  if Config.windows.sidebar_header.rounded then
    winbar_text = winbar_text .. "%#" .. reverse_hl .. "#"
  end
  winbar_text = winbar_text .. "%#Normal#"
  if Config.windows.sidebar_header.align == "center" then
    winbar_text = winbar_text .. "%="
  end
  api.nvim_set_option_value("winbar", winbar_text, { win = winid })
end

function Sidebar:render_result()
  if not self.result or not self.result.bufnr or not api.nvim_buf_is_valid(self.result.bufnr) then
    return
  end
  local header_text = "󰭻 Avante"
  self:render_header(self.result.winid, self.result.bufnr, header_text, Highlights.TITLE, Highlights.REVERSED_TITLE)
end

function Sidebar:render_input()
  if not self.input or not self.input.bufnr or not api.nvim_buf_is_valid(self.input.bufnr) then
    return
  end

  local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })

  ---@type string
  local icon
  ---@diagnostic disable-next-line: undefined-field
  if _G.MiniIcons ~= nil then
    ---@diagnostic disable-next-line: undefined-global
    icon, _, _ = MiniIcons.get("filetype", filetype)
  else
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if ok then
      icon = devicons.get_icon_by_filetype(filetype, {})
    else
      icon = ""
    end
  end

  local code_file_fullpath = api.nvim_buf_get_name(self.code.bufnr)
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
    self.input.winid,
    self.input.bufnr,
    header_text,
    Highlights.THIRD_TITLE,
    Highlights.REVERSED_THIRD_TITLE
  )
end

function Sidebar:render_selected_code()
  if not self.selected_code or not self.selected_code.bufnr or not api.nvim_buf_is_valid(self.selected_code.bufnr) then
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
    self.selected_code.winid,
    self.selected_code.bufnr,
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
        virt_text = { { " [<A>: apply patch] ", "Keyword" } },
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
      vim.cmd("normal! zz")
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
      if not self.result or not self.result.bufnr or not api.nvim_buf_is_valid(self.result.bufnr) then
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

  self:render_result()
  self:render_input()
  self:render_selected_code()

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
      self:focus()
      if self.input and self.input.winid and api.nvim_win_is_valid(self.input.winid) then
        api.nvim_set_current_win(self.input.winid)
      end
      return true
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
    local winid = winids[current_idx]
    if winid and api.nvim_win_is_valid(winid) then
      pcall(api.nvim_set_current_win, winid)
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
    local winid = winids[current_idx]
    if winid and api.nvim_win_is_valid(winid) then
      api.nvim_set_current_win(winid)
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
  self:render_result()
  self:render_input()
  self:render_selected_code()
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
  if not self.result or not self.result.bufnr then
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
      if not self.result or not self.result.bufnr or not api.nvim_buf_is_valid(self.result.bufnr) then
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
      if not self.result or not self.result.bufnr or not api.nvim_buf_is_valid(self.result.bufnr) then
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

---@alias AvanteSlashCommands "clear" | "help" | "lines"
---@alias AvanteSlashCallback fun(args: string, cb?: fun(args: string): nil): nil
---@alias AvanteSlash {description: string, command: AvanteSlashCommands, details: string, shorthelp?: string, callback?: AvanteSlashCallback}
---@return AvanteSlash[]
function Sidebar:get_commands()
  ---@param items_ {command: string, description: string, shorthelp?: string}[]
  ---@return string
  local function get_help_text(items_)
    local help_text = ""
    for _, item in ipairs(items_) do
      help_text = help_text .. "- " .. item.command .. ": " .. (item.shorthelp or item.description) .. "\n"
    end
    return help_text
  end

  ---@type AvanteSlash[]
  local items = {
    { description = "Show help message", command = "help" },
    { description = "Clear chat history", command = "clear" },
    {
      shorthelp = "Ask a question about specific lines",
      description = "/lines <start>-<end> <question>",
      command = "lines",
    },
  }

  ---@type {[AvanteSlashCommands]: AvanteSlashCallback}
  local cbs = {
    help = function(args, cb)
      local help_text = get_help_text(items)
      self:update_content(help_text, { focus = false, scroll = false })
      if cb then
        cb(args)
      end
    end,
    clear = function(args, cb)
      local chat_history = {}
      History.save(self.code.bufnr, chat_history)
      self:update_content("Chat history cleared", { focus = false, scroll = false })
      vim.defer_fn(function()
        self:close()
        if cb then
          cb(args)
        end
      end, 1000)
    end,
    lines = function(args, cb)
      if cb then
        cb(args)
      end
    end,
  }

  return vim
    .iter(items)
    :map(
      ---@param item AvanteSlash
      function(item)
        return {
          command = item.command,
          description = item.description,
          callback = cbs[item.command],
          details = item.shorthelp and table.concat({ item.shorthelp, item.description }, "\n") or item.description,
        }
      end
    )
    :totable()
end

function Sidebar:create_selected_code()
  if self.selected_code ~= nil then
    self.selected_code:unmount()
    self.selected_code = nil
  end

  local selected_code_size = self:get_selected_code_size()

  if self.code.selection ~= nil then
    self.selected_code = Split({
      enter = false,
      relative = {
        type = "win",
        winid = self.input.winid,
      },
      buf_options = buf_options,
      win_options = get_win_options(),
      position = "top",
      size = {
        height = selected_code_size + 3,
      },
    })
    self.selected_code:mount()
  end
end

local hint_window = nil

function Sidebar:create_input()
  if self.input then
    self.input:unmount()
  end

  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then
    return
  end

  local chat_history = History.load(self.code.bufnr)

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
      ---@type AvanteSlash
      local cmd = vim
        .iter(cmds)
        :filter(function(_)
          return _.command == command
        end)
        :totable()[1]
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
      History.save(self.code.bufnr, chat_history)
    end

    Llm.stream(
      request,
      filetype,
      content_with_line_numbers,
      selected_code_content_with_line_numbers,
      "planning",
      on_chunk,
      on_complete
    )

    if Config.behaviour.auto_apply_diff_after_generation then
      self:apply()
    end
  end

  self.input = Split({
    enter = false,
    relative = {
      type = "win",
      winid = self.result.winid,
    },
    win_options = vim.tbl_deep_extend("force", get_win_options(), { signcolumn = "yes" }),
    position = "bottom",
    size = {
      height = 8,
    },
  })

  local function on_submit()
    if not vim.g.avante_login then
      Utils.warn("Sending message to fast!, API key is not yet set", { title = "Avante" })
      return
    end
    if not self.input or not self.input.bufnr or not api.nvim_buf_is_valid(self.input.bufnr) then
      return
    end
    local lines = api.nvim_buf_get_lines(self.input.bufnr, 0, -1, false)
    local request = table.concat(lines, "\n")
    if request == "" then
      return
    end
    api.nvim_buf_set_lines(self.input.bufnr, 0, -1, false, {})
    handle_submit(request)
  end

  self.input:mount()

  local function place_sign_at_first_line(bufnr)
    local group = "avante_input_prompt_group"

    vim.fn.sign_unplace(group, { buffer = bufnr })

    vim.fn.sign_place(0, group, "AvanteInputPromptSign", bufnr, { lnum = 1 })
  end

  place_sign_at_first_line(self.input.bufnr)
  api.nvim_win_set_hl_ns(self.input.winid, Highlights.input_ns)

  if Utils.in_visual_mode() then
    -- Exit visual mode
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
  end

  self.input:map("n", Config.mappings.submit.normal, on_submit)
  self.input:map("i", Config.mappings.submit.insert, on_submit)

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

    local hint_text = (vim.fn.mode() ~= "i" and Config.mappings.submit.normal or Config.mappings.submit.insert)
      .. ": submit"

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, { hint_text })

    -- Get the current window size
    local win_width = api.nvim_win_get_width(self.input.winid)
    local buf_height = api.nvim_buf_line_count(self.input.bufnr)
    local width = #hint_text

    -- Set the floating window options
    local opts = {
      relative = "win",
      win = self.input.winid,
      width = width,
      height = 1,
      row = buf_height,
      col = math.max(win_width - width, 0), -- Display in the bottom right corner
      style = "minimal",
      border = "none",
      focusable = false,
      zindex = 100,
    }

    -- Create the floating window
    hint_window = api.nvim_open_win(buf, false, opts)

    api.nvim_win_set_hl_ns(hint_window, Highlights.hint_ns)
  end

  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = self.augroup,
    buffer = self.input.bufnr,
    callback = function()
      show_hint()
      place_sign_at_first_line(self.input.bufnr)
    end,
  })

  api.nvim_create_autocmd("QuitPre", {
    group = self.augroup,
    buffer = self.input.bufnr,
    callback = function()
      close_hint()
    end,
  })

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

function Sidebar:render()
  local chat_history = History.load(self.code.bufnr)

  local sidebar_height = api.nvim_win_get_height(self.code.winid)
  local selected_code_size = self:get_selected_code_size()

  self.result = Split({
    enter = false,
    relative = "editor",
    position = "right",
    buf_options = vim.tbl_deep_extend("force", buf_options, {
      modifiable = false,
      swapfile = false,
      buftype = "nofile",
      bufhidden = "wipe",
      filetype = "Avante",
    }),
    win_options = get_win_options(),
    size = {
      width = string.format("%d%%", Config.windows.width),
      height = math.max(1, sidebar_height - selected_code_size - 3 - 8),
    },
  })

  self.result:mount()

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

  self:create_input()

  self:update_content_with_history(chat_history)

  -- reset states when buffer is closed
  api.nvim_buf_attach(self.code.bufnr, false, {
    on_detach = function(_, _)
      self:reset()
    end,
  })

  self:create_selected_code()

  self:on_mount()

  return self
end

return Sidebar
