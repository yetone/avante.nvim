local Utils = require("avante.utils")
local Llm = require("avante.llm")
local Highlights = require("avante.highlights")
local Config = require("avante.config")
local Providers = require("avante.providers")
local api = vim.api
local fn = vim.fn

local SUGGESTION_NS = api.nvim_create_namespace("avante_suggestion")

---@class avante.SuggestionItem
---@field content string
---@field row number
---@field col number

---@class avante.SuggestionContext
---@field suggestions avante.SuggestionItem[]
---@field current_suggestion_idx number
---@field prev_doc? table

---@class avante.Suggestion
---@field id number
---@field augroup integer
---@field extmark_id integer
---@field _timer? table
---@field _contexts table
local Suggestion = {}
Suggestion.__index = Suggestion

---@param id number
---@return avante.Suggestion
function Suggestion:new(id)
  local instance = setmetatable({}, self)
  instance.id = id
  instance.extmark_id = 1
  instance._timer = nil
  instance._contexts = {}
  if Config.behaviour.auto_suggestions then
    if not vim.g.avante_login or vim.g.avante_login == false then
      api.nvim_exec_autocmds("User", { pattern = Providers.env.REQUEST_LOGIN_PATTERN })
      vim.g.avante_login = true
    end
    instance:setup_autocmds()
  end
  return instance
end

function Suggestion:destroy()
  self:stop_timer()
  self:reset()
  self:delete_autocmds()
end

function Suggestion:suggest()
  Utils.debug("suggesting")

  local ctx = self:ctx()
  local doc = Utils.get_doc()
  ctx.prev_doc = doc

  local bufnr = api.nvim_get_current_buf()
  local filetype = api.nvim_get_option_value("filetype", { buf = bufnr })
  local code_content =
    Utils.prepend_line_number(table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") .. "\n\n")

  local full_response = ""

  local provider = Providers[Config.auto_suggestions_provider]

  Llm.stream({
    provider = provider,
    bufnr = bufnr,
    ask = true,
    file_content = code_content,
    code_lang = filetype,
    instructions = vim.json.encode(doc),
    mode = "suggesting",
    on_chunk = function(chunk) full_response = full_response .. chunk end,
    on_complete = function(err)
      if err then
        Utils.error("Error while suggesting: " .. vim.inspect(err), { once = true, title = "Avante" })
        return
      end
      Utils.debug("full_response: " .. vim.inspect(full_response))
      local cursor_row, cursor_col = Utils.get_cursor_pos()
      if cursor_row ~= doc.position.row or cursor_col ~= doc.position.col then return end
      local ok, suggestions = pcall(vim.json.decode, full_response)
      if not ok then
        Utils.error("Error while decoding suggestions: " .. full_response, { once = true, title = "Avante" })
        return
      end
      if not suggestions then
        Utils.info("No suggestions found", { once = true, title = "Avante" })
        return
      end
      suggestions = vim
        .iter(suggestions)
        :map(function(s) return { row = s.row, col = s.col, content = Utils.trim_all_line_numbers(s.content) } end)
        :totable()
      ctx.suggestions = suggestions
      ctx.current_suggestion_idx = 1
      self:show()
    end,
  })
end

function Suggestion:show()
  self:hide()

  if not fn.mode():match("^[iR]") then return end

  local ctx = self:ctx()
  local suggestion = ctx.suggestions[ctx.current_suggestion_idx]
  if not suggestion then return end

  local cursor_row, cursor_col = Utils.get_cursor_pos()

  if suggestion.row < cursor_row then return end

  local bufnr = api.nvim_get_current_buf()
  local row = suggestion.row
  local col = suggestion.col
  local content = suggestion.content

  local lines = vim.split(content, "\n")

  local extmark_col = cursor_col

  if cursor_row < row then extmark_col = 0 end

  local current_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)

  if cursor_row == row then
    local cursor_line_col = #current_lines[cursor_row] - 1
    if cursor_col ~= cursor_line_col then
      local current_line = current_lines[cursor_row]
      lines[1] = lines[1] .. current_line:sub(col + 1, -1)
    end
  end

  local extmark = {
    id = self.extmark_id,
    virt_text_win_col = col,
    virt_text = { { lines[1], Highlights.SUGGESTION } },
  }

  if #lines > 1 then
    extmark.virt_lines = {}
    for i = 2, #lines do
      extmark.virt_lines[i - 1] = { { lines[i], Highlights.SUGGESTION } }
    end
  end

  extmark.hl_mode = "combine"

  local buf_lines = Utils.get_buf_lines(0, -1, bufnr)
  local buf_lines_count = #buf_lines

  while buf_lines_count < row do
    api.nvim_buf_set_lines(bufnr, buf_lines_count, -1, false, { "" })
    buf_lines_count = buf_lines_count + 1
  end

  api.nvim_buf_set_extmark(bufnr, SUGGESTION_NS, row - 1, extmark_col, extmark)
end

function Suggestion:is_visible()
  return not not api.nvim_buf_get_extmark_by_id(0, SUGGESTION_NS, self.extmark_id, { details = false })[1]
end

function Suggestion:hide() api.nvim_buf_del_extmark(0, SUGGESTION_NS, self.extmark_id) end

