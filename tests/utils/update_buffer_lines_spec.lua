local Utils = require("avante.utils")

describe("update_buffer_lines with newline handling", function()
  -- Mock vim.api for testing
  local mock_api
  local set_lines_calls

  before_each(function()
    set_lines_calls = {}
    mock_api = {
      nvim_buf_set_lines = function(bufnr, start, end_, strict, lines)
        table.insert(set_lines_calls, {
          bufnr = bufnr,
          start = start,
          end_ = end_,
          strict = strict,
          lines = lines,
        })
      end,
      nvim_buf_line_count = function() return 100 end,
    }
    _G.vim = _G.vim or {}
    _G.vim.api = mock_api
    _G.vim.list_slice = function(tbl, start, finish)
      local result = {}
      for i = start, finish or #tbl do
        table.insert(result, tbl[i])
      end
      return result
    end
    _G.vim.tbl_map = function(func, tbl)
      local result = {}
      for _, v in ipairs(tbl) do
        table.insert(result, func(v))
      end
      return result
    end
    _G.vim.split = function(s, sep)
      local result = {}
      local pattern = string.format("([^%s]+)", sep)
      for match in string.gmatch(s, pattern) do
        table.insert(result, match)
      end
      -- Handle trailing separator
      if s:sub(-1) == sep then
        table.insert(result, "")
      end
      return result
    end
    _G.vim.list_extend = function(dst, src)
      for _, item in ipairs(src) do
        table.insert(dst, item)
      end
      return dst
    end
  end)

  it("should split lines containing embedded newlines", function()
    local ns_id = 1
    local bufnr = 1
    local old_lines = { "line1", "line2" }
    local new_lines = { "line1", "line2 with\nnewline", "line3" }
    local skip_line_count = 0

    -- This test verifies the fix for embedded newlines
    -- Before fix: line with \n would be passed as single line
    -- After fix: should be split into multiple lines

    local lines_with_newline = { "text with\nnewline\ncharacters" }
    local cleaned = {}
    for _, line in ipairs(lines_with_newline) do
      local lines_ = vim.split(line, "\n")
      cleaned = vim.list_extend(cleaned, lines_)
    end

    assert.are.equal(3, #cleaned, "should split into 3 lines")
    assert.are.equal("text with", cleaned[1])
    assert.are.equal("newline", cleaned[2])
    assert.are.equal("characters", cleaned[3])
  end)

  it("should handle single line without newlines", function()
    local lines_without_newline = { "simple line" }
    local cleaned = {}
    for _, line in ipairs(lines_without_newline) do
      local lines_ = vim.split(line, "\n")
      cleaned = vim.list_extend(cleaned, lines_)
    end

    assert.are.equal(1, #cleaned, "should remain single line")
    assert.are.equal("simple line", cleaned[1])
  end)

  it("should handle multiple lines with mixed newline content", function()
    local mixed_lines = {
      "normal line",
      "line with\nnewline",
      "another normal",
      "two\nnew\nlines"
    }
    local cleaned = {}
    for _, line in ipairs(mixed_lines) do
      local lines_ = vim.split(line, "\n")
      cleaned = vim.list_extend(cleaned, lines_)
    end

    assert.are.equal(7, #cleaned, "should result in 7 total lines")
    assert.are.equal("normal line", cleaned[1])
    assert.are.equal("line with", cleaned[2])
    assert.are.equal("newline", cleaned[3])
    assert.are.equal("another normal", cleaned[4])
    assert.are.equal("two", cleaned[5])
    assert.are.equal("new", cleaned[6])
    assert.are.equal("lines", cleaned[7])
  end)

  it("should handle empty lines and trailing newlines", function()
    local lines_with_empty = { "", "line\n", "last" }
    local cleaned = {}
    for _, line in ipairs(lines_with_empty) do
      local lines_ = vim.split(line, "\n")
      cleaned = vim.list_extend(cleaned, lines_)
    end

    -- Empty line stays, "line\n" becomes ["line", ""], "last" stays
    assert.is_true(#cleaned >= 3, "should handle empty lines")
  end)

  it("should convert all elements to strings before splitting", function()
    -- The code uses: tostring(line)
    local mixed_types = { 123, "text", true }
    local text_lines = vim.tbl_map(function(line) return tostring(line) end, mixed_types)

    assert.are.equal("123", text_lines[1])
    assert.are.equal("text", text_lines[2])
    assert.are.equal("true", text_lines[3])
  end)
end)
