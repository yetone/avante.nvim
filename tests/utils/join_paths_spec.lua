local assert = require("luassert")
local utils = require("avante.utils")

describe("join_paths", function()
  it("should join multiple path segments with proper separator", function()
    local result = utils.join_paths("path", "to", "file.lua")
    assert.equals("path" .. utils.path_sep .. "to" .. utils.path_sep .. "file.lua", result)
  end)

  it("should handle empty path segments", function()
    local result = utils.join_paths("", "to", "file.lua")
    assert.equals("to" .. utils.path_sep .. "file.lua", result)
  end)

  it("should handle nil path segments", function()
    local result = utils.join_paths(nil, "to", "file.lua")
    assert.equals("to" .. utils.path_sep .. "file.lua", result)
  end)

  it("should handle empty path segments", function()
    local result = utils.join_paths("path", "", "file.lua")
    assert.equals("path" .. utils.path_sep .. "file.lua", result)
  end)

  it("should use absolute path when encountered", function()
    local absolute_path = utils.is_win() and "C:\\absolute\\path" or "/absolute/path"
    local result = utils.join_paths("relative", "path", absolute_path)
    assert.equals(absolute_path, result)
  end)

  it("should handle paths with trailing separators", function()
    local path_with_sep = "path" .. utils.path_sep
    local result = utils.join_paths(path_with_sep, "file.lua")
    assert.equals("path" .. utils.path_sep .. "file.lua", result)
  end)

  it("should return empty string when no paths provided", function()
    local result = utils.join_paths()
    assert.equals("", result)
  end)

  it("should return first path when only one path provided", function()
    local result = utils.join_paths("path")
    assert.equals("path", result)
  end)

  it("should handle path with mixed separators", function()
    -- This test is more relevant on Windows where both / and \ are valid separators
    local mixed_path = utils.is_win() and "path\\to/file" or "path/to/file"
    local result = utils.join_paths("base", mixed_path)
    -- The function should use utils.path_sep for joining
    assert.equals("base" .. utils.path_sep .. mixed_path, result)
  end)
end)
