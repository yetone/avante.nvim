local utils = require("avante.utils")

describe("get_parent_path", function()
  -- Define path separator for our tests, using the same logic as in the utils module
  local path_sep = jit.os:find("Windows") ~= nil and "\\" or "/"

  it("should return the parent directory of a file path", function()
    local filepath = "foo" .. path_sep .. "bar" .. path_sep .. "baz.txt"
    local expected = "foo" .. path_sep .. "bar"
    assert.are.equal(expected, utils.get_parent_path(filepath))
  end)

  it("should return the parent directory of a directory path", function()
    local dirpath = "foo" .. path_sep .. "bar" .. path_sep .. "baz"
    local expected = "foo" .. path_sep .. "bar"
    assert.are.equal(expected, utils.get_parent_path(dirpath))
  end)

  it("should handle trailing separators", function()
    local dirpath = "foo" .. path_sep .. "bar" .. path_sep .. "baz" .. path_sep
    local expected = "foo" .. path_sep .. "bar"
    assert.are.equal(expected, utils.get_parent_path(dirpath))
  end)

  it("should return '.' for a single file or directory", function()
    assert.are.equal(".", utils.get_parent_path("foo.txt"))
    assert.are.equal(".", utils.get_parent_path("dir"))
  end)

  it("should handle paths with multiple levels", function()
    local filepath = "a" .. path_sep .. "b" .. path_sep .. "c" .. path_sep .. "d" .. path_sep .. "file.txt"
    local expected = "a" .. path_sep .. "b" .. path_sep .. "c" .. path_sep .. "d"
    assert.are.equal(expected, utils.get_parent_path(filepath))
  end)

  it("should return empty string for root directory", function()
    -- Root directory on Unix-like systems
    if path_sep == "/" then
      assert.are.equal("/", utils.get_parent_path("/foo"))
    else
      -- Windows uses drive letters, so parent of "C:\foo" is "C:"
      local winpath = "C:" .. path_sep .. "foo"
      assert.are.equal("C:", utils.get_parent_path(winpath))
    end
  end)

  it("should return empty string for an empty string", function() assert.are.equal("", utils.get_parent_path("")) end)

  it("should throw an error for nil input", function()
    assert.has_error(function() utils.get_parent_path(nil) end, "filepath cannot be nil")
  end)

  it("should handle paths with spaces", function()
    local filepath = "path with spaces" .. path_sep .. "file name.txt"
    local expected = "path with spaces"
    assert.are.equal(expected, utils.get_parent_path(filepath))
  end)

  it("should handle special characters in paths", function()
    local filepath = "folder-name!" .. path_sep .. "file_#$%&.txt"
    local expected = "folder-name!"
    assert.are.equal(expected, utils.get_parent_path(filepath))
  end)

  it("should handle absolute paths", function()
    if path_sep == "/" then
      -- Unix-like paths
      local filepath = path_sep .. "home" .. path_sep .. "user" .. path_sep .. "file.txt"
      local expected = path_sep .. "home" .. path_sep .. "user"
      assert.are.equal(expected, utils.get_parent_path(filepath))

      -- Root directory edge case
      assert.are.equal("", utils.get_parent_path(path_sep))
    else
      -- Windows paths
      local filepath = "C:" .. path_sep .. "Users" .. path_sep .. "user" .. path_sep .. "file.txt"
      local expected = "C:" .. path_sep .. "Users" .. path_sep .. "user"
      assert.are.equal(expected, utils.get_parent_path(filepath))
    end
  end)
end)
