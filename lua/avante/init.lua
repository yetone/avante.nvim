local M = {}
local sidebar = require("avante.sidebar")
local config = require("avante.config")

function M.setup(opts)
  require("tiktoken_lib").load()
  config.update(opts)
  sidebar.setup()
end

return M
