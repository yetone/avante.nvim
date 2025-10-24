-- test-b: Requirements Gathering and PRD Management System
-- Main module initialization

local M = {}

-- Import submodules
M.project = require("test_b.project")
M.stakeholder = require("test_b.stakeholder")
M.requirement = require("test_b.requirement")
M.technical = require("test_b.technical")
M.risk = require("test_b.risk")
M.prd_workflow = require("test_b.prd_workflow")
M.storage = require("test_b.storage")

-- Module version
M.version = "0.1.0"

-- Setup function for initialization
function M.setup(opts)
  opts = opts or {}

  -- Initialize storage system
  M.storage.init(opts.storage_path or ".something/data")

  return M
end

return M
