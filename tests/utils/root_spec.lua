local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("avante.utils.root", function()
  local root
  local original_cwd

  before_each(function()
    -- Clear package cache to get fresh module
    package.loaded["avante.utils.root"] = nil
    package.loaded["avante.config"] = nil
    package.loaded["avante.utils"] = nil

    -- Mock Config module to avoid dependencies
    package.loaded["avante.config"] = {
      ask_opts = { project_root = nil },
      behaviour = { use_cwd_as_project_root = false },
    }

    -- Mock Utils module
    package.loaded["avante.utils"] = {
      norm = function(path) return path end,
      is_win = function() return false end,
      lsp = {
        get_clients = function() return {} end,
      },
    }

    -- Save original cwd function
    original_cwd = vim.uv.cwd

    root = require("avante.utils.root")
  end)

  after_each(function()
    -- Restore original cwd
    vim.uv.cwd = original_cwd
    root = nil
  end)

  describe("M.detectors.cwd", function()
    it("should return empty table when vim.uv.cwd() returns nil", function()
      vim.uv.cwd = function() return nil end
      local result = root.detectors.cwd()
      assert.is_table(result)
      assert.equals(0, #result)
    end)

    it("should return table with cwd when vim.uv.cwd() returns valid path", function()
      vim.uv.cwd = function() return "/valid/path" end
      local result = root.detectors.cwd()
      assert.is_table(result)
      assert.equals(1, #result)
      assert.equals("/valid/path", result[1])
    end)
  end)

  describe("M.detectors.pattern", function()
    it("should use '/' as fallback when buf path and cwd are nil", function()
      vim.uv.cwd = function() return nil end

      -- Mock vim.api.nvim_buf_get_name to return empty string
      local original_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "" end

      -- Mock vim.fs.find to capture the path parameter
      local captured_path = nil
      local original_find = vim.fs.find
      vim.fs.find = function(fn, opts)
        captured_path = opts.path
        return {}
      end

      root.detectors.pattern(1, "test.txt")

      assert.equals("/", captured_path)

      -- Restore
      vim.api.nvim_buf_get_name = original_get_name
      vim.fs.find = original_find
    end)
  end)

  describe("M.get", function()
    it("should return '/' when cwd is nil and no roots are detected", function()
      vim.uv.cwd = function() return nil end

      -- Mock vim.api functions
      local original_get_current_buf = vim.api.nvim_get_current_buf
      local original_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_name = function() return "" end

      -- Mock vim.fs.find to return nothing
      local original_find = vim.fs.find
      vim.fs.find = function() return {} end

      local result = root.get()
      assert.equals("/", result)

      -- Restore
      vim.api.nvim_get_current_buf = original_get_current_buf
      vim.api.nvim_buf_get_name = original_get_name
      vim.fs.find = original_find
    end)

    it("should not crash when cwd becomes nil after detection", function()
      -- First call with valid cwd
      vim.uv.cwd = function() return "/valid/path" end

      local original_get_current_buf = vim.api.nvim_get_current_buf
      local original_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_name = function() return "/valid/path/file.txt" end

      local original_find = vim.fs.find
      vim.fs.find = function() return {} end

      local result = root.get()
      assert.equals("/valid/path", result)

      -- Simulate cwd being deleted (becomes nil)
      vim.uv.cwd = function() return nil end
      
      -- Mock buf_get_name for different buffers
      local function mock_get_name(buf)
        if buf == 2 then
          return "/other/file.txt"
        else
          return "/valid/path/file.txt"
        end
      end
      vim.api.nvim_buf_get_name = mock_get_name

      -- Should not crash, should use cached value or fallback
      result = root.get({ buf = 2 }) -- Different buffer to bypass cache
      
      assert.is_string(result)
      assert.equals("/", result)

      -- Restore
      vim.api.nvim_get_current_buf = original_get_current_buf
      vim.api.nvim_buf_get_name = original_get_name
      vim.fs.find = original_find
    end)

    it("should handle nil ret in length comparison", function()
      vim.uv.cwd = function() return "/some/path" end

      local original_get_current_buf = vim.api.nvim_get_current_buf
      local original_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_name = function() return "" end

      local original_find = vim.fs.find
      vim.fs.find = function() return {} end

      -- This simulates a case where M.detect returns no roots
      -- and cwd fallback would be used, but if it were nil, we'd get an error
      local result = root.get()
      
      -- Should not crash and should return a valid string
      assert.is_string(result)

      -- Restore
      vim.api.nvim_get_current_buf = original_get_current_buf
      vim.api.nvim_buf_get_name = original_get_name
      vim.fs.find = original_find
    end)

    it("should return string (not nil) even when everything fails", function()
      vim.uv.cwd = function() return nil end

      local original_get_current_buf = vim.api.nvim_get_current_buf
      local original_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_name = function() return "" end

      local original_find = vim.fs.find
      vim.fs.find = function() return {} end

      local result = root.get()
      
      assert.is_not_nil(result)
      assert.is_string(result)
      assert.equals("/", result)

      -- Restore
      vim.api.nvim_get_current_buf = original_get_current_buf
      vim.api.nvim_buf_get_name = original_get_name
      vim.fs.find = original_find
    end)
  end)

  describe("M.cwd", function()
    it("should return empty string when vim.uv.cwd() returns nil", function()
      vim.uv.cwd = function() return nil end
      local result = root.cwd()
      assert.equals("", result)
    end)

    it("should return normalized path when vim.uv.cwd() returns valid path", function()
      vim.uv.cwd = function() return "/valid/path" end
      local result = root.cwd()
      assert.equals("/valid/path", result)
    end)
  end)
end)
