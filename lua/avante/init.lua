local M = {}
local sidebar = require("avante.sidebar")
local config = require("avante.config")

function M.setup(opts)
  config.update(opts)
  sidebar.setup()
end

return M
