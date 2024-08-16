local M = {}
local tiktoken = require("avante.tiktoken")
local sidebar = require("avante.sidebar")
local config = require("avante.config")

local api = vim.api

function M.setup(opts)
  local load_path = function()
    require("tiktoken_lib").load()

    tiktoken.setup("gpt-4o")
  end

  local ok, LazyConfig = pcall(require, "lazy.core.config")
  if ok then
    local name = "avante.nvim"
    if LazyConfig.plugins[name] and LazyConfig.plugins[name]._.loaded then
      vim.schedule(load_path)
    else
      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyLoad",
        callback = function(event)
          if event.data == name then
            load_path()
            return true
          end
        end,
      })
    end

    api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = load_path,
    })
  end

  config.update(opts)
  sidebar.setup()
end

return M
