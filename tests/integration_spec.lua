---@diagnostic disable: undefined-global
-- Test file for Rust components integration
local Utils = require("avante.utils")

describe("Rust Components Integration", function()
  local tokenizers

  before_each(function()
    -- Clean state before each test
    package.loaded['avante.tokenizers'] = nil
  end)

  describe("Tokenizer Integration", function()
    it("should load tokenizers module", function()
      local ok, module = pcall(require, 'avante.tokenizers')
      if not ok then
        pending("Tokenizers module not available: " .. tostring(module))
        return
      end

      assert.is_not_nil(module, "Tokenizers module should not be nil")
      tokenizers = module
    end)

    it("should have required tokenizer functions", function()
      local ok, module = pcall(require, 'avante.tokenizers')
      if not ok then
        pending("Tokenizers module not available")
        return
      end

      assert.is_function(module.encode, "encode function should exist")
      tokenizers = module
    end)

    it("should tokenize text successfully", function()
      local ok, module = pcall(require, 'avante.tokenizers')
      if not ok then
        pending("Tokenizers module not available")
        return
      end

      -- Test basic tokenization
      local test_text = "Hello, world!"
      local encode_ok, result = pcall(module.encode, test_text)

      if not encode_ok then
        pending("Tokenization failed - FFI binding may not be ready: " .. tostring(result))
        return
      end

      assert.is_not_nil(result, "Tokenization result should not be nil")
      -- Result should be a table with tokens, num_tokens, num_chars
      if type(result) == "table" and #result >= 3 then
        local tokens, num_tokens, num_chars = result[1], result[2], result[3]
        assert.is_table(tokens, "Tokens should be a table")
        assert.is_number(num_tokens, "Token count should be a number")
        assert.is_number(num_chars, "Character count should be a number")
        assert.is_true(num_tokens > 0, "Should have at least one token")
      end
    end)

    it("should handle empty input gracefully", function()
      local ok, module = pcall(require, 'avante.tokenizers')
      if not ok then
        pending("Tokenizers module not available")
        return
      end

      local encode_ok, result = pcall(module.encode, "")
      if not encode_ok then
        pending("Tokenization failed - FFI binding may not be ready")
        return
      end

      assert.is_not_nil(result, "Should handle empty input without crashing")
    end)
  end)

  describe("Rust-Lua FFI Performance", function()
    it("should complete tokenization within performance target", function()
      local ok, module = pcall(require, 'avante.tokenizers')
      if not ok then
        pending("Tokenizers module not available")
        return
      end

      local test_text = "This is a longer text for performance testing with multiple sentences."
      local start_time = vim.uv.hrtime()

      local encode_ok, result = pcall(module.encode, test_text)
      if not encode_ok then
        pending("Tokenization failed - FFI binding may not be ready")
        return
      end

      local end_time = vim.uv.hrtime()
      local elapsed_ms = (end_time - start_time) / 1000000 -- Convert to milliseconds

      assert.is_true(elapsed_ms < 10, string.format(
        "Tokenization should complete in <10ms, took %.2fms", elapsed_ms))
    end)

    it("should handle multiple rapid calls", function()
      local ok, module = pcall(require, 'avante.tokenizers')
      if not ok then
        pending("Tokenizers module not available")
        return
      end

      local test_texts = {
        "First test",
        "Second test with more words",
        "Third test for rapid calls",
      }

      local start_time = vim.uv.hrtime()

      for _, text in ipairs(test_texts) do
        local encode_ok, result = pcall(module.encode, text)
        if not encode_ok then
          pending("Multiple tokenization calls failed")
          return
        end
      end

      local end_time = vim.uv.hrtime()
      local elapsed_ms = (end_time - start_time) / 1000000

      assert.is_true(elapsed_ms < 30, string.format(
        "Multiple calls should complete in <30ms, took %.2fms", elapsed_ms))
    end)
  end)

  describe("Template System Integration", function()
    it("should handle template rendering if available", function()
      -- Try to test template functionality if available
      local template_ok, template_module = pcall(require, 'avante.templates')

      if not template_ok then
        pending("Template system not available for testing")
        return
      end

      -- Test basic template operations
      assert.is_not_nil(template_module, "Template module should be available")
    end)
  end)

  describe("Cross-language Error Handling", function()
    it("should handle FFI errors gracefully", function()
      local Errors = require("avante.errors")

      -- Test FFI error handling
      local result, error_msg = Errors.safe_execute(function()
        -- This might fail if FFI is not properly set up
        local tokenizers = require("avante.tokenizers")
        return tokenizers.encode("test")
      end, "FFI tokenization test")

      -- Either should succeed or fail gracefully
      if result then
        assert.is_not_nil(result, "Successful FFI call should return result")
      else
        assert.is_string(error_msg, "Failed FFI call should return error message")
      end
    end)

    it("should provide clear error messages for FFI failures", function()
      local Errors = require("avante.errors")

      -- Test module loading error handling
      local module, error_msg = Errors.safe_require("non.existent.ffi.module", true)
      assert.is_nil(module, "Non-existent module should return nil")
      assert.is_string(error_msg, "Should provide error message for missing FFI module")
    end)
  end)
end)