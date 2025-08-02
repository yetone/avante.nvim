local Utils = require("avante.utils")

describe("Utils notification system", function()
  describe("M.notify", function()
    it("should handle nil message gracefully", function()
      -- This test should not crash
      assert.has_no.errors(function() Utils.notify(nil) end)
    end)

    it("should handle empty string message", function()
      assert.has_no.errors(function() Utils.notify("") end)
    end)

    it("should handle string message", function()
      assert.has_no.errors(function() Utils.notify("test message") end)
    end)

    it("should handle table message with valid strings", function()
      assert.has_no.errors(function() Utils.notify({ "line1", "line2", "line3" }) end)
    end)

    it("should handle table message with nil values", function()
      -- This is the critical test case that currently fails
      assert.has_no.errors(function() Utils.notify({ "line1", nil, "line3" }) end)
    end)

    it("should handle table message with all nil values", function()
      assert.has_no.errors(function() Utils.notify({ nil, nil, nil }) end)
    end)

    it("should handle empty table message", function()
      assert.has_no.errors(function() Utils.notify({}) end)
    end)

    it("should handle mixed type table message", function()
      assert.has_no.errors(function() Utils.notify({ "string", 123, true, nil, "another" }) end)
    end)

    it("should handle number message", function()
      assert.has_no.errors(function() Utils.notify(123) end)
    end)

    it("should handle boolean message", function()
      assert.has_no.errors(function() Utils.notify(true) end)
      assert.has_no.errors(function() Utils.notify(false) end)
    end)

    it("should handle function message", function()
      assert.has_no.errors(function() Utils.notify(function() return "test" end) end)
    end)
  end)

  describe("M.error", function()
    it("should handle nil message gracefully", function()
      assert.has_no.errors(function() Utils.error(nil) end)
    end)

    it("should handle table with nil values", function()
      assert.has_no.errors(function() Utils.error({ "error:", nil, "details" }) end)
    end)
  end)

  describe("M.info", function()
    it("should handle nil message gracefully", function()
      assert.has_no.errors(function() Utils.info(nil) end)
    end)

    it("should handle table with nil values", function()
      assert.has_no.errors(function() Utils.info({ "info:", nil, "details" }) end)
    end)
  end)

  describe("M.warn", function()
    it("should handle nil message gracefully", function()
      assert.has_no.errors(function() Utils.warn(nil) end)
    end)

    it("should handle table with nil values", function()
      assert.has_no.errors(function() Utils.warn({ "warning:", nil, "details" }) end)
    end)
  end)

  describe("M.debug", function()
    it("should handle nil message gracefully", function()
      -- Note: debug function has different behavior based on config.debug
      assert.has_no.errors(function() Utils.debug(nil) end)
    end)

    it("should handle multiple nil arguments", function()
      assert.has_no.errors(function() Utils.debug(nil, nil, nil) end)
    end)
  end)
end)