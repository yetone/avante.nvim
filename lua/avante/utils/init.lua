local api = vim.api

---@class avante.Utils: LazyUtilCore
---@field colors avante.util.colors
local M = {}

setmetatable(M, {
  __index = function(t, k)
    local ok, lazyutil = pcall(require, "lazy.core.util")
    if ok and lazyutil[k] then
      return lazyutil[k]
    end

    ---@diagnostic disable-next-line: no-unknown
    t[k] = require("avante.utils." .. k)
    return t[k]
  end,
})

---Check if a plugin is installed
---@param plugin string
---@return boolean
M.has = function(plugin)
  return require("lazy.core.config").plugins[plugin] ~= nil
end

---@param str string
---@param opts? {suffix?: string, prefix?: string}
function M.trim(str, opts)
  if not opts then
    return str
  end
  if opts.suffix then
    return str:sub(-1) == opts.suffix and str:sub(1, -2) or str
  elseif opts.prefix then
    return str:sub(1, 1) == opts.prefix and str:sub(2) or str
  end
end

function M.in_visual_mode()
  local current_mode = vim.fn.mode()
  return current_mode == "v" or current_mode == "V" or current_mode == ""
end

---Get the selected content and range in Visual mode
---@return avante.SelectionResult | nil Selected content and range
function M.get_visual_selection_and_range()
  local Range = require("avante.range")
  local SelectionResult = require("avante.selection_result")

  if not M.in_visual_mode() then
    return nil
  end
  -- Get the start and end positions of Visual mode
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  -- Get the start and end line and column numbers
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]
  -- If the start point is after the end point, swap them
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end
  local content = ""
  local range = Range.new({ line = start_line, col = start_col }, { line = end_line, col = end_col })
  -- Check if it's a single-line selection
  if start_line == end_line then
    -- Get partial content of a single line
    local line = vim.fn.getline(start_line)
    -- content = string.sub(line, start_col, end_col)
    content = line
  else
    -- Multi-line selection: Get all lines in the selection
    local lines = vim.fn.getline(start_line, end_line)
    -- Extract partial content of the first line
    -- lines[1] = string.sub(lines[1], start_col)
    -- Extract partial content of the last line
    -- lines[#lines] = string.sub(lines[#lines], 1, end_col)
    -- Concatenate all lines in the selection into a string
    if type(lines) == "table" then
      content = table.concat(lines, "\n")
    else
      content = lines
    end
  end
  if not content then
    return nil
  end
  -- Return the selected content and range
  return SelectionResult.new(content, range)
end

---Wrapper around `api.nvim_buf_get_lines` which defaults to the current buffer
---@param start integer
---@param _end integer
---@param buf integer?
---@return string[]
function M.get_buf_lines(start, _end, buf)
  return api.nvim_buf_get_lines(buf or 0, start, _end, false)
end

---Get cursor row and column as (1, 0) based
---@param win_id integer?
---@return integer, integer
function M.get_cursor_pos(win_id)
  return unpack(api.nvim_win_get_cursor(win_id or 0))
end

---Check if the buffer is likely to have actionable conflict markers
---@param bufnr integer?
---@return boolean
function M.is_valid_buf(bufnr)
  bufnr = bufnr or 0
  return #vim.bo[bufnr].buftype == 0 and vim.bo[bufnr].modifiable
end

---@param name string?
---@return table<string, string>
function M.get_hl(name)
  if not name then
    return {}
  end
  return api.nvim_get_hl(0, { name = name })
end

--- vendor from lazy.nvim for early access and override

---@param msg string|string[]
---@param opts? LazyNotifyOpts
function M.notify(msg, opts)
  if vim.in_fast_event() then
    return vim.schedule(function()
      M.notify(msg, opts)
    end)
  end

  opts = opts or {}
  if type(msg) == "table" then
    ---@diagnostic disable-next-line: no-unknown
    msg = table.concat(
      vim.tbl_filter(function(line)
        return line or false
      end, msg),
      "\n"
    )
  end
  ---@diagnostic disable-next-line: undefined-field
  if opts.stacktrace then
    ---@diagnostic disable-next-line: undefined-field
    msg = msg .. M.pretty_trace({ level = opts.stacklevel or 2 })
  end
  local lang = opts.lang or "markdown"
  ---@diagnostic disable-next-line: undefined-field
  local n = opts.once and vim.notify_once or vim.notify
  n(msg, opts.level or vim.log.levels.INFO, {
    on_open = function(win)
      local ok = pcall(function()
        vim.treesitter.language.add("markdown")
      end)
      if not ok then
        pcall(require, "nvim-treesitter")
      end
      vim.wo[win].conceallevel = 3
      vim.wo[win].concealcursor = ""
      vim.wo[win].spell = false
      local buf = api.nvim_win_get_buf(win)
      if not pcall(vim.treesitter.start, buf, lang) then
        vim.bo[buf].filetype = lang
        vim.bo[buf].syntax = lang
      end
    end,
    title = opts.title or "lazy.nvim",
  })
end

---@param msg string|string[]
---@param opts? LazyNotifyOpts
function M.error(msg, opts)
  opts = opts or {}
  opts.level = vim.log.levels.ERROR
  M.notify(msg, opts)
end

---@param msg string|string[]
---@param opts? LazyNotifyOpts
function M.info(msg, opts)
  opts = opts or {}
  opts.level = vim.log.levels.INFO
  M.notify(msg, opts)
end

---@param msg string|string[]
---@param opts? LazyNotifyOpts
function M.warn(msg, opts)
  opts = opts or {}
  opts.level = vim.log.levels.WARN
  M.notify(msg, opts)
end

---@param msg string|table
---@param opts? LazyNotifyOpts
function M.debug(msg, opts)
  if not require("avante.config").options.debug then
    return
  end
  opts = opts or {}
  if opts.title then
    opts.title = "lazy.nvim: " .. opts.title
  end
  if type(msg) == "string" then
    M.notify(msg, opts)
  else
    opts.lang = "lua"
    M.notify(vim.inspect(msg), opts)
  end
end

function M.tbl_indexof(tbl, value)
  for i, v in ipairs(tbl) do
    if v == value then
      return i
    end
  end
  return nil
end

function M.update_win_options(winid, opt_name, key, value)
  local cur_opt_value = api.nvim_get_option_value(opt_name, { win = winid })

  if cur_opt_value:find(key .. ":") then
    cur_opt_value = cur_opt_value:gsub(key .. ":[^,]*", key .. ":" .. value)
  else
    if #cur_opt_value > 0 then
      cur_opt_value = cur_opt_value .. ","
    end
    cur_opt_value = cur_opt_value .. key .. ":" .. value
  end

  api.nvim_set_option_value(opt_name, cur_opt_value, { win = winid })
end

function M.get_win_options(winid, opt_name, key)
  local cur_opt_value = api.nvim_get_option_value(opt_name, { win = winid })
  if not cur_opt_value then
    return
  end
  local pieces = vim.split(cur_opt_value, ",")
  for _, piece in ipairs(pieces) do
    local kv_pair = vim.split(piece, ":")
    if kv_pair[1] == key then
      return kv_pair[2]
    end
  end
end

function M.unlock_buf(bufnr)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = true
end

function M.lock_buf(bufnr)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

---@param winnr? number
---@return nil
M.scroll_to_end = function(winnr)
  winnr = winnr or 0
  local bufnr = api.nvim_win_get_buf(winnr)
  local lnum = api.nvim_buf_line_count(bufnr)
  local last_line = api.nvim_buf_get_lines(bufnr, -2, -1, true)[1]
  api.nvim_win_set_cursor(winnr, { lnum, api.nvim_strwidth(last_line) })
end

---@param bufnr nil|integer
---@return nil
M.buf_scroll_to_end = function(bufnr)
  for _, winnr in ipairs(M.buf_list_wins(bufnr or 0)) do
    M.scroll_to_end(winnr)
  end
end

---@param bufnr nil|integer
---@return integer[]
M.buf_list_wins = function(bufnr)
  local wins = {}

  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end

  for _, winnr in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(winnr) and api.nvim_win_get_buf(winnr) == bufnr then
      table.insert(wins, winnr)
    end
  end

  return wins
end

return M
