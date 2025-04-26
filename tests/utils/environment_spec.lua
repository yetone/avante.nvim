local environment = require("avante.utils.environment")

describe("environment", function()
  local original_system

  before_each(function()
    -- Clear the cache before each test
    environment.cache = {}
    -- Store original vim.system
    original_system = vim.system
  end)

  after_each(function()
    -- Restore original vim.system
    vim.system = original_system
  end)

  describe("parse", function()
    it("should read environment variables directly", function()
      vim.env.TEST_VAR = "test_value"
      assert.equals("test_value", environment.parse("TEST_VAR"))
      -- Should use cache on second call
      vim.env.TEST_VAR = "changed_value"
      assert.equals("test_value", environment.parse("TEST_VAR"))
    end)

    it("should execute commands and cache results", function()
      vim.system = function(cmd, opts, callback)
        assert.same(vim.split("echo hello", " "), cmd)
        callback({ code = 0, stdout = "hello\n", stderr = "" })
        return { wait = function() end }
      end

      local result = environment.parse("cmd:echo hello")
      assert.equals("hello", result)
      assert.equals("hello", environment.cache["cmd:echo hello"])
      -- Should use cache on second call
      assert.equals("hello", environment.parse("cmd:echo hello"))
    end)

    it("should handle command arrays", function()
      vim.system = function(cmd, opts, callback)
        assert.same({ "echo", "world" }, cmd)
        callback({ code = 0, stdout = "world\n", stderr = "" })
        return { wait = function() end }
      end

      local result = environment.parse({ "echo", "world" })
      assert.equals("world", result)
      assert.equals("world", environment.cache["echo__world"])
      -- Should use cache on second call using the concatenated key
      assert.equals("world", environment.parse({ "echo", "world" }))
    end)

    it("should force cache invalidation when requested", function()
      local call_count = 0
      vim.system = function(cmd, opts, callback)
        call_count = call_count + 1
        callback({ code = 0, stdout = "hello\n", stderr = "" })
        return { wait = function() end }
      end

      -- First call caches the value
      local result = environment.parse("cmd:echo hello")
      assert.equals("hello", result)
      assert.equals(1, call_count)

      -- Second call with force_cache_invalidate should run command again
      result = environment.parse("cmd:echo hello", nil, true)
      assert.equals("hello", result)
      assert.equals(2, call_count)

      -- Third call should use cache
      result = environment.parse("cmd:echo hello")
      assert.equals("hello", result)
      assert.equals(2, call_count)
    end)

    it("should use override when provided", function()
      vim.env.OVERRIDE_VAR = "override_value"
      -- The command should never be called when override is used
      vim.system = function(cmd, opts, callback)
        assert.fail("Command should not be called when override is used")
        return { wait = function() end }
      end

      local result = environment.parse("cmd:echo should_not_see_this", "OVERRIDE_VAR")
      assert.equals("override_value", result)
    end)

    it("should handle command failures gracefully", function()
      vim.system = function(cmd, opts, callback)
        callback({ code = 1, stdout = "", stderr = "command not found" })
        return { wait = function() end }
      end

      local result = environment.parse("cmd:nonexistent_command")
      assert.is_nil(result)
      assert.is_nil(environment.cache["cmd:nonexistent_command"])
    end)

    it("should handle nil input", function()
      assert.has_error(function()
        environment.parse(nil)
      end, "Requires key_name")
    end)
  end)
end)

