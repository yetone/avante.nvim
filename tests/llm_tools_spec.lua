local stub = require("luassert.stub")
local LlmTools = require("avante.llm_tools")
local LlmToolHelpers = require("avante.llm_tools.helpers")
local Config = require("avante.config")
local Utils = require("avante.utils")
local ls = require("avante.llm_tools.ls")
local grep = require("avante.llm_tools.grep")
local glob = require("avante.llm_tools.glob")
local view = require("avante.llm_tools.view")
local bash = require("avante.llm_tools.bash")

LlmToolHelpers.confirm = function(msg, cb) return cb(true) end
LlmToolHelpers.already_in_context = function(path) return false end

describe("llm_tools", function()
  local test_dir = "/tmp/test_llm_tools"
  local test_file = test_dir .. "/test.txt"

  before_each(function()
    Config.setup()
    -- 创建测试目录和文件
    os.execute("mkdir -p " .. test_dir)
    os.execute(string.format("cd %s; git init", test_dir))
    local file = io.open(test_file, "w")
    if not file then error("Failed to create test file") end
    file:write("test content")
    file:close()
    os.execute("mkdir -p " .. test_dir .. "/test_dir1")
    file = io.open(test_dir .. "/test_dir1/test1.txt", "w")
    if not file then error("Failed to create test file") end
    file:write("test1 content")
    file:close()
    os.execute("mkdir -p " .. test_dir .. "/test_dir2")
    file = io.open(test_dir .. "/test_dir2/test2.txt", "w")
    if not file then error("Failed to create test file") end
    file:write("test2 content")
    file:close()
    file = io.open(test_dir .. "/.gitignore", "w")
    if not file then error("Failed to create test file") end
    file:write("test_dir2/")
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

  describe("ls", function()
    it("should list files in directory", function()
      local result, err = ls({ rel_path = ".", max_depth = 1 })
      assert.is_nil(err)
      assert.falsy(result:find("avante.nvim"))
      assert.truthy(result:find("test.txt"))
      assert.falsy(result:find("test1.txt"))
    end)
    it("should list files in directory with depth", function()
      local result, err = ls({ rel_path = ".", max_depth = 2 })
      assert.is_nil(err)
      assert.falsy(result:find("avante.nvim"))
      assert.truthy(result:find("test.txt"))
      assert.truthy(result:find("test1.txt"))
    end)
    it("should list files respecting gitignore", function()
      local result, err = ls({ rel_path = ".", max_depth = 2 })
      assert.is_nil(err)
      assert.falsy(result:find("avante.nvim"))
      assert.truthy(result:find("test.txt"))
      assert.truthy(result:find("test1.txt"))
      assert.falsy(result:find("test2.txt"))
    end)
  end)

  describe("view", function()
    it("should read file content", function()
      view({ path = "test.txt" }, nil, function(content, err)
        assert.is_nil(err)
        assert.equals("test content", content)
      end)
    end)

    it("should return error for non-existent file", function()
      view({ path = "non_existent.txt" }, nil, function(content, err)
        assert.truthy(err)
        assert.equals("", content)
      end)
    end)

    it("should read directory content", function()
      view({ path = test_dir }, nil, function(content, err)
        assert.is_nil(err)
        assert.truthy(content:find("test.txt"))
        assert.truthy(content:find("test content"))
      end)
    end)
  end)

  describe("create_dir", function()
    it("should create new directory", function()
      LlmTools.create_dir({ rel_path = "new_dir" }, nil, function(success, err)
        assert.is_nil(err)
        assert.is_true(success)

        local dir_exists = io.open(test_dir .. "/new_dir", "r") ~= nil
        assert.is_true(dir_exists)
      end)
    end)
  end)

  describe("delete_file", function()
    it("should delete existing file", function()
      LlmTools.delete_file({ rel_path = "test.txt" }, nil, function(success, err)
        assert.is_nil(err)
        assert.is_true(success)

        local file_exists = io.open(test_file, "r") ~= nil
        assert.is_false(file_exists)
      end)
    end)
  end)

  describe("grep", function()
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
      if not file then error("Failed to create test file") end
      file:write("this is searchable content")
      file:close()

      file = io.open(test_dir .. "/nothing.txt", "w")
      if not file then error("Failed to create test file") end
      file:write("this is nothing")
      file:close()

      local result, err = grep({ rel_path = ".", query = "Searchable", case_sensitive = false })
      assert.is_nil(err)
      assert.truthy(result:find("searchable.txt"))
      assert.falsy(result:find("nothing.txt"))

      local result2, err2 = grep({ rel_path = ".", query = "searchable", case_sensitive = true })
      assert.is_nil(err2)
      assert.truthy(result2:find("searchable.txt"))
      assert.falsy(result2:find("nothing.txt"))

      local result3, err3 = grep({ rel_path = ".", query = "Searchable", case_sensitive = true })
      assert.is_nil(err3)
      assert.falsy(result3:find("searchable.txt"))
      assert.falsy(result3:find("nothing.txt"))

      local result4, err4 = grep({ rel_path = ".", query = "searchable", case_sensitive = false })
      assert.is_nil(err4)
      assert.truthy(result4:find("searchable.txt"))
      assert.falsy(result4:find("nothing.txt"))

      local result5, err5 = grep({
        rel_path = ".",
        query = "searchable",
        case_sensitive = false,
        exclude_pattern = "search*",
      })
      assert.is_nil(err5)
      assert.falsy(result5:find("searchable.txt"))
      assert.falsy(result5:find("nothing.txt"))
    end)

    it("should search using ag when rg is not available", function()
      -- Mock exepath to return ag path
      vim.fn.exepath = function(cmd)
        if cmd == "ag" then return "/usr/bin/ag" end
        return ""
      end

      -- Create a test file specifically for ag
      local file = io.open(test_dir .. "/ag_test.txt", "w")
      if not file then error("Failed to create test file") end
      file:write("content for ag test")
      file:close()

      local result, err = grep({ rel_path = ".", query = "ag test" })
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

      -- Create a test file with searchable content
      local file = io.open(test_dir .. "/searchable.txt", "w")
      if not file then error("Failed to create test file") end
      file:write("this is searchable content")
      file:close()

      file = io.open(test_dir .. "/nothing.txt", "w")
      if not file then error("Failed to create test file") end
      file:write("this is nothing")
      file:close()

      local result, err = grep({ rel_path = ".", query = "Searchable", case_sensitive = false })
      assert.is_nil(err)
      assert.truthy(result:find("searchable.txt"))
      assert.falsy(result:find("nothing.txt"))

      local result2, err2 = grep({ rel_path = ".", query = "searchable", case_sensitive = true })
      assert.is_nil(err2)
      assert.truthy(result2:find("searchable.txt"))
      assert.falsy(result2:find("nothing.txt"))

      local result3, err3 = grep({ rel_path = ".", query = "Searchable", case_sensitive = true })
      assert.is_nil(err3)
      assert.falsy(result3:find("searchable.txt"))
      assert.falsy(result3:find("nothing.txt"))

      local result4, err4 = grep({ rel_path = ".", query = "searchable", case_sensitive = false })
      assert.is_nil(err4)
      assert.truthy(result4:find("searchable.txt"))
      assert.falsy(result4:find("nothing.txt"))

      local result5, err5 = grep({
        rel_path = ".",
        query = "searchable",
        case_sensitive = false,
        exclude_pattern = "search*",
      })
      assert.is_nil(err5)
      assert.falsy(result5:find("searchable.txt"))
      assert.falsy(result5:find("nothing.txt"))
    end)

    it("should return error when no search tool is available", function()
      -- Mock exepath to return nothing
      vim.fn.exepath = function() return "" end

      local result, err = grep({ rel_path = ".", query = "test" })
      assert.equals("", result)
      assert.equals("No search command found", err)
    end)

    it("should respect path permissions", function()
      local result, err = grep({ rel_path = "../outside_project", query = "test" })
      assert.truthy(err:find("No permission to access path"))
    end)

    it("should handle non-existent paths", function()
      local result, err = grep({ rel_path = "non_existent_dir", query = "test" })
      assert.equals("", result)
      assert.truthy(err)
      assert.truthy(err:find("No such file or directory"))
    end)
  end)

  describe("bash", function()
    it("should execute command and return output", function()
      bash({ rel_path = ".", command = "echo 'test'" }, nil, function(result, err)
        assert.is_nil(err)
        assert.equals("test\n", result)
      end)
    end)

    it("should return error when running outside current directory", function()
      bash({ rel_path = "../outside_project", command = "echo 'test'" }, nil, function(result, err)
        assert.is_false(result)
        assert.truthy(err)
        assert.truthy(err:find("No permission to access path"))
      end)
    end)
  end)

  describe("python", function()
    it("should execute Python code and return output", function()
      LlmTools.python(
        {
          rel_path = ".",
          code = "print('Hello from Python')",
        },
        nil,
        function(result, err)
          assert.is_nil(err)
          assert.equals("Hello from Python\n", result)
        end
      )
    end)

    it("should handle Python errors", function()
      LlmTools.python(
        {
          rel_path = ".",
          code = "print(undefined_variable)",
        },
        nil,
        function(result, err)
          assert.is_nil(result)
          assert.truthy(err)
          assert.truthy(err:find("Error"))
        end
      )
    end)

    it("should respect path permissions", function()
      LlmTools.python(
        {
          rel_path = "../outside_project",
          code = "print('test')",
        },
        nil,
        function(result, err)
          assert.is_nil(result)
          assert.truthy(err:find("No permission to access path"))
        end
      )
    end)

    it("should handle non-existent paths", function()
      LlmTools.python(
        {
          rel_path = "non_existent_dir",
          code = "print('test')",
        },
        nil,
        function(result, err)
          assert.is_nil(result)
          assert.truthy(err:find("Path not found"))
        end
      )
    end)

    it("should support custom container image", function()
      os.execute("docker image rm python:3.12-slim")
      LlmTools.python(
        {
          rel_path = ".",
          code = "print('Hello from custom container')",
          container_image = "python:3.12-slim",
        },
        nil,
        function(result, err)
          assert.is_nil(err)
          assert.equals("Hello from custom container\n", result)
        end
      )
    end)
  end)

  describe("glob", function()
    it("should find files matching the pattern", function()
      -- Create some additional test files with different extensions for glob testing
      os.execute("touch " .. test_dir .. "/file1.lua")
      os.execute("touch " .. test_dir .. "/file2.lua")
      os.execute("touch " .. test_dir .. "/file3.js")
      os.execute("mkdir -p " .. test_dir .. "/nested")
      os.execute("touch " .. test_dir .. "/nested/file4.lua")

      -- Test for lua files in the root
      local result, err = glob({ rel_path = ".", pattern = "*.lua" })
      assert.is_nil(err)
      local files = vim.json.decode(result)
      assert.equals(2, #files)
      assert.truthy(vim.tbl_contains(files, test_dir .. "/file1.lua"))
      assert.truthy(vim.tbl_contains(files, test_dir .. "/file2.lua"))
      assert.falsy(vim.tbl_contains(files, test_dir .. "/file3.js"))
      assert.falsy(vim.tbl_contains(files, test_dir .. "/nested/file4.lua"))

      -- Test with recursive pattern
      local result2, err2 = glob({ rel_path = ".", pattern = "**/*.lua" })
      assert.is_nil(err2)
      local files2 = vim.json.decode(result2)
      assert.equals(3, #files2)
      assert.truthy(vim.tbl_contains(files2, test_dir .. "/file1.lua"))
      assert.truthy(vim.tbl_contains(files2, test_dir .. "/file2.lua"))
      assert.truthy(vim.tbl_contains(files2, test_dir .. "/nested/file4.lua"))
    end)

    it("should respect path permissions", function()
      local result, err = glob({ rel_path = "../outside_project", pattern = "*.txt" })
      assert.equals("", result)
      assert.truthy(err:find("No permission to access path"))
    end)

    it("should handle patterns without matches", function()
      local result, err = glob({ rel_path = ".", pattern = "*.nonexistent" })
      assert.is_nil(err)
      local files = vim.json.decode(result)
      assert.equals(0, #files)
    end)

    it("should handle files in gitignored directories", function()
      -- Create test files in ignored directory
      os.execute("touch " .. test_dir .. "/test_dir2/ignored1.lua")
      os.execute("touch " .. test_dir .. "/test_dir2/ignored2.lua")

      -- Create test files in non-ignored directory
      os.execute("touch " .. test_dir .. "/test_dir1/notignored1.lua")
      os.execute("touch " .. test_dir .. "/test_dir1/notignored2.lua")

      local result, err = glob({ rel_path = ".", pattern = "**/*.lua" })
      assert.is_nil(err)
      local files = vim.json.decode(result)

      -- Check that files from non-ignored directory are found
      local found_notignored = false
      for _, file in ipairs(files) do
        if file:find("test_dir1/notignored") then
          found_notignored = true
          break
        end
      end
      assert.is_true(found_notignored)

      -- Note: By default, vim.fn.glob does not respect gitignore files
      -- This test simply verifies the glob function works as expected
      -- If in the future, the function is modified to respect gitignore,
      -- this test can be updated
    end)
  end)
end)
