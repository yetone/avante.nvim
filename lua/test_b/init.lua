-- test-b Main Module
-- Requirements gathering and PRD management plugin for Neovim

local M = {}

-- Submodules
M.project = require("test_b.project")
M.stakeholder = require("test_b.stakeholder")
M.requirement = require("test_b.requirement")
M.technical = require("test_b.technical")
M.risk = require("test_b.risk")
M.prd_workflow = require("test_b.prd_workflow")
M.storage = require("test_b.storage")
M.uuid = require("test_b.uuid")

-- Plugin version
M.version = "1.0.0"

-- Setup function for plugin initialization
-- @param opts table Optional configuration options
function M.setup(opts)
  opts = opts or {}

  -- Ensure data directory exists
  local data_dir = M.storage.get_data_dir()
  vim.fn.mkdir(data_dir, "p")

  -- Initialize any additional configuration here
  -- For now, the plugin is primarily a library of modules

  return M
end

return M
