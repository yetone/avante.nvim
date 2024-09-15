local Utils = require("avante.utils")
local Config = require("avante.config")
local Llm = require("avante.llm")
local Highlights = require("avante.highlights")
local Provider = require("avante.providers")

local api = vim.api
local fn = vim.fn

local NAMESPACE = api.nvim_create_namespace("avante_selection")
local SELECTED_CODE_NAMESPACE = api.nvim_create_namespace("avante_selected_code")
local PRIORITY = vim.highlight.priorities.user

local EDITING_INPUT_START_SPINNER_PATTERN = "AvanteEditingInputStartSpinner"
local EDITING_INPUT_STOP_SPINNER_PATTERN = "AvanteEditingInputStopSpinner"

---@class avante.Selection
---@field selection avante.SelectionResult | nil
---@field cursor_pos table | nil
---@field shortcuts_extmark_id integer | nil
---@field selected_code_extmark_id integer | nil
---@field augroup integer | nil
---@field editing_input_bufnr integer | nil
---@field editing_input_winid integer | nil
---@field editing_input_shortcuts_hints_winid integer | nil
---@field code_winid integer | nil
local Selection = {}

Selection.did_setup = false

---@param id integer the tabpage id retrieved from api.nvim_get_current_tabpage()
function Selection:new(id)
  return setmetatable({
    shortcuts_extmark_id = nil,
    selected_code_extmark_id = nil,
    augroup = api.nvim_create_augroup("avante_selection_" .. id, { clear = true }),
    selection = nil,
    cursor_pos = nil,
    editing_input_bufnr = nil,
    editing_input_winid = nil,
    editing_input_shortcuts_hints_winid = nil,
    code_winid = nil,
  }, { __index = self })
end

function Selection:get_virt_text_line()
  local current_pos = fn.getpos(".")

  -- Get the current and start position line numbers
  local current_line = current_pos[2] - 1 -- 0-indexed

  -- Ensure line numbers are not negative and don't exceed buffer range
  local total_lines = api.nvim_buf_line_count(0)
  if current_line < 0 then current_line = 0 end
  if current_line >= total_lines then current_line = total_lines - 1 end

  -- Take the first line of the selection to ensure virt_text is always in the top right corner
  return current_line
end

function Selection:show_shortcuts_hints_popup()
  self:close_shortcuts_hints_popup()

  local hint_text = string.format(" [%s: ask, %s: edit] ", Config.mappings.ask, Config.mappings.edit)

  local virt_text_line = self:get_virt_text_line()

  self.shortcuts_extmark_id = api.nvim_buf_set_extmark(0, NAMESPACE, virt_text_line, -1, {
    virt_text = { { hint_text, "AvanteInlineHint" } },
    virt_text_pos = "eol",
    priority = PRIORITY,
  })
end

function Selection:close_shortcuts_hints_popup()
  if self.shortcuts_extmark_id then
    api.nvim_buf_del_extmark(0, NAMESPACE, self.shortcuts_extmark_id)
    self.shortcuts_extmark_id = nil
  end
end

