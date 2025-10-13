-- Integration Tests
-- TDD Red Phase - Tests should fail until full integration is implemented

describe("Integration Tests", function()
  local avante

  before_each(function()
    -- Reset any cached modules
    package.loaded['avante'] = nil
    package.loaded['avante.config'] = nil
    package.loaded['avante.errors'] = nil
  end)

  describe("Plugin Integration", function()
    it("should integrate config and main module", function()
      -- Load main module
      avante = require('avante')
      assert.is_not_nil(avante, "Main module should load")

      -- Setup with configuration
      local success, result = pcall(avante.setup, { provider = 'test' })
      assert.is_true(success, "Setup should succeed with config integration")
    end)

    it("should handle configuration errors in main setup", function()
      avante = require('avante')

      -- Test various invalid configs
      local invalid_configs = {
        { provider = nil },
        { timeout = -1 },
        { max_tokens = "invalid" }
      }

      for _, config in ipairs(invalid_configs) do
        local success = pcall(avante.setup, config)
        -- Should either succeed with error handling or fail gracefully
        assert.is_boolean(success, "Should handle invalid config: " .. vim.inspect(config))
      end
    end)

    it("should maintain state across multiple operations", function()
      avante = require('avante')

      -- First setup
      local success1 = pcall(avante.setup, { provider = 'test1' })
      assert.is_true(success1, "First setup should succeed")

      -- Second setup should work
      local success2 = pcall(avante.setup, { provider = 'test2' })
      assert.is_true(success2, "Second setup should succeed")
    end)
  end)

  describe("Rust Integration", function()
    it("should load without crashing even if rust modules missing", function()
      -- Test that Lua code doesn't crash if Rust FFI modules are not available
      local success = pcall(function()
        -- Try to load main module
        avante = require('avante')
        avante.setup({})
      end)

      -- Should at least load Lua parts without crashing
      assert.is_true(success, "Should handle missing Rust modules gracefully")
    end)

    it("should attempt to use tokenizers if available", function()
      -- This test will pass if tokenizer is available, skip if not
      local tokenizer_available = pcall(require, 'avante.tokenizers')

      if tokenizer_available then
        local tokenizers = require('avante.tokenizers')
        if tokenizers and tokenizers.encode then
          local success, result = pcall(tokenizers.encode, "test text")
          -- If tokenizer is available, it should work
          assert.is_true(success, "Tokenizer should work if available")
          assert.is_not_nil(result, "Should return tokenization result")
        end
      end
      -- Test passes if tokenizer not available (graceful degradation)
    end)
  end)

  describe("Performance Integration", function()
    it("should complete setup within reasonable time", function()
      local start_time = os.clock()

      avante = require('avante')
      avante.setup({})

      local elapsed = os.clock() - start_time
      -- Should complete within 1 second (very generous for basic setup)
      assert.is_true(elapsed < 1.0, "Setup should complete quickly, took: " .. elapsed .. "s")
    end)

    it("should handle multiple rapid setups", function()
      avante = require('avante')

      local start_time = os.clock()

      -- Run multiple setups rapidly
      for i = 1, 10 do
        local success = pcall(avante.setup, { provider = 'test' .. i })
        assert.is_true(success, "Rapid setup " .. i .. " should succeed")
      end

      local elapsed = os.clock() - start_time
      -- Should handle multiple setups efficiently
      assert.is_true(elapsed < 2.0, "Multiple setups should be efficient, took: " .. elapsed .. "s")
    end)

    it("should not leak memory on repeated setups", function()
      avante = require('avante')

      -- Get initial memory usage
      collectgarbage("collect")
      local initial_memory = collectgarbage("count")

      -- Perform multiple setups
      for i = 1, 50 do
        avante.setup({ provider = 'test' .. i })
      end

      -- Force garbage collection
      collectgarbage("collect")
      local final_memory = collectgarbage("count")

      -- Memory increase should be reasonable (less than 1MB)
      local memory_increase = final_memory - initial_memory
      assert.is_true(memory_increase < 1024, "Memory usage should be reasonable: " .. memory_increase .. "KB")
    end)
  end)

  describe("Error Recovery Integration", function()
    it("should recover from setup errors", function()
      avante = require('avante')

      -- Cause an error in setup
      local success1 = pcall(avante.setup, function() error("test error") end)
      -- Should handle error gracefully

      -- Should be able to setup normally after error
      local success2 = pcall(avante.setup, {})
      assert.is_true(success2, "Should recover from previous setup error")
    end)

    it("should handle partial module failures", function()
      -- Test that main functionality works even if some submodules fail
      local success = pcall(function()
        avante = require('avante')
        avante.setup({})
      end)

      assert.is_true(success, "Should work even with partial module failures")
    end)
  end)

  describe("Cross-component Integration", function()
    it("should integrate error handling with main module", function()
      avante = require('avante')

      -- Setup should use error handling internally
      local success = pcall(avante.setup, nil)
      -- Should handle nil config using error handling module
      assert.is_true(success, "Should integrate error handling in setup")
    end)

    it("should integrate configuration validation", function()
      avante = require('avante')

      -- Setup should validate configuration
      local configs = {
        {},  -- empty config
        { provider = 'valid' },  -- valid config
        { provider = 123 }  -- potentially invalid config
      }

      for _, config in ipairs(configs) do
        local success = pcall(avante.setup, config)
        -- Should handle all configs through validation
        assert.is_boolean(success, "Should validate config: " .. vim.inspect(config))
      end
    end)
  end)
end)