local Utils = require("avante.utils")
local Config = require("avante.config")
local Llm = require("avante.llm")
local Provider = require("avante.providers")
local RepoMap = require("avante.repo_map")
local PromptInput = require("avante.prompt_input")

local api = vim.api
local fn = vim.fn

local NAMESPACE = api.nvim_create_namespace("avante_selection")
local SELECTED_CODE_NAMESPACE = api.nvim_create_namespace("avante_selected_code")
local PRIORITY = vim.highlight.priorities.user

---@class avante.Selection
---@field selection avante.SelectionResult | nil
---@field cursor_pos table | nil
---@field shortcuts_extmark_id integer | nil
---@field selected_code_extmark_id integer | nil
---@field augroup integer | nil
---@field code_winid integer | nil
---@field prompt_input PromptInput | nil
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
end

function Selection:create_editing_input()
  self:close_editing_input()

  if not vim.g.avante_login or vim.g.avante_login == false then
    api.nvim_exec_autocmds("User", { pattern = Provider.env.REQUEST_LOGIN_PATTERN })
    vim.g.avante_login = true
  end

  local code_bufnr = api.nvim_get_current_buf()
  local code_winid = api.nvim_get_current_win()
  self.cursor_pos = api.nvim_win_get_cursor(code_winid)
  self.code_winid = code_winid
  local code_lines = api.nvim_buf_get_lines(code_bufnr, 0, -1, false)
  local code_content = table.concat(code_lines, "\n")

  self.selection = Utils.get_visual_selection_and_range()

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

  self.selected_code_extmark_id = api.nvim_buf_set_extmark(code_bufnr, SELECTED_CODE_NAMESPACE, start_row, start_col, {
    hl_group = "Visual",
    hl_mode = "combine",
    end_row = end_row,
    end_col = end_col,
    priority = PRIORITY,
  })

  local submit_input = function(input)
    local full_response = ""
    local start_line = self.selection.range.start.lnum
    local finish_line = self.selection.range.finish.lnum

    local original_first_line_indentation = Utils.get_indentation(code_lines[self.selection.range.start.lnum])

    local need_prepend_indentation = false

    self.prompt_input:start_spinner()

    ---@type AvanteChunkParser
    local on_chunk = function(chunk)
      full_response = full_response .. chunk
      local response_lines_ = vim.split(full_response, "\n")
      local response_lines = {}
      for i, line in ipairs(response_lines_) do
        if string.match(line, "^```") and (i == 1 or i == #response_lines_) then goto continue end
        if string.match(line, "^```$") then goto continue end
        table.insert(response_lines, line)
        ::continue::
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
      api.nvim_buf_set_lines(code_bufnr, start_line - 1, finish_line, true, response_lines)
      finish_line = start_line + #response_lines - 1
    end

    ---@type AvanteCompleteParser
    local on_complete = function(err)
      if err then
        -- NOTE: in Ubuntu 22.04+ you will see this ignorable error from ~/.local/share/nvim/lazy/avante.nvim/lua/avante/llm.lua `on_error = function(err)`, check to avoid showing this error.
        if type(err) == "table" and err.exit == nil and err.stderr == "{}" then return end
        Utils.error(
          "Error occurred while processing the response: " .. vim.inspect(err),
          { once = true, title = "Avante" }
        )
        return
      end
      self.prompt_input:stop_spinner()
      vim.defer_fn(function() self:close_editing_input() end, 0)
      Utils.debug("full response:", full_response)
    end

    local filetype = api.nvim_get_option_value("filetype", { buf = code_bufnr })
    local file_ext = api.nvim_buf_get_name(code_bufnr):match("^.+%.(.+)$")

    local mentions = Utils.extract_mentions(input)
    input = mentions.new_content
    local project_context = mentions.enable_project_context and RepoMap.get_repo_map(file_ext) or nil

    local diagnostics = Utils.get_current_selection_diagnostics(code_bufnr, self.selection)

    Llm.stream({
      ask = true,
      project_context = vim.json.encode(project_context),
      diagnostics = vim.json.encode(diagnostics),
      selected_files = { { content = code_content, file_type = filetype, path = "" } },
      code_lang = filetype,
      selected_code = self.selection.content,
      instructions = input,
      mode = "editing",
      on_chunk = on_chunk,
      on_complete = on_complete,
    })
  end

  local prompt_input = PromptInput:new({
    submit_callback = submit_input,
    cancel_callback = function() self:close_editing_input() end,
    win_opts = {
      border = Config.windows.edit.border,
      title = { { "edit selected block", "FloatTitle" } },
    },
    start_insert = Config.windows.edit.start_insert,
  })

  self.prompt_input = prompt_input

  prompt_input:open()

  api.nvim_create_autocmd("InsertEnter", {
    group = self.augroup,
    buffer = prompt_input.bufnr,
    once = true,
    desc = "Setup the completion of helpers in the input buffer",
    callback = function()
      local has_cmp, cmp = pcall(require, "cmp")
      if has_cmp then
        cmp.register_source(
          "avante_mentions",
          require("cmp_avante.mentions"):new(Utils.get_mentions(), prompt_input.bufnr)
        )
        cmp.setup.buffer({
          enabled = true,
          sources = {
            { name = "avante_mentions" },
          },
        })
      end
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
