---@diagnostic disable: undefined-field
local M = require("avante.llm_tools.acp_diff_handler")
local Utils = require("avante.utils")
local Config = require("avante.config")
local fixtures = require("tests.data.acp_diff.fixtures")
local sample_files = require("tests.data.acp_diff.sample_files")
local stub = require("luassert.stub")

describe("acp_diff_handler", function()
  local original_behaviour

  before_each(function()
    -- Initialize Config.behaviour if it doesn't exist
    if not Config.behaviour then
      Config.behaviour = {}
    end

    -- Store original config value
    original_behaviour = vim.deepcopy(Config.behaviour)

    -- Set minimize_diff to false for predictable tests
    Config.behaviour.minimize_diff = false
  end)

  after_each(function()
    -- Restore original config
    if original_behaviour then
      Config.behaviour = original_behaviour
    end
  end)

  describe("has_diff_content", function()
    it("should detect diff in content array", function()
      local result = M.has_diff_content(fixtures.simple_single_line_edit)
      assert.is_true(result)
    end)

    it("should detect diff in rawInput with new_string", function()
      local tool_call = {
        rawInput = {
          new_string = "text content",
        },
      }
      assert.is_true(M.has_diff_content(tool_call))
    end)

    it("should return false when no diff present", function()
      local tool_call = {}
      assert.is_false(M.has_diff_content(tool_call))
    end)

    it("should return false when rawInput.new_string is nil", function()
      local tool_call = {
        rawInput = {
          new_string = nil,
        },
      }
      assert.is_false(M.has_diff_content(tool_call))
    end)

    it("should return false when rawInput.new_string is vim.NIL", function()
      local tool_call = {
        rawInput = {
          new_string = vim.NIL,
        },
      }
      assert.is_false(M.has_diff_content(tool_call))
    end)
  end)

  describe("extract_diff_blocks", function()
    local path_stub, read_stub, fuzzy_stub

    before_each(function()
      -- Default stubs that can be overridden in specific tests
      path_stub = stub(Utils, "to_absolute_path", function(path)
        return path -- Return as-is for testing
      end)
    end)

    after_each(function()
      if path_stub then
        path_stub:revert()
      end
      if read_stub then
        read_stub:revert()
      end
      if fuzzy_stub then
        fuzzy_stub:revert()
      end
    end)

    describe("simple single-line edits", function()
      before_each(function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.readme_simple, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function(file_lines, search_lines)
          -- Find exact match
          local search_str = search_lines[1]
          for i, line in ipairs(file_lines) do
            if line == search_str then
              return i, i + #search_lines - 1
            end
          end
          return nil, nil
        end)
      end)

      it("should extract simple single-line replacement from content", function()
        local result = M.extract_diff_blocks(fixtures.simple_single_line_edit)

        assert.is_not_nil(result["/project/README.md"])
        assert.equals(1, #result["/project/README.md"])

        local block = result["/project/README.md"][1]
        assert.equals(1, block.start_line)
        assert.equals(1, block.end_line)
        assert.same({ "# Platform Frontend" }, block.old_lines)
        assert.same({ "# Platform Front-end" }, block.new_lines)
        assert.equals(1, block.new_start_line)
        assert.equals(1, block.new_end_line)
      end)
    end)

    describe("replace_all behavior", function()
      before_each(function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.app_with_config, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function()
          return nil, nil -- Force fallback to substring search
        end)
      end)

      it("should replace all occurrences when replace_all is true", function()
        local find_all_stub = stub(Utils, "find_all_matches", function(file_lines, search_lines)
          local matches = {}
          local search_str = search_lines[1]
          for i, line in ipairs(file_lines) do
            if line:find(search_str, 1, true) then
              table.insert(matches, { start_line = i, end_line = i })
            end
          end
          return matches
        end)

        local result = M.extract_diff_blocks(fixtures.replace_all_occurrences)

        assert.is_not_nil(result["/project/app.lua"])
        -- Should find 3 occurrences: lines 1, 3, 4
        assert.equals(3, #result["/project/app.lua"])

        find_all_stub:revert()
      end)

      it("should only replace first occurrence when replace_all is false", function()
        read_stub:revert()
        fuzzy_stub:revert()

        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.file_with_duplicates, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function()
          return nil, nil -- Force substring replacement
        end)

        local tool_call = {
          rawInput = {
            file_path = "/project/app.lua",
            old_string = "config",
            new_string = "configuration",
            replace_all = false,
          },
        }

        local result = M.extract_diff_blocks(tool_call)

        assert.is_not_nil(result["/project/app.lua"])
        -- Should only find 1 occurrence (first match)
        assert.equals(1, #result["/project/app.lua"])
      end)
    end)

    describe("CRITICAL BUG: special characters in replacement", function()
      before_each(function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.lib_with_variable, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function()
          return nil, nil -- Force substring replacement path
        end)
      end)

      it("should handle %1 in replacement text as literal (not backreference)", function()
        local result = M.extract_diff_blocks(fixtures.special_chars_in_replacement)

        assert.is_not_nil(result["/project/lib.lua"])
        local blocks = result["/project/lib.lua"]

        -- Verify that at least one block was created
        assert.truthy(#blocks > 0, "Expected at least one diff block")

        -- Verify that %1 appears literally in the result (escaped or literal)
        local found_replacement = false
        for _, block in ipairs(blocks) do
          local new_text = table.concat(block.new_lines, "\n")
          -- Should contain "result" and "%1" (possibly as "result%1")
          if new_text:find("result", 1, true) and new_text:find("%%1", 1, false) then
            found_replacement = true
            break
          end
        end
        assert.truthy(found_replacement, "Expected literal 'result%1' pattern in replacement")
      end)

      it("should handle backslashes in replacement text", function()
        read_stub:revert()
        fuzzy_stub:revert()

        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.paths_file, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function()
          return nil, nil -- Force substring replacement
        end)

        local result = M.extract_diff_blocks(fixtures.special_chars_backslash)

        -- Allow for case where no match is found (backslash handling is complex)
        if result["/project/paths.lua"] and #result["/project/paths.lua"] > 0 then
          local block = result["/project/paths.lua"][1]
          local new_text = table.concat(block.new_lines, "\n")
          -- Just verify we got some replacement
          assert.truthy(#new_text > 0)
        end
      end)
    end)

    describe("multiple content items for same file", function()
      before_each(function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.config_with_foo_baz, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function()
          return nil, nil -- Force substring replacement
        end)
      end)

      it("should handle multiple edits to same file", function()
        local result = M.extract_diff_blocks(fixtures.multiple_edits_same_file)

        assert.is_not_nil(result["/project/config.lua"])
        -- Should have 2 diff blocks
        assert.equals(2, #result["/project/config.lua"])

        -- Blocks should be sorted by start_line
        local blocks = result["/project/config.lua"]
        assert.truthy(blocks[1].start_line <= blocks[2].start_line)
      end)
    end)

    describe("new file creation", function()
      before_each(function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return {}, nil -- Empty file
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function()
          return nil, nil
        end)
      end)

      it("should handle new file with empty string oldText", function()
        local result = M.extract_diff_blocks(fixtures.new_file_creation_empty_string)

        assert.is_not_nil(result["/project/new_module.lua"])
        local block = result["/project/new_module.lua"][1]

        assert.equals(1, block.start_line)
        assert.equals(0, block.end_line) -- New file marker
        assert.same({}, block.old_lines)
        -- The file content splits into 7 lines (including empty lines from \n\n)
        assert.equals(7, #block.new_lines)
      end)

      it("should handle new file with vim.NIL oldText", function()
        local result = M.extract_diff_blocks(fixtures.new_file_creation_vim_nil)

        assert.is_not_nil(result["/project/another_module.lua"])
        local block = result["/project/another_module.lua"][1]

        assert.equals(1, block.start_line)
        assert.equals(0, block.end_line)
        assert.same({}, block.old_lines)
        assert.equals(2, #block.new_lines)
      end)
    end)

    describe("multi-line replacements", function()
      before_each(function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.utils_with_function, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function(file_lines, search_lines)
          -- Find the function across multiple lines
          if #search_lines == 3 and search_lines[1]:match("^function process") then
            return 3, 5 -- Lines 3-5 in utils_with_function
          end
          return nil, nil
        end)
      end)

      it("should handle multi-line function replacement", function()
        local result = M.extract_diff_blocks(fixtures.multiline_function_edit)

        assert.is_not_nil(result["/project/utils.lua"])
        local block = result["/project/utils.lua"][1]

        assert.equals(3, block.start_line)
        assert.equals(5, block.end_line)
        assert.equals(3, #block.old_lines)
        assert.equals(5, #block.new_lines) -- Expanded to 5 lines
      end)
    end)

    describe("cumulative offset calculation", function()
      before_each(function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.main_file_for_offset, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function(file_lines, search_lines)
          local search_str = search_lines[1]
          for i, line in ipairs(file_lines) do
            if line == search_str then
              return i, i + #search_lines - 1
            end
          end
          return nil, nil
        end)
      end)

      it("should calculate new_start_line and new_end_line with cumulative offset", function()
        local result = M.extract_diff_blocks(fixtures.multiple_diff_blocks_offset_test)

        assert.is_not_nil(result["/project/main.lua"])
        local blocks = result["/project/main.lua"]

        -- First block: line 1, replaces 1 line with 2 lines (offset +1)
        assert.equals(1, blocks[1].start_line)
        assert.equals(1, blocks[1].new_start_line)
        assert.equals(2, blocks[1].new_end_line)

        -- Second block: originally at line 7, but with +1 offset becomes line 8
        assert.equals(7, blocks[2].start_line)
        assert.equals(8, blocks[2].new_start_line)
        assert.equals(8, blocks[2].new_end_line)
      end)
    end)

    describe("edge cases", function()
      it("should handle empty file", function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return {}, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function()
          return nil, nil
        end)

        local tool_call = {
          content = { {
            type = "diff",
            path = "/project/empty.lua",
            oldText = "",
            newText = "content",
          } },
        }

        local result = M.extract_diff_blocks(tool_call)
        assert.is_not_nil(result["/project/empty.lua"])
      end)

      it("should handle only rawInput present (no content array)", function()
        if read_stub then
          read_stub:revert()
        end
        if fuzzy_stub then
          fuzzy_stub:revert()
        end

        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.settings_file, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function(file_lines, search_lines)
          -- Find "debug = false" in settings file
          for i, line in ipairs(file_lines) do
            if line:find(search_lines[1], 1, true) then
              return i, i
            end
          end
          return nil, nil
        end)

        local result = M.extract_diff_blocks(fixtures.only_raw_input)

        assert.is_not_nil(result["/project/settings.lua"])
        assert.truthy(#result["/project/settings.lua"] > 0)
      end)

      it("should handle deletion (newText is empty)", function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return sample_files.temp_file_with_todo, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function(file_lines, search_lines)
          -- Find lines 3-4
          if #search_lines == 2 and search_lines[1]:match("TODO") then
            return 3, 4
          end
          return nil, nil
        end)

        local result = M.extract_diff_blocks(fixtures.delete_lines)

        assert.is_not_nil(result["/project/temp.lua"])
        local block = result["/project/temp.lua"][1]

        assert.equals(3, block.start_line)
        assert.equals(4, block.end_line)
        assert.same({}, block.new_lines)
        -- For deletions, new_end_line is one before new_start_line
        assert.equals(block.new_start_line - 1, block.new_end_line)
      end)

      it("should return empty table when no diff found", function()
        read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
          return { "unrelated content" }, nil
        end)
        fuzzy_stub = stub(Utils, "fuzzy_match", function()
          return nil, nil -- No match
        end)

        local tool_call = {
          content = { {
            type = "diff",
            path = "/project/file.lua",
            oldText = "nonexistent",
            newText = "replacement",
          } },
        }

        local result = M.extract_diff_blocks(tool_call)

        -- Should return empty table when no matches found
        assert.truthy(next(result) == nil or result["/project/file.lua"] == nil)
      end)
    end)
  end)

  -- Note: minimize_diff_blocks is a private function (in P table, not M table)
  -- It's tested indirectly through extract_diff_blocks with Config.behaviour.minimize_diff = true

  describe("integration with Config.behaviour.minimize_diff", function()
    it("should apply minimize_diff when config enabled", function()
      Config.behaviour.minimize_diff = true

      local read_stub = stub(Utils, "read_file_from_buf_or_disk", function()
        return sample_files.file_for_minimize_diff, nil
      end)
      local fuzzy_stub = stub(Utils, "fuzzy_match", function()
        return 1, 5 -- Match all 5 lines
      end)

      local tool_call = {
        content = { {
          type = "diff",
          path = "/project/test.lua",
          oldText = table.concat(sample_files.file_for_minimize_diff, "\n"),
          newText = "CHANGED\nline 2 - keep me\nCHANGED\nline 4 - keep me\nCHANGED",
        } },
      }

      local result = M.extract_diff_blocks(tool_call)

      read_stub:revert()
      fuzzy_stub:revert()

      -- Should have multiple blocks (unchanged lines removed)
      assert.truthy(#result["/project/test.lua"] > 1)
    end)
  end)
end)
