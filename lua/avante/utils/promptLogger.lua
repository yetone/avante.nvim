local Config = require("avante.config")

---@class avante.utils.promptLogger
local M = {}

function M.log_prompt(request)
  local log_dir = Config.prompt_logger and Config.prompt_logger.log_dir or vim.fn.expand('~/.cache/nvim/avante_logs')
  local log_file = log_dir .. '/avante_prompt_' .. os.date('%Y%m%d_%H%M%S') .. '.log'

  if vim.fn.isdirectory(log_dir) == 0 then
    vim.fn.mkdir(log_dir, 'p')
  end

  local file = io.open(log_file, 'w')
  if file then
    file:write(request)
    file:close()
    if Config.prompt_logger and Config.prompt_logger.fortune_message_on_success then
      local handle = io.popen("fortune -s -n 100")
      if handle then
        local fortune_msg = handle:read("*a")
        handle:close()
        if fortune_msg and #fortune_msg > 0 then
          vim.notify(fortune_msg, vim.log.levels.INFO, { title = "" })
        end
      end
    end
  else
    vim.notify('Failed to log prompt', vim.log.levels.ERROR)
  end
end

return M

