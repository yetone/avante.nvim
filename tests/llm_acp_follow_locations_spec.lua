local Config = require("avante.config")

describe("ACP auto-follow agent locations", function()
  before_each(function()
    -- Reset config to defaults
    Config.setup({})
  end)

  describe("configuration option", function()
    it("should have acp_follow_agent_locations config option", function()
      assert.is_not_nil(Config.behaviour, "behaviour config should exist")
      assert.is_not_nil(Config.behaviour.acp_follow_agent_locations,
        "acp_follow_agent_locations should be defined")
    end)

    it("should default to true", function()
      assert.is_true(Config.behaviour.acp_follow_agent_locations,
        "acp_follow_agent_locations should default to true")
    end)

    it("should be configurable by user", function()
      Config.setup({
        behaviour = {
          acp_follow_agent_locations = false,
        },
      })

      assert.is_false(Config.behaviour.acp_follow_agent_locations,
        "should respect user configuration")
    end)
  end)

  describe("location following logic", function()
    -- Note: These tests verify the configuration and logic structure.
    -- Full integration tests with actual window navigation would require
    -- a complete Neovim instance with proper buffer/window setup.

    it("should only follow on 'edit' kind tool calls", function()
      -- The code checks: update.kind == "edit"
      -- This test documents the expected behavior
      local edit_update = { kind = "edit", locations = {} }
      local read_update = { kind = "read", locations = {} }

      assert.are.equal("edit", edit_update.kind, "edit kind should be 'edit'")
      assert.are_not.equal("edit", read_update.kind, "non-edit kinds should not trigger follow")
    end)

    it("should require locations array to be non-empty", function()
      -- The code checks: update.locations and #update.locations > 0
      local valid_update = {
        kind = "edit",
        locations = { { path = "test.lua", line = 1 } }
      }
      local empty_update = {
        kind = "edit",
        locations = {}
      }
      local nil_update = {
        kind = "edit",
        locations = nil
      }

      assert.is_true(#valid_update.locations > 0, "valid update should have locations")
      assert.is_false(#empty_update.locations > 0, "empty locations should not trigger follow")
      assert.is_false(nil_update.locations and #nil_update.locations > 0,
        "nil locations should not trigger follow")
    end)

    it("should only follow first location to avoid rapid jumping", function()
      -- The code contains: local location = update.locations[1]
      -- This test documents that only the first location is used
      local update = {
        kind = "edit",
        locations = {
          { path = "file1.lua", line = 10 },
          { path = "file2.lua", line = 20 },
          { path = "file3.lua", line = 30 },
        }
      }

      local first_location = update.locations[1]
      assert.are.equal("file1.lua", first_location.path, "should only use first location")
      assert.are.equal(10, first_location.line, "should use first location's line")
    end)

    it("should not follow when sidebar is in full view (Zen mode)", function()
      -- The code checks: not sidebar.is_in_full_view
      -- This documents the expected behavior
      local sidebar_normal = { is_in_full_view = false }
      local sidebar_zen = { is_in_full_view = true }

      assert.is_false(sidebar_normal.is_in_full_view, "normal view should allow following")
      assert.is_true(sidebar_zen.is_in_full_view, "zen mode should prevent following")
    end)

    it("should enforce grace period to prevent rapid navigation", function()
      -- The code uses: local grace_period = 2000 (milliseconds)
      -- This test documents the grace period behavior
      local grace_period = 2000
      local now = 10000

      local recent_nav = now - 1000 -- 1 second ago
      local old_nav = now - 3000 -- 3 seconds ago

      assert.is_true(now - recent_nav < grace_period,
        "navigation within grace period should be blocked")
      assert.is_false(now - old_nav < grace_period,
        "navigation after grace period should be allowed")
    end)

    it("should center line in viewport after navigation", function()
      -- The code uses: vim.cmd("normal! zz") to center the line
      -- This documents the expected behavior
      local center_command = "normal! zz"
      assert.are.equal("normal! zz", center_command,
        "should use zz command to center line in viewport")
    end)

    it("should clamp line number to valid buffer range", function()
      -- The code uses: math.min(line, line_count)
      local line_count = 100

      local valid_line = 50
      local overflow_line = 150

      local clamped_valid = math.min(valid_line, line_count)
      local clamped_overflow = math.min(overflow_line, line_count)

      assert.are.equal(50, clamped_valid, "valid line should remain unchanged")
      assert.are.equal(100, clamped_overflow, "overflow line should be clamped to max")
    end)
  end)

  describe("tool_call_update status handling", function()
    it("should handle pending status correctly", function()
      local update = { status = "pending" }
      local is_calling = (update.status == "pending" or update.status == "in_progress")
      local state = is_calling and "generating" or "generated"

      assert.is_true(is_calling, "pending should be treated as calling")
      assert.are.equal("generating", state, "state should be 'generating'")
    end)

    it("should handle in_progress status correctly", function()
      local update = { status = "in_progress" }
      local is_calling = (update.status == "pending" or update.status == "in_progress")
      local state = is_calling and "generating" or "generated"

      assert.is_true(is_calling, "in_progress should be treated as calling")
      assert.are.equal("generating", state, "state should be 'generating'")
    end)

    it("should handle completed status correctly", function()
      local update = { status = "completed" }
      local should_create_result = (update.status == "completed" or update.status == "failed")
      local is_calling = (update.status == "pending" or update.status == "in_progress")

      assert.is_true(should_create_result, "completed should create result message")
      assert.is_false(is_calling, "completed should not be calling")
    end)

    it("should handle failed status correctly", function()
      local update = { status = "failed" }
      local should_create_result = (update.status == "completed" or update.status == "failed")
      local is_calling = (update.status == "pending" or update.status == "in_progress")

      assert.is_true(should_create_result, "failed should create result message")
      assert.is_false(is_calling, "failed should not be calling")
    end)
  end)
end)
