---@diagnostic disable: undefined-global
-- Test file for basic plugin functionality
local Utils = require("avante.utils")

describe("Basic Plugin Functionality", function()
  local avante

  before_each(function()
    -- Clean state before each test
    package.loaded['avante'] = nil
    package.loaded['avante.config'] = nil
    package.loaded['avante.errors'] = nil
  end)

  describe("Module Loading", function()
    it("should load avante module without errors", function()
      local ok, module = pcall(require, 'avante')
      assert.is_true(ok, "Failed to load avante module: " .. tostring(module))
      assert.is_not_nil(module, "Avante module should not be nil")
      avante = module
    end)

    it("should load configuration module", function()
      local ok, config = pcall(require, 'avante.config')
      assert.is_true(ok, "Failed to load avante.config module")
      assert.is_not_nil(config, "Config module should not be nil")
      assert.is_table(config, "Config should be a table")
    end)

    it("should load error handling module", function()
      local ok, errors = pcall(require, 'avante.errors')
      assert.is_true(ok, "Failed to load avante.errors module")
      assert.is_not_nil(errors, "Errors module should not be nil")
      assert.is_function(errors.handle_error, "handle_error should be a function")
    end)
  end)

  describe("Plugin Initialization", function()
    it("should initialize with default configuration", function()
      local ok, module = pcall(require, 'avante')
      assert.is_true(ok, "Failed to load avante module")

      -- Test setup function exists
      assert.is_function(module.setup, "setup should be a function")

      -- Test setup with empty config
      local setup_ok = pcall(module.setup, {})
      assert.is_true(setup_ok, "Plugin should initialize with empty config")
    end)

    it("should have required functions", function()
      local ok, module = pcall(require, 'avante')
      assert.is_true(ok, "Failed to load avante module")

      -- Check for essential functions/properties
      assert.is_not_nil(module.setup, "setup function should exist")
      assert.is_not_nil(module.did_setup, "did_setup property should exist")
    end)

    it("should handle custom configuration", function()
      local ok, module = pcall(require, 'avante')
      assert.is_true(ok, "Failed to load avante module")

      local custom_config = {
        provider = "test_provider",
        debug = true
      }

      local setup_ok = pcall(module.setup, custom_config)
      assert.is_true(setup_ok, "Plugin should initialize with custom config")
    end)
  end)

  describe("Configuration System", function()
    it("should have default configuration", function()
      local Config = require("avante.config")
      assert.is_not_nil(Config._defaults, "Default configuration should exist")
      assert.is_table(Config._defaults, "Default configuration should be a table")

      -- Check for essential default values
      assert.is_not_nil(Config._defaults.provider, "Default provider should be set")
      assert.is_boolean(Config._defaults.debug, "Debug should be a boolean")
    end)

    it("should validate configuration", function()
      local Errors = require("avante.errors")

      -- Test configuration validation
      local valid_config = {
        provider = "openai",
        debug = false,
        timeout = 30000
      }

      local schema = {
        provider = { type = "string", required = true },
        debug = { type = "boolean", required = false },
        timeout = { type = "number", required = false }
      }

      local is_valid, error_msg = Errors.validate_config(valid_config, schema)
      assert.is_true(is_valid, "Valid configuration should pass validation: " .. (error_msg or ""))
    end)
  end)

  describe("Error Handling", function()
    it("should handle errors gracefully", function()
      local Errors = require("avante.errors")

      -- Test error handling doesn't crash
      local ok = pcall(Errors.handle_error, "Test error", { test = true })
      assert.is_true(ok, "Error handling should not crash")
    end)

    it("should validate input types", function()
      local Errors = require("avante.errors")

      local is_valid, error_msg = Errors.validate_input("test", "string")
      assert.is_true(is_valid, "String input should be valid")

      local is_invalid, _ = Errors.validate_input("test", "number")
      assert.is_false(is_invalid, "String input should be invalid for number type")
    end)

    it("should safely require modules", function()
      local Errors = require("avante.errors")

      -- Test existing module
      local module, err = Errors.safe_require("avante.config")
      assert.is_not_nil(module, "Should successfully load existing module")
      assert.is_nil(err, "Should not return error for existing module")

      -- Test non-existing module
      local missing_module, missing_err = Errors.safe_require("non.existing.module", true)
      assert.is_nil(missing_module, "Should return nil for missing module")
      assert.is_string(missing_err, "Should return error message for missing module")
    end)
  end)
end)