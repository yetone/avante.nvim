---@diagnostic disable: undefined-global
-- Test file for error handling and edge cases

describe("Error Handling and Edge Cases", function()
  local Errors

  before_each(function()
    -- Reload errors module for clean state
    package.loaded['avante.errors'] = nil
    Errors = require("avante.errors")
  end)

  describe("Error Module Loading", function()
    it("should load errors module successfully", function()
      local ok, module = pcall(require, 'avante.errors')
      assert.is_true(ok, "Should load errors module without issues")
      assert.is_not_nil(module, "Errors module should not be nil")
    end)

    it("should have all required functions", function()
      assert.is_function(Errors.handle_error, "handle_error should be a function")
      assert.is_function(Errors.validate_input, "validate_input should be a function")
      assert.is_function(Errors.validate_config, "validate_config should be a function")
      assert.is_function(Errors.safe_require, "safe_require should be a function")
      assert.is_function(Errors.safe_execute, "safe_execute should be a function")
    end)
  end)

  describe("Input Validation", function()
    it("should validate correct input types", function()
      local is_valid, error_msg = Errors.validate_input("test", "string")
      assert.is_true(is_valid, "String input should be valid")
      assert.is_nil(error_msg, "No error message for valid input")

      is_valid, error_msg = Errors.validate_input(42, "number")
      assert.is_true(is_valid, "Number input should be valid")
      assert.is_nil(error_msg, "No error message for valid number")

      is_valid, error_msg = Errors.validate_input({}, "table")
      assert.is_true(is_valid, "Table input should be valid")
      assert.is_nil(error_msg, "No error message for valid table")
    end)

    it("should reject incorrect input types", function()
      local is_valid, error_msg = Errors.validate_input("test", "number")
      assert.is_false(is_valid, "String should be invalid for number type")
      assert.is_string(error_msg, "Should provide error message for invalid input")

      is_valid, error_msg = Errors.validate_input(42, "string")
      assert.is_false(is_valid, "Number should be invalid for string type")
      assert.is_string(error_msg, "Should provide error message for invalid input")
    end)

    it("should handle nil inputs appropriately", function()
      local is_valid, error_msg = Errors.validate_input(nil, "string")
      assert.is_false(is_valid, "nil should be invalid for string type")
      assert.is_string(error_msg, "Should provide error message for nil input")
    end)
  end)

  describe("Configuration Validation", function()
    it("should validate correct configuration", function()
      local config = {
        provider = "openai",
        debug = false,
        timeout = 30000
      }

      local schema = {
        provider = { type = "string", required = true },
        debug = { type = "boolean", required = false },
        timeout = { type = "number", required = false }
      }

      local is_valid, error_msg = Errors.validate_config(config, schema)
      assert.is_true(is_valid, "Valid configuration should pass validation")
      assert.is_nil(error_msg, "No error message for valid configuration")
    end)

    it("should reject missing required fields", function()
      local config = {
        debug = false -- missing required 'provider'
      }

      local schema = {
        provider = { type = "string", required = true },
        debug = { type = "boolean", required = false }
      }

      local is_valid, error_msg = Errors.validate_config(config, schema)
      assert.is_false(is_valid, "Should reject config with missing required field")
      assert.is_string(error_msg, "Should provide error message for missing field")
      assert.truthy(string.find(error_msg:lower(), "required"), "Error should mention required field")
    end)

    it("should reject incorrect field types", function()
      local config = {
        provider = "openai",
        debug = "not_a_boolean" -- wrong type
      }

      local schema = {
        provider = { type = "string", required = true },
        debug = { type = "boolean", required = false }
      }

      local is_valid, error_msg = Errors.validate_config(config, schema)
      assert.is_false(is_valid, "Should reject config with wrong field types")
      assert.is_string(error_msg, "Should provide error message for wrong type")
    end)
  end)

  describe("Safe Module Loading", function()
    it("should load existing modules successfully", function()
      local module, error_msg = Errors.safe_require("avante.config")
      assert.is_not_nil(module, "Should successfully load existing module")
      assert.is_nil(error_msg, "Should not return error for existing module")
    end)

    it("should handle missing modules gracefully", function()
      local module, error_msg = Errors.safe_require("non.existent.module", true)
      assert.is_nil(module, "Should return nil for missing module")
      assert.is_string(error_msg, "Should return error message for missing module")
    end)

    it("should report non-optional missing modules", function()
      -- This test might generate vim.notify calls, which is expected
      local module, error_msg = Errors.safe_require("definitely.does.not.exist.module")
      assert.is_nil(module, "Should return nil for missing module")
      assert.is_string(error_msg, "Should return error message")
    end)
  end)

  describe("Safe Function Execution", function()
    it("should execute successful functions", function()
      local result, error_msg = Errors.safe_execute(function()
        return "success"
      end, "test operation")

      assert.is_equal("success", result, "Should return function result")
      assert.is_nil(error_msg, "Should not return error for successful function")
    end)

    it("should handle function errors gracefully", function()
      local result, error_msg = Errors.safe_execute(function()
        error("intentional error")
      end, "test operation")

      assert.is_nil(result, "Should return nil for failed function")
      assert.is_string(error_msg, "Should return error message for failed function")
    end)

    it("should handle functions that return nil", function()
      local result, error_msg = Errors.safe_execute(function()
        return nil
      end, "test operation")

      assert.is_nil(result, "Should return nil when function returns nil")
      assert.is_nil(error_msg, "Should not return error for function that returns nil")
    end)
  end)

  describe("Error Object Creation", function()
    it("should create error objects correctly", function()
      local error_obj = Errors.create_error("test message", Errors.CODES.VALIDATION_ERROR, { test = true })

      assert.is_table(error_obj, "Should return error object as table")
      assert.is_equal("test message", error_obj.message, "Should set correct message")
      assert.is_equal(Errors.CODES.VALIDATION_ERROR, error_obj.code, "Should set correct error code")
      assert.is_table(error_obj.context, "Should include context")
    end)

    it("should use default error code when not provided", function()
      local error_obj = Errors.create_error("test message")

      assert.is_equal(Errors.CODES.UNKNOWN_ERROR, error_obj.code, "Should use default error code")
    end)
  end)

  describe("Edge Cases", function()
    it("should handle nil error input to handle_error", function()
      local ok = pcall(Errors.handle_error, nil)
      assert.is_true(ok, "Should handle nil error input without crashing")
    end)

    it("should handle empty string validation", function()
      local is_valid, error_msg = Errors.validate_input("", "string")
      assert.is_true(is_valid, "Empty string should be valid for string type")
    end)

    it("should handle empty table validation", function()
      local is_valid, error_msg = Errors.validate_input({}, "table")
      assert.is_true(is_valid, "Empty table should be valid for table type")
    end)

    it("should handle malformed configuration gracefully", function()
      -- Test with non-table config
      local is_valid, error_msg = Errors.validate_config("not a table", {})
      assert.is_false(is_valid, "Should reject non-table configuration")
      assert.is_string(error_msg, "Should provide error message for non-table config")
    end)
  end)
end)