function Suggestion:ctx()
  local bufnr = api.nvim_get_current_buf()
  local ctx = self._contexts[bufnr]
  if not ctx then
    ctx = {
      suggestions = {},
      current_suggestion_idx = 0,
      prev_doc = {},
    }
    self._contexts[bufnr] = ctx
  end
  return ctx
end

function Suggestion:reset()
  self._timer = nil
  local bufnr = api.nvim_get_current_buf()
  self._contexts[bufnr] = nil
end

function Suggestion:stop_timer()
  if self._timer then
    pcall(function() fn.timer_stop(self._timer) end)
    self._timer = nil
  end
end

function Suggestion:next()
  local ctx = self:ctx()
  if #ctx.suggestions == 0 then return end
  ctx.current_suggestion_idx = (ctx.current_suggestion_idx % #ctx.suggestions) + 1
  self:show()
end

function Suggestion:prev()
  local ctx = self:ctx()
  if #ctx.suggestions == 0 then return end
  ctx.current_suggestion_idx = ((ctx.current_suggestion_idx - 2 + #ctx.suggestions) % #ctx.suggestions) + 1
  self:show()
end

function Suggestion:dismiss()
  self:stop_timer()
  self:hide()
  self:reset()
end

function Suggestion:accept()
  -- Llm.cancel_inflight_request()
  api.nvim_buf_del_extmark(0, SUGGESTION_NS, self.extmark_id)
  local ctx = self:ctx()
  local suggestion = ctx.suggestions and ctx.suggestions[ctx.current_suggestion_idx] or nil
  if not suggestion then
    if Config.mappings.suggestion and Config.mappings.suggestion.accept == "<Tab>" then
      api.nvim_feedkeys(api.nvim_replace_termcodes("<Tab>", true, false, true), "n", true)
    end
    return
  end
  local bufnr = api.nvim_get_current_buf()
  local current_lines = Utils.get_buf_lines(0, -1, bufnr)
  local row = suggestion.row
  local col = suggestion.col
  local content = suggestion.content
  local lines = vim.split(content, "\n")
  local cursor_row, cursor_col = Utils.get_cursor_pos()
  if row > cursor_row then api.nvim_buf_set_lines(bufnr, row - 1, row - 1, false, { "" }) end
  local line_count = #lines
  if line_count > 0 then
    if cursor_row == row then
      local cursor_line_col = #current_lines[cursor_row] - 1
      if cursor_col ~= cursor_line_col then
        local current_line_ = current_lines[cursor_row]
        lines[1] = lines[1] .. current_line_:sub(col + 1, -1)
      end
    end
    local current_line = current_lines[row] or ""
    local current_line_max_col = #current_line - 1
    local start_col = col
    if start_col > current_line_max_col then
      lines[1] = string.rep(" ", start_col - current_line_max_col - 1) .. lines[1]
      start_col = -1
    end
    api.nvim_buf_set_text(bufnr, row - 1, start_col, row - 1, -1, { lines[1] })
    if #lines > 1 then
      local insert_lines = vim.list_slice(lines, 2)
      api.nvim_buf_set_lines(bufnr, row, row, true, insert_lines)
    end
  end

  local down_count = line_count - 1
  if row > cursor_row then down_count = down_count + 1 end

  local cursor_keys = string.rep("<Down>", down_count) .. "<End>"
  api.nvim_feedkeys(api.nvim_replace_termcodes(cursor_keys, true, false, true), "n", false)

  self:hide()
  self:reset()
end

function Suggestion:setup_autocmds()
  self.augroup = api.nvim_create_augroup("avante_suggestion_" .. self.id, { clear = true })
  local last_cursor_pos = {}

  local check_for_suggestion = Utils.debounce(function()
    local current_cursor_pos = api.nvim_win_get_cursor(0)
    if last_cursor_pos[1] == current_cursor_pos[1] and last_cursor_pos[2] == current_cursor_pos[2] then
      self:suggest()
    end
  end, 700)

  local function suggest_callback()
    if not vim.bo.buflisted then return end

    if vim.bo.buftype ~= "" then return end

    local ctx = self:ctx()

    if ctx.prev_doc and vim.deep_equal(ctx.prev_doc, Utils.get_doc()) then return end

    self:hide()
    last_cursor_pos = api.nvim_win_get_cursor(0)
    self._timer = check_for_suggestion()
  end

  api.nvim_create_autocmd("InsertEnter", {
    group = self.augroup,
    callback = suggest_callback,
  })

  api.nvim_create_autocmd("BufEnter", {
    group = self.augroup,
    callback = function()
      if fn.mode():match("^[iR]") then suggest_callback() end
    end,
  })

  api.nvim_create_autocmd("CursorMovedI", {
    group = self.augroup,
    callback = suggest_callback,
  })

  api.nvim_create_autocmd("InsertLeave", {
    group = self.augroup,
    callback = function()
      last_cursor_pos = {}
      self:hide()
      self:reset()
    end,
  })
end

function Suggestion:delete_autocmds()
  if self.augroup then api.nvim_del_augroup_by_id(self.augroup) end
  self.augroup = nil
end

return Suggestion
