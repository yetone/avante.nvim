-- Basic Plugin Functionality Tests
-- TDD Red Phase - Tests should fail until implementation is added

describe("Basic Plugin Functionality", function()
  local avante

  before_each(function()
    -- Reset any cached modules
    package.loaded['avante'] = nil
    package.loaded['avante.init'] = nil
  end)

  describe("Plugin Loading", function()
    it("should load the main avante module without errors", function()
      local success, result = pcall(require, 'avante')
      assert.is_true(success, "Failed to load avante module: " .. tostring(result))
      assert.is_not_nil(result, "Module returned nil")
      assert.is_table(result, "Module should return a table")
    end)

    it("should have a setup function", function()
      avante = require('avante')
      assert.is_function(avante.setup, "Module should have a setup function")
    end)
  end)

  describe("Plugin Setup", function()
    before_each(function()
      avante = require('avante')
    end)

    it("should initialize with empty configuration", function()
      local success, result = pcall(avante.setup, {})
      assert.is_true(success, "Setup should succeed with empty config")
      assert.is_not_nil(result, "Setup should return a value")
    end)

    it("should initialize without any configuration", function()
      local success, result = pcall(avante.setup)
      assert.is_true(success, "Setup should succeed with no config")
    end)

    it("should handle nil configuration gracefully", function()
      local success, result = pcall(avante.setup, nil)
      assert.is_true(success, "Setup should handle nil config gracefully")
    end)
  end)

  describe("Error Handling", function()
    before_each(function()
      avante = require('avante')
    end)

    it("should not crash when setup is called multiple times", function()
      local success1 = pcall(avante.setup, {})
      local success2 = pcall(avante.setup, {})
      assert.is_true(success1, "First setup should succeed")
      assert.is_true(success2, "Second setup should succeed")
    end)
  end)
end)