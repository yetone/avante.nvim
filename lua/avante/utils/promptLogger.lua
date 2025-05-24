local Config = require("avante.config")
local Utils = require("avante.utils")

---@class avante.utils.promptLogger
local M = {}

function M.log_prompt(request)
  local log_dir = Config.prompt_logger.log_dir
  local log_file = Utils.join_paths(log_dir, "avante_prompt_" .. os.date("%Y%m%d_%H%M%S") .. ".log")

  if vim.fn.isdirectory(log_dir) == 0 then vim.fn.mkdir(log_dir, "p") end

  local file = io.open(log_file, "w")
  if file then
    file:write(request)
    file:close()
    if Config.prompt_logger and Config.prompt_logger.fortune_cookie_on_success then
      local handle = io.popen("fortune -s -n 100")
      if handle then
        local fortune_msg = handle:read("*a")
        handle:close()
        if fortune_msg and #fortune_msg > 0 then vim.notify(fortune_msg, vim.log.levels.INFO, { title = "" }) end
      end
    end
  else
    vim.notify("Failed to log prompt", vim.log.levels.ERROR)
  end
end

-- Cache + helper
local logs, idx = {}, 0

local function refresh_logs()
  local dir = Config.prompt_logger.log_dir
  logs = vim.fn.glob(Utils.join_paths(dir, "avante_prompt_*.log"), false, true)
  table.sort(logs, function(a, b) -- newest first
    return a > b
  end)
end

---@param step integer 0 = keep | 1 = newer | -1 = older
local function load_log(step)
  if #logs == 0 then refresh_logs() end
  if #logs == 0 then
    vim.notify("No prompt logs found 🤷", vim.log.levels.WARN)
    return
  end
  idx = (idx + step) -- turn wheel
  if idx < 1 then idx = #logs end -- wrap around
  if idx > #logs then idx = 1 end

  local fp = io.open(logs[idx], "r")
  if not fp then
    vim.notify("Could not open " .. logs[idx], vim.log.levels.ERROR)
    return
  end
  local content = fp:read("*a")
  fp:close()

  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
  vim.bo[buf].modifiable = true
  vim.b[buf].avante_logpath = logs[idx]
end

function M.next_log() load_log(1) end

function M.prev_log() load_log(-1) end

local function _read_log(delta)
  if #logs == 0 then refresh_logs() end
  if #logs == 0 then return nil end

  local target = idx + delta
  if target < 1 then target = 1 end
  if target > #logs then target = #logs end

  idx = target

  local fp = io.open(logs[idx], "r")
  if not fp then return nil end
  local txt = fp:read("*a")
  fp:close()
  return { txt = txt, path = logs[idx] }
end

function M.on_log_retrieve(delta)
  return function()
    local res = _read_log(delta)
    if not res then
      vim.notify("No logs available", vim.log.levels.WARN)
      return
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(res.txt, "\n", { plain = true }))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end
end

return M
