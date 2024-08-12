-----------------------------------------------------------------------------//
-- Utils
-----------------------------------------------------------------------------//
local M = {}

local api = vim.api
local fn = vim.fn

--- Wrapper for [vim.notify]
---@param msg string|string[]
---@param level "error" | "trace" | "debug" | "info" | "warn"
---@param once boolean?
function M.notify(msg, level, once)
  if type(msg) == "table" then
    msg = table.concat(msg, "\n")
  end
  local lvl = vim.log.levels[level:upper()] or vim.log.levels.INFO
  local opts = { title = "Git conflict" }
  if once then
    return vim.notify_once(msg, lvl, opts)
  end
  vim.notify(msg, lvl, opts)
end

--- Start an async job
---@param cmd string
---@param callback fun(data: string[]): nil
function M.job(cmd, callback)
  fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      callback(data)
    end,
  })
end

---Only call the passed function once every timeout in ms
---@param timeout integer
---@param func function
---@return function
function M.throttle(timeout, func)
  local timer = vim.loop.new_timer()
  local running = false
  return function(...)
    if not running then
      func(...)
      running = true
      timer:start(timeout, 0, function()
        running = false
      end)
    end
  end
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
  return api.nvim_get_hl_by_name(name, true)
end

return M
