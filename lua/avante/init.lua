local M = {}
local sidebar = require("avante.sidebar")
local config = require("avante.config")

function M.setup(opts)
  local ok, LazyConfig = pcall(require, "lazy.core.config")
  if ok then
    local name = "avante.nvim"
    if LazyConfig.plugins[name] and LazyConfig.plugins[name]._.loaded then
      vim.schedule(function()
        require("tiktoken_lib").load()
      end)
    else
      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyLoad",
        callback = function(event)
          if event.data == name then
            require("tiktoken_lib").load()
            return true
          end
        end,
      })
    end
  end

  config.update(opts)
  sidebar.setup()
end

return M
