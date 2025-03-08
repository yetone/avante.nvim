local assert = require("luassert")
local utils = require("avante.utils")

describe("make_relative_path", function()
  it("should remove base directory from filepath", function()
    local test_filepath = "/path/to/project/src/file.lua"
    local test_base_dir = "/path/to/project"
    local result = utils.make_relative_path(test_filepath, test_base_dir)
    assert.equals("src/file.lua", result)
  end)

  it("should handle trailing dot-slash in base_dir", function()
    local test_filepath = "/path/to/project/src/file.lua"
    local test_base_dir = "/path/to/project/."
    local result = utils.make_relative_path(test_filepath, test_base_dir)
    assert.equals("src/file.lua", result)
  end)

  it("should handle trailing dot-slash in filepath", function()
    local test_filepath = "/path/to/project/src/."
    local test_base_dir = "/path/to/project"
    local result = utils.make_relative_path(test_filepath, test_base_dir)
    assert.equals("src", result)
  end)

  it("should handle both having trailing dot-slash", function()
    local test_filepath = "/path/to/project/src/."
    local test_base_dir = "/path/to/project/."
    local result = utils.make_relative_path(test_filepath, test_base_dir)
    assert.equals("src", result)
  end)

  it("should return the filepath when base_dir is not a prefix", function()
    local test_filepath = "/path/to/project/src/file.lua"
    local test_base_dir = "/different/path"
    local result = utils.make_relative_path(test_filepath, test_base_dir)
    assert.equals("/path/to/project/src/file.lua", result)
  end)

  it("should handle identical paths", function()
    local test_filepath = "/path/to/project"
    local test_base_dir = "/path/to/project"
    local result = utils.make_relative_path(test_filepath, test_base_dir)
    assert.equals(".", result)
  end)

  it("should handle empty strings", function()
    local result = utils.make_relative_path("", "")
    assert.equals(".", result)
  end)

  it("should preserve trailing slash in filepath", function()
    local test_filepath = "/path/to/project/src/"
    local test_base_dir = "/path/to/project"
    local result = utils.make_relative_path(test_filepath, test_base_dir)
    assert.equals("src/", result)
  end)
end)
