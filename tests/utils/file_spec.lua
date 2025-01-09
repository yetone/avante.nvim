local File = require("avante.utils.file")
local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("File", function()
  local test_file = "test.txt"
  local test_content = "test content\nline 2"

  -- Mock vim API
  local api_mock
  local loop_mock

  before_each(function()
    -- Setup mocks
    api_mock = mock(vim.api, true)
    loop_mock = mock(vim.loop, true)
  end)

  after_each(function()
    -- Clean up mocks
    mock.revert(api_mock)
    mock.revert(loop_mock)
  end)

  describe("read_content", function()
    it("should read file content", function()
      vim.fn.readfile = stub().returns({ "test content", "line 2" })

      local content = File.read_content(test_file)
      assert.equals(test_content, content)
      assert.stub(vim.fn.readfile).was_called_with(test_file)
    end)

    it("should return nil for non-existent file", function()
      vim.fn.readfile = stub().returns(nil)

      local content = File.read_content("nonexistent.txt")
      assert.is_nil(content)
    end)

    it("should use cache for subsequent reads", function()
      vim.fn.readfile = stub().returns({ "test content", "line 2" })
      local new_test_file = "test1.txt"

      -- First read
      local content1 = File.read_content(new_test_file)
      assert.equals(test_content, content1)

      -- Second read (should use cache)
      local content2 = File.read_content(new_test_file)
      assert.equals(test_content, content2)

      -- readfile should only be called once
      assert.stub(vim.fn.readfile).was_called(1)
    end)
  end)

  describe("exists", function()
    it("should return true for existing file", function()
      loop_mock.fs_stat.returns({ type = "file" })

      assert.is_true(File.exists(test_file))
      assert.stub(loop_mock.fs_stat).was_called_with(test_file)
    end)

    it("should return false for non-existent file", function()
      loop_mock.fs_stat.returns(nil)

      assert.is_false(File.exists("nonexistent.txt"))
    end)
  end)

  describe("get_file_icon", function()
    local Filetype
    local devicons_mock

    before_each(function()
      -- Mock plenary.filetype
      Filetype = mock(require("plenary.filetype"), true)
      -- Prepare devicons mock
      devicons_mock = {
        get_icon = stub().returns(""),
      }
      -- Reset _G.MiniIcons
      _G.MiniIcons = nil
    end)

    after_each(function() mock.revert(Filetype) end)

    it("should get icon using nvim-web-devicons", function()
      Filetype.detect.returns("lua")
      devicons_mock.get_icon.returns("")

      -- Mock require for nvim-web-devicons
      local old_require = _G.require
      _G.require = function(module)
        if module == "nvim-web-devicons" then return devicons_mock end
        return old_require(module)
      end

      local icon = File.get_file_icon("test.lua")
      assert.equals("", icon)
      assert.stub(Filetype.detect).was_called_with("test.lua", {})
      assert.stub(devicons_mock.get_icon).was_called()

      _G.require = old_require
    end)

    it("should get icon using MiniIcons if available", function()
      _G.MiniIcons = {
        get = stub().returns("", "color", "name"),
      }

      Filetype.detect.returns("lua")

      local icon = File.get_file_icon("test.lua")
      assert.equals("", icon)
      assert.stub(Filetype.detect).was_called_with("test.lua", {})
      assert.stub(_G.MiniIcons.get).was_called_with("filetype", "lua")

      _G.MiniIcons = nil
    end)

    it("should handle unknown filetypes", function()
      Filetype.detect.returns(nil)
      devicons_mock.get_icon.returns("")

      -- Mock require for nvim-web-devicons
      local old_require = _G.require
      _G.require = function(module)
        if module == "nvim-web-devicons" then return devicons_mock end
        return old_require(module)
      end

      local icon = File.get_file_icon("unknown.xyz")
      assert.equals("", icon)

      _G.require = old_require
    end)
  end)
end)