function Selection:close_editing_input()
  self:close_editing_input_shortcuts_hints()
  Llm.cancel_inflight_request()
  if api.nvim_get_mode().mode == "i" then vim.cmd([[stopinsert]]) end
  if self.editing_input_winid and api.nvim_win_is_valid(self.editing_input_winid) then
    api.nvim_win_close(self.editing_input_winid, true)
    self.editing_input_winid = nil
  end
  if self.code_winid and api.nvim_win_is_valid(self.code_winid) then
    local code_bufnr = api.nvim_win_get_buf(self.code_winid)
    api.nvim_buf_clear_namespace(code_bufnr, SELECTED_CODE_NAMESPACE, 0, -1)
    if self.selected_code_extmark_id then
      api.nvim_buf_del_extmark(code_bufnr, SELECTED_CODE_NAMESPACE, self.selected_code_extmark_id)
      self.selected_code_extmark_id = nil
    end
  end
  if self.cursor_pos and self.code_winid then
    vim.schedule(function()
      local bufnr = api.nvim_win_get_buf(self.code_winid)
      local line_count = api.nvim_buf_line_count(bufnr)
      local row = math.min(self.cursor_pos[1], line_count)
      local line = api.nvim_buf_get_lines(bufnr, row - 1, row, true)[1] or ""
      local col = math.min(self.cursor_pos[2], #line)
      api.nvim_win_set_cursor(self.code_winid, { row, col })
    end)
  end
  if self.editing_input_bufnr and api.nvim_buf_is_valid(self.editing_input_bufnr) then
    api.nvim_buf_delete(self.editing_input_bufnr, { force = true })
    self.editing_input_bufnr = nil
  end
end

function Selection:close_editing_input_shortcuts_hints()
  if self.editing_input_shortcuts_hints_winid and api.nvim_win_is_valid(self.editing_input_shortcuts_hints_winid) then
    api.nvim_win_close(self.editing_input_shortcuts_hints_winid, true)
    self.editing_input_shortcuts_hints_winid = nil
  end
end

function Selection:show_editing_input_shortcuts_hints()
  self:close_editing_input_shortcuts_hints()

  if not self.editing_input_winid or not api.nvim_win_is_valid(self.editing_input_winid) then return end

  local win_width = api.nvim_win_get_width(self.editing_input_winid)
  local buf_height = api.nvim_buf_line_count(self.editing_input_bufnr)
  -- spinner string: "⡀⠄⠂⠁⠈⠐⠠⢀⣀⢄⢂⢁⢈⢐⢠⣠⢤⢢⢡⢨⢰⣰⢴⢲⢱⢸⣸⢼⢺⢹⣹⢽⢻⣻⢿⣿⣶⣤⣀"
  local spinner_chars = {
    "⡀",
    "⠄",
    "⠂",
    "⠁",
    "⠈",
    "⠐",
    "⠠",
    "⢀",
    "⣀",
    "⢄",
    "⢂",
    "⢁",
    "⢈",
    "⢐",
    "⢠",
    "⣠",
    "⢤",
    "⢢",
    "⢡",
    "⢨",
    "⢰",
    "⣰",
    "⢴",
    "⢲",
    "⢱",
    "⢸",
    "⣸",
    "⢼",
    "⢺",
    "⢹",
    "⣹",
    "⢽",
    "⢻",
    "⣻",
    "⢿",
    "⣿",
    "⣶",
    "⣤",
    "⣀",
  }
  local spinner_index = 1
  local timer = nil

  local hint_text = (vim.fn.mode() ~= "i" and Config.mappings.submit.normal or Config.mappings.submit.insert)
    .. ": submit"

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, { hint_text })
  vim.api.nvim_buf_add_highlight(buf, 0, "AvantePopupHint", 0, 0, -1)

  local function update_spinner()
    spinner_index = (spinner_index % #spinner_chars) + 1
    local spinner = spinner_chars[spinner_index]
    local new_text = spinner .. " " .. hint_text

    api.nvim_buf_set_lines(buf, 0, -1, false, { new_text })

    if
      not self.editing_input_shortcuts_hints_winid
      or not api.nvim_win_is_valid(self.editing_input_shortcuts_hints_winid)
    then
      return
    end

    local win_config = vim.api.nvim_win_get_config(self.editing_input_shortcuts_hints_winid)

    local new_width = fn.strdisplaywidth(new_text)

    if win_config.width ~= new_width then
      win_config.width = new_width
      win_config.col = math.max(win_width - new_width, 0)
      vim.api.nvim_win_set_config(self.editing_input_shortcuts_hints_winid, win_config)
    end
  end

  local function stop_spinner()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    api.nvim_buf_set_lines(buf, 0, -1, false, { hint_text })

    if
      not self.editing_input_shortcuts_hints_winid
      or not api.nvim_win_is_valid(self.editing_input_shortcuts_hints_winid)
    then
      return
    end

    local win_config = vim.api.nvim_win_get_config(self.editing_input_shortcuts_hints_winid)

    if win_config.width ~= #hint_text then
      win_config.width = #hint_text
      win_config.col = math.max(win_width - #hint_text, 0)
      vim.api.nvim_win_set_config(self.editing_input_shortcuts_hints_winid, win_config)
    end
  end

  api.nvim_create_autocmd("User", {
    pattern = EDITING_INPUT_START_SPINNER_PATTERN,
    callback = function()
      timer = vim.uv.new_timer()
      if timer then timer:start(0, 100, vim.schedule_wrap(function() update_spinner() end)) end
    end,
  })

  api.nvim_create_autocmd("User", {
    pattern = EDITING_INPUT_STOP_SPINNER_PATTERN,
    callback = function() stop_spinner() end,
  })

  local width = fn.strdisplaywidth(hint_text)

  local opts = {
    relative = "win",
    win = self.editing_input_winid,
    width = width,
    height = 1,
    row = buf_height,
    col = math.max(win_width - width, 0),
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 100,
  }

  self.editing_input_shortcuts_hints_winid = api.nvim_open_win(buf, false, opts)
end

function Selection:create_editing_input()
  self:close_editing_input()

  if not vim.g.avante_login or vim.g.avante_login == false then
    api.nvim_exec_autocmds("User", { pattern = Provider.env.REQUEST_LOGIN_PATTERN })
    vim.g.avante_login = true
  end

  local code_bufnr = api.nvim_get_current_buf()
  local code_wind = api.nvim_get_current_win()
  self.cursor_pos = api.nvim_win_get_cursor(code_wind)
  self.code_winid = code_wind
  local code_lines = api.nvim_buf_get_lines(code_bufnr, 0, -1, false)
  local code_content = table.concat(code_lines, "\n")

  self.selection = Utils.get_visual_selection_and_range()

  local start_row
  local start_col
  local end_row
  local end_col
  if vim.fn.mode() == "V" then
    start_row = self.selection.range.start.line - 1
    start_col = 0
    end_row = self.selection.range.finish.line - 1
    end_col = #code_lines[self.selection.range.finish.line]
  else
    start_row = self.selection.range.start.line - 1
    start_col = self.selection.range.start.col - 1
    end_row = self.selection.range.finish.line - 1
    end_col = math.min(self.selection.range.finish.col, #code_lines[self.selection.range.finish.line])
  end

  self.selected_code_extmark_id = api.nvim_buf_set_extmark(code_bufnr, SELECTED_CODE_NAMESPACE, start_row, start_col, {
    hl_group = "Visual",
    hl_mode = "combine",
    end_row = end_row,
    end_col = end_col,
    priority = PRIORITY,
  })

  local bufnr = api.nvim_create_buf(false, true)

  self.editing_input_bufnr = bufnr

  local win_opts = {
    relative = "cursor",
    width = 40,
    height = 2,
    row = 1,
    col = 0,
    style = "minimal",
    border = Config.windows.edit.border,
    title = { { "edit selected block", "FloatTitle" } },
    title_pos = "center",
  }

  local winid = api.nvim_open_win(bufnr, true, win_opts)

  self.editing_input_winid = winid

  api.nvim_set_option_value("wrap", false, { win = winid })
  api.nvim_set_option_value("cursorline", true, { win = winid })
  api.nvim_set_option_value("modifiable", true, { buf = bufnr })

  self:show_editing_input_shortcuts_hints()

  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = self.augroup,
    buffer = bufnr,
    callback = function() self:show_editing_input_shortcuts_hints() end,
  })

  api.nvim_create_autocmd("ModeChanged", {
    group = self.augroup,
    pattern = "i:*",
    callback = function()
      local cur_buf = api.nvim_get_current_buf()
      if cur_buf == bufnr then self:show_editing_input_shortcuts_hints() end
    end,
  })

  api.nvim_create_autocmd("ModeChanged", {
    group = self.augroup,
    pattern = "*:i",
    callback = function()
      local cur_buf = api.nvim_get_current_buf()
      if cur_buf == bufnr then self:show_editing_input_shortcuts_hints() end
    end,
  })

  ---@param input string
  local function submit_input(input)
    local full_response = ""
    local start_line = self.selection.range.start.line
    local finish_line = self.selection.range.finish.line

    local original_first_line_indentation = Utils.get_indentation(code_lines[self.selection.range.start.line])

    local need_prepend_indentation = false

    api.nvim_exec_autocmds("User", { pattern = EDITING_INPUT_START_SPINNER_PATTERN })
    ---@type AvanteChunkParser
    local on_chunk = function(chunk)
      full_response = full_response .. chunk
      local response_lines = vim.split(full_response, "\n")
      if #response_lines == 1 then
        local first_line = response_lines[1]
        local first_line_indentation = Utils.get_indentation(first_line)
        need_prepend_indentation = first_line_indentation ~= original_first_line_indentation
      end
      if need_prepend_indentation then
        for i, line in ipairs(response_lines) do
          response_lines[i] = original_first_line_indentation .. line
        end
      end
      api.nvim_buf_set_lines(code_bufnr, start_line - 1, finish_line, true, response_lines)
      finish_line = start_line + #response_lines - 1
    end

    ---@type AvanteCompleteParser
    local on_complete = function(err)
      if err then
        Utils.error(
          "Error occurred while processing the response: " .. vim.inspect(err),
          { once = true, title = "Avante" }
        )
        return
      end
      api.nvim_exec_autocmds("User", { pattern = EDITING_INPUT_STOP_SPINNER_PATTERN })
      vim.defer_fn(function() self:close_editing_input() end, 0)
    end

    local filetype = api.nvim_get_option_value("filetype", { buf = code_bufnr })

    Llm.stream({
      bufnr = code_bufnr,
      ask = true,
      file_content = code_content,
      code_lang = filetype,
      selected_code = self.selection.content,
      instructions = input,
      mode = "editing",
      on_chunk = on_chunk,
      on_complete = on_complete,
    })
  end

  ---@return string
  local get_bufnr_input = function()
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return lines[1] or ""
  end

  vim.keymap.set(
    "i",
    Config.mappings.submit.insert,
    function() submit_input(get_bufnr_input()) end,
    { buffer = bufnr, noremap = true, silent = true }
  )
  vim.keymap.set(
    "n",
    Config.mappings.submit.normal,
    function() submit_input(get_bufnr_input()) end,
    { buffer = bufnr, noremap = true, silent = true }
  )
  vim.keymap.set("n", "<Esc>", function() self:close_editing_input() end, { buffer = bufnr })
  vim.keymap.set("n", "q", function() self:close_editing_input() end, { buffer = bufnr })

  local quit_id, close_unfocus
  quit_id = api.nvim_create_autocmd("QuitPre", {
    group = self.augroup,
    buffer = bufnr,
    once = true,
    nested = true,
    callback = function()
      self:close_editing_input()
      if not quit_id then
        api.nvim_del_autocmd(quit_id)
        quit_id = nil
      end
    end,
  })

  close_unfocus = api.nvim_create_autocmd("WinLeave", {
    group = self.augroup,
    buffer = bufnr,
    callback = function()
      self:close_editing_input()
      if close_unfocus then
        api.nvim_del_autocmd(close_unfocus)
        close_unfocus = nil
      end
    end,
  })

  api.nvim_create_autocmd("User", {
    pattern = "AvanteEditSubmitted",
    callback = function(ev)
      if ev.data and ev.data.request then submit_input(ev.data.request) end
    end,
  })
end

function Selection:setup_autocmds()
  Selection.did_setup = true
  api.nvim_create_autocmd({ "ModeChanged" }, {
    group = self.augroup,
    pattern = { "n:v", "n:V", "n:" }, -- Entering Visual mode from Normal mode
    callback = function(ev)
      if not Utils.is_sidebar_buffer(ev.buf) then self:show_shortcuts_hints_popup() end
    end,
  })

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = self.augroup,
    callback = function(ev)
      if not Utils.is_sidebar_buffer(ev.buf) then
        if Utils.in_visual_mode() then
          self:show_shortcuts_hints_popup()
        else
          self:close_shortcuts_hints_popup()
        end
      end
    end,
  })

  api.nvim_create_autocmd({ "ModeChanged" }, {
    group = self.augroup,
    pattern = { "v:n", "v:i", "v:c" }, -- Switching from visual mode back to normal, insert, or other modes
    callback = function(ev)
      if not Utils.is_sidebar_buffer(ev.buf) then self:close_shortcuts_hints_popup() end
    end,
  })

  api.nvim_create_autocmd({ "BufLeave" }, {
    group = self.augroup,
    callback = function(ev)
      if not Utils.is_sidebar_buffer(ev.buf) then self:close_shortcuts_hints_popup() end
    end,
  })

  return self
end

function Selection:delete_autocmds()
  if self.augroup then api.nvim_del_augroup_by_id(self.augroup) end
  self.augroup = nil
  Selection.did_setup = false
end

return Selection
