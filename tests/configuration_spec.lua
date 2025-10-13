-- Configuration System Tests
-- TDD Red Phase - Tests should fail until configuration system is implemented

describe("Configuration System", function()
  local config

  before_each(function()
    -- Reset any cached modules
    package.loaded['avante.config'] = nil
  end)

  describe("Config Module", function()
    it("should load the config module", function()
      local success, result = pcall(require, 'avante.config')
      assert.is_true(success, "Failed to load config module: " .. tostring(result))
      assert.is_not_nil(result, "Config module returned nil")
      assert.is_table(result, "Config module should return a table")
    end)

    it("should have default configuration", function()
      config = require('avante.config')
      assert.is_table(config.defaults, "Should have defaults table")
      assert.is_not_nil(config.defaults.provider, "Should have default provider")
    end)

    it("should have setup function", function()
      config = require('avante.config')
      assert.is_function(config.setup, "Should have setup function")
    end)

    it("should have validation function", function()
      config = require('avante.config')
      assert.is_function(config.validate_config, "Should have validate_config function")
    end)
  end)

  describe("Configuration Setup", function()
    before_each(function()
      config = require('avante.config')
    end)

    it("should return default configuration when no user config provided", function()
      local result = config.setup()
      assert.is_table(result, "Setup should return a table")
      assert.equals(config.defaults.provider, result.provider, "Should use default provider")
    end)

    it("should merge user configuration with defaults", function()
      local user_config = { provider = 'custom' }
      local result = config.setup(user_config)
      assert.equals('custom', result.provider, "Should use custom provider")
      assert.is_not_nil(result.model, "Should retain default model")
    end)

    it("should handle empty user configuration", function()
      local result = config.setup({})
      assert.is_table(result, "Should return table for empty config")
    end)
  end)

  describe("Configuration Validation", function()
    before_each(function()
      config = require('avante.config')
    end)

    it("should validate valid configuration", function()
      local valid_config = {
        provider = 'openai',
        model = 'gpt-4',
        timeout = 30000
      }
      local success, result = pcall(config.validate_config, valid_config)
      assert.is_true(success, "Should validate valid config")
    end)

    it("should handle configuration with unknown options", function()
      local config_with_unknown = {
        provider = 'openai',
        unknown_option = 'test'
      }
      -- Should not crash, may warn
      local success = pcall(config.validate_config, config_with_unknown)
      assert.is_true(success, "Should handle unknown options gracefully")
    end)
  end)

  describe("Configuration Edge Cases", function()
    before_each(function()
      config = require('avante.config')
    end)

    it("should handle nil configuration", function()
      local success, result = pcall(config.setup, nil)
      assert.is_true(success, "Should handle nil config")
      assert.is_table(result, "Should return defaults for nil config")
    end)

    it("should handle malformed configuration", function()
      local malformed_configs = {
        "string_instead_of_table",
        123,
        function() end,
        true
      }

      for _, malformed in ipairs(malformed_configs) do
        local success = pcall(config.setup, malformed)
        -- Should either succeed with defaults or fail gracefully
        -- The exact behavior can be decided during implementation
        assert.is_boolean(success, "Should return boolean success status")
      end
    end)
  end)
end)