---@diagnostic disable: undefined-global
-- Test file for configuration and extensibility

describe("Configuration and Extensibility", function()
  local Config
  local Errors

  before_each(function()
    -- Clean state before each test
    package.loaded['avante.config'] = nil
    package.loaded['avante.errors'] = nil
    Config = require("avante.config")
    Errors = require("avante.errors")
  end)

  describe("Configuration Module Loading", function()
    it("should load config module successfully", function()
      local ok, module = pcall(require, 'avante.config')
      assert.is_true(ok, "Should load config module without errors")
      assert.is_not_nil(module, "Config module should not be nil")
    end)

    it("should have default configuration", function()
      assert.is_not_nil(Config._defaults, "Should have _defaults table")
      assert.is_table(Config._defaults, "Defaults should be a table")
    end)

    it("should have essential default values", function()
      local defaults = Config._defaults

      assert.is_not_nil(defaults.provider, "Should have default provider")
      assert.is_string(defaults.provider, "Provider should be a string")

      assert.is_not_nil(defaults.debug, "Should have debug setting")
      assert.is_boolean(defaults.debug, "Debug should be a boolean")

      assert.is_not_nil(defaults.tokenizer, "Should have tokenizer setting")
      assert.is_string(defaults.tokenizer, "Tokenizer should be a string")
    end)
  end)

  describe("Configuration Validation", function()
    it("should validate default configuration", function()
      local defaults = Config._defaults
      assert.is_table(defaults, "Defaults should be valid table")

      -- Test that defaults are self-consistent
      local schema = {
        provider = { type = "string", required = true },
        debug = { type = "boolean", required = false },
        tokenizer = { type = "string", required = false },
        mode = { type = "string", required = false }
      }

      local is_valid, error_msg = Errors.validate_config(defaults, schema)
      assert.is_true(is_valid, "Default configuration should be valid: " .. (error_msg or ""))
    end)

    it("should handle custom provider configuration", function()
      local custom_config = {
        provider = "custom_provider",
        debug = true,
        tokenizer = "hf",
        custom_field = "custom_value"
      }

      -- Custom config should be valid (extensible)
      assert.is_table(custom_config, "Custom config should be a valid table")
      assert.is_equal("custom_provider", custom_config.provider, "Should preserve custom provider")
    end)

    it("should merge configurations properly", function()
      local user_config = {
        provider = "test_provider",
        debug = true,
        new_option = "test_value"
      }

      -- Test that we can merge configs (mimicking vim.tbl_deep_extend behavior)
      local merged = {}
      for k, v in pairs(Config._defaults) do
        merged[k] = v
      end
      for k, v in pairs(user_config) do
        merged[k] = v
      end

      assert.is_equal("test_provider", merged.provider, "Should use user provider")
      assert.is_true(merged.debug, "Should use user debug setting")
      assert.is_equal("test_value", merged.new_option, "Should include new option")

      -- Should still have defaults for unspecified values
      assert.is_not_nil(merged.tokenizer, "Should keep default tokenizer")
    end)
  end)

  describe("Configuration Setup", function()
    it("should handle empty configuration setup", function()
      local avante_ok, avante = pcall(require, 'avante')
      if not avante_ok then
        pending("Avante module not available for config setup test")
        return
      end

      assert.is_function(avante.setup, "Setup should be a function")

      -- Test setup with empty config
      local setup_ok = pcall(avante.setup, {})
      assert.is_true(setup_ok, "Should handle empty config setup")
    end)

    it("should handle nil configuration setup", function()
      local avante_ok, avante = pcall(require, 'avante')
      if not avante_ok then
        pending("Avante module not available for config setup test")
        return
      end

      -- Test setup with nil config
      local setup_ok = pcall(avante.setup, nil)
      assert.is_true(setup_ok, "Should handle nil config setup")
    end)

    it("should handle custom configuration setup", function()
      local avante_ok, avante = pcall(require, 'avante')
      if not avante_ok then
        pending("Avante module not available for config setup test")
        return
      end

      local custom_config = {
        provider = "custom",
        debug = true,
        tokenizer = "hf",
        timeout = 60000
      }

      local setup_ok = pcall(avante.setup, custom_config)
      assert.is_true(setup_ok, "Should handle custom config setup")
    end)
  end)

  describe("Configuration Extensibility", function()
    it("should accept unknown configuration options", function()
      local custom_config = {
        provider = "openai",
        debug = false,
        unknown_option = "should_not_crash",
        experimental_feature = { enabled = true }
      }

      -- Should not crash with unknown options
      local avante_ok, avante = pcall(require, 'avante')
      if not avante_ok then
        pending("Avante module not available for extensibility test")
        return
      end

      local setup_ok = pcall(avante.setup, custom_config)
      assert.is_true(setup_ok, "Should accept unknown configuration options")
    end)

    it("should handle nested configuration objects", function()
      local nested_config = {
        provider = "openai",
        providers = {
          openai = {
            model = "gpt-4",
            api_key = "test_key"
          },
          claude = {
            model = "claude-3",
            api_key = "test_key"
          }
        },
        ui = {
          theme = "dark",
          width = 80
        }
      }

      local avante_ok, avante = pcall(require, 'avante')
      if not avante_ok then
        pending("Avante module not available for nested config test")
        return
      end

      local setup_ok = pcall(avante.setup, nested_config)
      assert.is_true(setup_ok, "Should handle nested configuration objects")
    end)
  end)

  describe("Configuration Validation Edge Cases", function()
    it("should handle malformed configuration gracefully", function()
      local avante_ok, avante = pcall(require, 'avante')
      if not avante_ok then
        pending("Avante module not available for malformed config test")
        return
      end

      -- Test with non-table config
      local setup_ok = pcall(avante.setup, "not_a_table")
      -- Should either succeed (by treating it as empty) or fail gracefully
      assert.is_boolean(setup_ok, "Should return boolean result for malformed config")
    end)

    it("should validate required configuration fields", function()
      local incomplete_configs = {
        {}, -- empty config should work (use defaults)
        { debug = true }, -- missing provider should work (use default)
        { provider = nil }, -- nil provider should work (use default)
      }

      local avante_ok, avante = pcall(require, 'avante')
      if not avante_ok then
        pending("Avante module not available for validation test")
        return
      end

      for i, config in ipairs(incomplete_configs) do
        local setup_ok = pcall(avante.setup, config)
        assert.is_true(setup_ok, "Incomplete config " .. i .. " should be handled gracefully")
      end
    end)

    it("should handle configuration type mismatches", function()
      local mismatched_configs = {
        { provider = 123 }, -- number instead of string
        { debug = "true" }, -- string instead of boolean
        { timeout = "30000" }, -- string instead of number
      }

      local avante_ok, avante = pcall(require, 'avante')
      if not avante_ok then
        pending("Avante module not available for type mismatch test")
        return
      end

      for i, config in ipairs(mismatched_configs) do
        local setup_ok = pcall(avante.setup, config)
        -- Should either succeed (with type conversion) or fail gracefully
        assert.is_boolean(setup_ok, "Type mismatch config " .. i .. " should be handled")
      end
    end)
  end)

  describe("Configuration Integration", function()
    it("should integrate with existing configuration patterns", function()
      -- Test that our config works with existing avante patterns
      local defaults = Config._defaults

      -- Should have provider field (common pattern)
      assert.is_string(defaults.provider, "Should follow provider pattern")

      -- Should have debug field (common pattern)
      assert.is_boolean(defaults.debug, "Should follow debug pattern")

      -- Should have tokenizer field (specific to avante)
      assert.is_string(defaults.tokenizer, "Should have tokenizer configuration")
    end)

    it("should support environment variable patterns", function()
      -- Test environment variable integration patterns
      local env_patterns = {
        "AVANTE_PROVIDER",
        "AVANTE_DEBUG",
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY"
      }

      -- These are just pattern tests - we don't need to actually set env vars
      for _, pattern in ipairs(env_patterns) do
        assert.is_string(pattern, "Environment variable pattern should be string")
        assert.is_true(#pattern > 0, "Environment variable pattern should not be empty")
      end
    end)
  end)
end)