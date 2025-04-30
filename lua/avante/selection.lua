local Utils = require("avante.utils")
local Config = require("avante.config")
local Llm = require("avante.llm")
local Provider = require("avante.providers")
local RepoMap = require("avante.repo_map")
local PromptInput = require("avante.ui.prompt_input")
local SelectionResult = require("avante.selection_result")
local Range = require("avante.range")

local api = vim.api
local fn = vim.fn

local NAMESPACE = api.nvim_create_namespace("avante_selection")
local SELECTED_CODE_NAMESPACE = api.nvim_create_namespace("avante_selected_code")
local PRIORITY = (vim.hl or vim.highlight).priorities.user

---@class avante.Selection
---@field selection avante.SelectionResult | nil
---@field cursor_pos table | nil
---@field shortcuts_extmark_id integer | nil
---@field selected_code_extmark_id integer | nil
---@field augroup integer | nil
---@field code_winid integer | nil
---@field code_bufnr integer | nil
---@field prompt_input avante.ui.PromptInput | nil
local Selection = {}
Selection.__index = Selection

Selection.did_setup = false

---@param id integer the tabpage id retrieved from api.nvim_get_current_tabpage()
function Selection:new(id)
  return setmetatable({
    shortcuts_extmark_id = nil,
    selected_code_extmark_id = nil,
    augroup = api.nvim_create_augroup("avante_selection_" .. id, { clear = true }),
    selection = nil,
    cursor_pos = nil,
    code_winid = nil,
    code_bufnr = nil,
    prompt_input = nil,
  }, Selection)
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
  if self.prompt_input then
    self.prompt_input:close()
    self.prompt_input = nil
  end
  Llm.cancel_inflight_request()
  if self.code_winid and api.nvim_win_is_valid(self.code_winid) then
    local code_bufnr = api.nvim_win_get_buf(self.code_winid)
    api.nvim_buf_clear_namespace(code_bufnr, SELECTED_CODE_NAMESPACE, 0, -1)
    if self.selected_code_extmark_id then
      api.nvim_buf_del_extmark(code_bufnr, SELECTED_CODE_NAMESPACE, self.selected_code_extmark_id)
      self.selected_code_extmark_id = nil
    end
  end
  if self.cursor_pos and self.code_winid and api.nvim_win_is_valid(self.code_winid) then
    vim.schedule(function()
      local bufnr = api.nvim_win_get_buf(self.code_winid)
      local line_count = api.nvim_buf_line_count(bufnr)
      local row = math.min(self.cursor_pos[1], line_count)
      local line = api.nvim_buf_get_lines(bufnr, row - 1, row, true)[1] or ""
      local col = math.min(self.cursor_pos[2], #line)
      api.nvim_win_set_cursor(self.code_winid, { row, col })
    end)
  end
end

function Selection:submit_input(input)
  if not input then
    Utils.error("No input provided", { once = true, title = "Avante" })
    return
  end
  if self.prompt_input and self.prompt_input.spinner_active then
    Utils.error(
      "Please wait for the previous request to finish before submitting another",
      { once = true, title = "Avante" }
    )
    return
  end
  local code_lines = api.nvim_buf_get_lines(self.code_bufnr, 0, -1, false)
  local code_content = table.concat(code_lines, "\n")

  local full_response = ""
  local start_line = self.selection.range.start.lnum
  local finish_line = self.selection.range.finish.lnum

  local original_first_line_indentation = Utils.get_indentation(code_lines[self.selection.range.start.lnum])

  local need_prepend_indentation = false

  if self.prompt_input then self.prompt_input:start_spinner() end

  ---@type AvanteLLMStartCallback
  local function on_start(_) end

  ---@type AvanteLLMChunkCallback
  local function on_chunk(chunk)
    full_response = full_response .. chunk
    local response_lines_ = vim.split(full_response, "\n")
    local response_lines = {}
    local in_code_block = false
    for _, line in ipairs(response_lines_) do
      if line:match("^<code>") then
        in_code_block = true
        line = line:gsub("^<code>", ""):gsub("</code>.*$", "")
        if line ~= "" then table.insert(response_lines, line) end
      elseif line:match("</code>") then
        in_code_block = false
        line = line:gsub("</code>.*$", "")
        if line ~= "" then table.insert(response_lines, line) end
      elseif in_code_block then
        table.insert(response_lines, line)
      end
    end
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
    api.nvim_buf_set_lines(self.code_bufnr, start_line - 1, finish_line, true, response_lines)
    finish_line = start_line + #response_lines - 1
  end

  ---@type AvanteLLMStopCallback
  local function on_stop(stop_opts)
    if stop_opts.error then
      -- NOTE: in Ubuntu 22.04+ you will see this ignorable error from ~/.local/share/nvim/lazy/avante.nvim/lua/avante/llm.lua `on_error = function(err)`, check to avoid showing this error.
      if type(stop_opts.error) == "table" and stop_opts.error.exit == nil and stop_opts.error.stderr == "{}" then
        return
      end
      Utils.error(
        "Error occurred while processing the response: " .. vim.inspect(stop_opts.error),
        { once = true, title = "Avante" }
      )
      return
    end
    if self.prompt_input then self.prompt_input:stop_spinner() end
    vim.defer_fn(function() self:close_editing_input() end, 0)
    Utils.debug("full response:", full_response)
  end

  local filetype = api.nvim_get_option_value("filetype", { buf = self.code_bufnr })
  local file_ext = api.nvim_buf_get_name(self.code_bufnr):match("^.+%.(.+)$")

  local mentions = Utils.extract_mentions(input)
  input = mentions.new_content
  local project_context = mentions.enable_project_context and RepoMap.get_repo_map(file_ext) or nil

  local diagnostics = Utils.get_current_selection_diagnostics(self.code_bufnr, self.selection)

  ---@type AvanteSelectedCode | nil
  local selected_code = nil

  if self.selection then
    selected_code = {
      content = self.selection.content,
      file_type = self.selection.filetype,
      path = self.selection.filepath,
    }
  end

  Llm.stream({
    ask = true,
    project_context = vim.json.encode(project_context),
    diagnostics = vim.json.encode(diagnostics),
    selected_files = { { content = code_content, file_type = filetype, path = "" } },
    code_lang = filetype,
    selected_code = selected_code,
    instructions = input,
    mode = "editing",
    on_start = on_start,
    on_chunk = on_chunk,
    on_stop = on_stop,
  })
end

---@param request? string
---@param line1? integer
---@param line2? integer
function Selection:create_editing_input(request, line1, line2)
  self:close_editing_input()

  if not vim.g.avante_login or vim.g.avante_login == false then
    api.nvim_exec_autocmds("User", { pattern = Provider.env.REQUEST_LOGIN_PATTERN })
    vim.g.avante_login = true
  end

  self.code_bufnr = api.nvim_get_current_buf()
  self.code_winid = api.nvim_get_current_win()
  self.cursor_pos = api.nvim_win_get_cursor(self.code_winid)
  local code_lines = api.nvim_buf_get_lines(self.code_bufnr, 0, -1, false)

  if line1 ~= nil and line2 ~= nil then
    local filepath = vim.fn.expand("%:p")
    local filetype = Utils.get_filetype(filepath)
    local content_lines = vim.list_slice(code_lines, line1, line2)
    local content = table.concat(content_lines, "\n")
    local range = Range:new(
      { lnum = line1, col = #content_lines[1] },
      { lnum = line2, col = #content_lines[#content_lines] }
    )
    self.selection = SelectionResult:new(filepath, filetype, content, range)
  else
    self.selection = Utils.get_visual_selection_and_range()
  end

  if self.selection == nil then
    Utils.error("No visual selection found", { once = true, title = "Avante" })
    return
  end

  local start_row
  local start_col
  local end_row
  local end_col
  if vim.fn.mode() == "V" then
    start_row = self.selection.range.start.lnum - 1
    start_col = 0
    end_row = self.selection.range.finish.lnum - 1
    end_col = #code_lines[self.selection.range.finish.lnum]
  else
    start_row = self.selection.range.start.lnum - 1
    start_col = self.selection.range.start.col - 1
    end_row = self.selection.range.finish.lnum - 1
    end_col = math.min(self.selection.range.finish.col, #code_lines[self.selection.range.finish.lnum])
  end

  self.selected_code_extmark_id =
    api.nvim_buf_set_extmark(self.code_bufnr, SELECTED_CODE_NAMESPACE, start_row, start_col, {
      hl_group = "Visual",
      hl_mode = "combine",
      end_row = end_row,
      end_col = end_col,
      priority = PRIORITY,
    })

  local prompt_input = PromptInput:new({
    default_value = request,
    submit_callback = function(input) self:submit_input(input) end,
    cancel_callback = function() self:close_editing_input() end,
    win_opts = {
      border = Config.windows.edit.border,
      height = Config.windows.edit.height,
      width = Config.windows.edit.width,
      title = { { "Avante edit selected block", "FloatTitle" } },
    },
    start_insert = Config.windows.edit.start_insert,
  })

  self.prompt_input = prompt_input

  prompt_input:open()
end

function Selection:setup_autocmds()
  Selection.did_setup = true

  api.nvim_create_autocmd("User", {
    group = self.augroup,
    pattern = "AvanteEditSubmitted",
    callback = function(ev) self:submit_input(ev.data.request) end,
  })

  api.nvim_create_autocmd({ "ModeChanged" }, {
    group = self.augroup,
    pattern = { "n:v", "n:V", "n:" }, -- Entering Visual mode from Normal mode
    callback = function(ev)
      if not Utils.is_sidebar_buffer(ev.buf) then self:show_shortcuts_hints_popup() end
    end,
  })

  api.nvim_create_autocmd({ "CursorMoved" }, {
    group = self.augroup,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "terminal" and not Utils.is_sidebar_buffer(ev.buf) then
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
