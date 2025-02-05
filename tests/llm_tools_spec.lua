local mock = require("luassert.mock")
local stub = require("luassert.stub")
local LlmTools = require("avante.llm_tools")
local Utils = require("avante.utils")

LlmTools.confirm = function(msg) return true end

describe("llm_tools", function()
  local test_dir = "/tmp/test_llm_tools"
  local test_file = test_dir .. "/test.txt"

  before_each(function()
    -- 创建测试目录和文件
    os.execute("mkdir -p " .. test_dir)
    local file = io.open(test_file, "w")
    file:write("test content")
    file:close()

    -- Mock get_project_root
    stub(Utils, "get_project_root", function() return test_dir end)
  end)

  after_each(function()
    -- 清理测试目录
    os.execute("rm -rf " .. test_dir)
    -- 恢复 mock
    Utils.get_project_root:revert()
  end)

  describe("list_files", function()
    it("should list files in directory", function()
      local result, err = LlmTools.list_files({ rel_path = ".", depth = 1 })
      assert.is_nil(err)
      assert.truthy(result:find("test.txt"))
    end)
  end)

  describe("read_file", function()
    it("should read file content", function()
      local content, err = LlmTools.read_file({ rel_path = "test.txt" })
      assert.is_nil(err)
      assert.equals("test content", content)
    end)

    it("should return error for non-existent file", function()
      local content, err = LlmTools.read_file({ rel_path = "non_existent.txt" })
      assert.truthy(err)
      assert.equals("", content)
    end)
  end)

  describe("create_file", function()
    it("should create new file", function()
      local success, err = LlmTools.create_file({ rel_path = "new_file.txt" })
      assert.is_nil(err)
      assert.is_true(success)

      local file_exists = io.open(test_dir .. "/new_file.txt", "r") ~= nil
      assert.is_true(file_exists)
    end)
  end)

  describe("create_dir", function()
    it("should create new directory", function()
      local success, err = LlmTools.create_dir({ rel_path = "new_dir" })
      assert.is_nil(err)
      assert.is_true(success)

      local dir_exists = io.open(test_dir .. "/new_dir", "r") ~= nil
      assert.is_true(dir_exists)
    end)
  end)

  describe("delete_file", function()
    it("should delete existing file", function()
      local success, err = LlmTools.delete_file({ rel_path = "test.txt" })
      assert.is_nil(err)
      assert.is_true(success)

      local file_exists = io.open(test_file, "r") ~= nil
      assert.is_false(file_exists)
    end)
  end)

  describe("search_files", function()
    it("should find files matching pattern", function()
      local result, err = LlmTools.search_files({ rel_path = ".", keyword = "test" })
      assert.is_nil(err)
      assert.truthy(result:find("test.txt"))
    end)
  end)

  describe("search", function()
    local original_exepath = vim.fn.exepath

    after_each(function() vim.fn.exepath = original_exepath end)

    it("should search using ripgrep when available", function()
      -- Mock exepath to return rg path
      vim.fn.exepath = function(cmd)
        if cmd == "rg" then return "/usr/bin/rg" end
        return ""
      end

      -- Create a test file with searchable content
      local file = io.open(test_dir .. "/searchable.txt", "w")
      file:write("this is searchable content")
      file:close()

      file = io.open(test_dir .. "/nothing.txt", "w")
      file:write("this is nothing")
      file:close()

      local result, err = LlmTools.search({ rel_path = ".", keyword = "searchable" })
      assert.is_nil(err)
      assert.truthy(result:find("searchable.txt"))
      assert.falsy(result:find("nothing.txt"))
    end)

    it("should search using ag when rg is not available", function()
      -- Mock exepath to return ag path
      vim.fn.exepath = function(cmd)
        if cmd == "ag" then return "/usr/bin/ag" end
        return ""
      end

      -- Create a test file specifically for ag
      local file = io.open(test_dir .. "/ag_test.txt", "w")
      file:write("content for ag test")
      file:close()

      local result, err = LlmTools.search({ rel_path = ".", keyword = "ag test" })
      assert.is_nil(err)
      assert.is_string(result)
      assert.truthy(result:find("ag_test.txt"))
    end)

    it("should search using grep when rg and ag are not available", function()
      -- Mock exepath to return grep path
      vim.fn.exepath = function(cmd)
        if cmd == "grep" then return "/usr/bin/grep" end
        return ""
      end

      local result, err = LlmTools.search({ rel_path = ".", keyword = "test" })
      assert.is_nil(err)
      assert.truthy(result:find("test.txt"))
    end)

    it("should return error when no search tool is available", function()
      -- Mock exepath to return nothing
      vim.fn.exepath = function() return "" end

      local result, err = LlmTools.search({ rel_path = ".", keyword = "test" })
      assert.equals("", result)
      assert.equals("No search command found", err)
    end)

    it("should respect path permissions", function()
      local result, err = LlmTools.search({ rel_path = "../outside_project", keyword = "test" })
      assert.truthy(err:find("No permission to access path"))
    end)

    it("should handle non-existent paths", function()
      local result, err = LlmTools.search({ rel_path = "non_existent_dir", keyword = "test" })
      assert.equals("", result)
      assert.truthy(err)
      assert.truthy(err:find("No such file or directory"))
    end)
  end)

  describe("run_command", function()
    it("should execute command and return output", function()
      local result, err = LlmTools.run_command({ rel_path = ".", command = "echo 'test'" })
      assert.is_nil(err)
      assert.equals("test\n", result)
    end)

    it("should return error when running outside current directory", function()
      local result, err = LlmTools.run_command({ rel_path = "../outside_project", command = "echo 'test'" })
      assert.is_false(result)
      assert.truthy(err)
      assert.truthy(err:find("No permission to access path"))
    end)
  end)
end)
