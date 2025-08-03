local Config = require("avante.config")
local Utils = require("avante.utils")

-- last one in entries is always to hold current input
local entries, idx = {}, 0

---@class avante.utils.promptLogger
local M = {}

function M.init()
  entries = {}
  local dir = Config.prompt_logger.log_dir
  local log_file = Utils.join_paths(dir, "avante_prompts.log")
  local file = io.open(log_file, "r")
  if file then
    local content = file:read("*a"):gsub("\n$", "")
    file:close()

    local lines = vim.split(content, "\n", { plain = true })
    for _, line in ipairs(lines) do
      local ok, entry = pcall(vim.fn.json_decode, line)
      if ok and entry and entry.time and entry.input then table.insert(entries, entry) end
    end
  end
  table.insert(entries, { input = "" })
  idx = #entries - 1
end

function M.log_prompt(request)
  local log_dir = Config.prompt_logger.log_dir
  local log_file = Utils.join_paths(log_dir, "avante_prompts.log")

  if vim.fn.isdirectory(log_dir) == 0 then vim.fn.mkdir(log_dir, "p") end

  local entry = {
    time = Utils.get_timestamp(),
    input = request,
  }

  -- Remove any existing entries with the same input
  if #entries > 1 then
    for i = #entries - 1, 1, -1 do
      if entries[i].input == entry.input then table.remove(entries, i) end
    end
    -- Add the new entry
    table.insert(entries, #entries, entry)
    idx = #entries - 1
  else
    table.insert(entries, entry)
  end

  local file = io.open(log_file, "w")
  if file then
    -- Write all entries to the log file, except the last one
    for i = 1, #entries - 1, 1 do
      file:write(vim.fn.json_encode(entries[i]) .. "\n")
    end
    file:close()
  else
    vim.notify("Failed to log prompt", vim.log.levels.ERROR)
  end
end

local function _read_log(delta)
  -- index of array starts from 1 in lua, while this idx starts from 0
  idx = ((idx - delta) % #entries + #entries) % #entries

  return entries[idx + 1]
end

function M.on_log_retrieve(delta)
  return function()
    local res = _read_log(delta)
    if not res or not res.input then
      vim.notify("No log entry found.", vim.log.levels.WARN)
      return
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(res.input, "\n", { plain = true }))
    vim.api.nvim_win_set_cursor(
      0,
      { vim.api.nvim_buf_line_count(0), #vim.api.nvim_buf_get_lines(0, -2, -1, false)[1] }
    )
  end
end

function M.update_current_input()
  if idx == #entries - 1 then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    entries[#entries].input = table.concat(lines, "\n")
  end
end

return M
