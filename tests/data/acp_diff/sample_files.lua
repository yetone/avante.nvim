---@class avante.test.acp_diff.sample_files
--- Mock file contents for testing acp_diff_handler
--- Each entry represents the current state of a file before edits

local M = {}

-- Simple README file with single line
M.readme_simple = {
  "# Platform Frontend",
  "",
  "This is a test project.",
}

-- File with multiple occurrences of 'config'
M.app_with_config = {
  "local config = require('config')",
  "local function setup()",
  "  config.init()",
  "  return config",
  "end",
}

-- File with 'variable' keyword for special char testing
M.lib_with_variable = {
  "local variable = 'test'",
  "local another_variable = 'value'",
  "local variable_name = 'foo'",
  "return variable",
}

-- File with path keyword
M.paths_file = {
  "local path = '/usr/local'",
  "return path",
}

-- Config file with foo and baz
M.config_with_foo_baz = {
  "local M = {}",
  "M.foo = 'original'",
  "M.baz = 'original'",
  "return M",
}

-- Empty file (for new file creation tests)
M.empty_file = {}

-- Utils file with function
M.utils_with_function = {
  "local M = {}",
  "",
  "function process(data)",
  "  return data",
  "end",
  "",
  "return M",
}

-- Main file with multiple sections for offset testing
M.main_file_for_offset = {
  "local a = 1",
  "",
  "local function work()",
  "  print('working')",
  "end",
  "",
  "return result",
}

-- Settings file
M.settings_file = {
  "return {",
  "  debug = false,",
  "  verbose = true,",
  "}",
}

-- Single line gitignore
M.gitignore_single_line = {
  "node_modules",
}

-- Temp file with code to delete
M.temp_file_with_todo = {
  "local M = {}",
  "",
  "-- TODO: Remove this",
  "local unused = 1",
  "",
  "return M",
}

-- File with 'old' substring within longer line
M.code_with_substring = {
  "local old_value = 123",
  "local very_old_code = true",
  "return old_value",
}

-- File with duplicate text on multiple lines
M.file_with_duplicates = {
  "config = 1",
  "local config = 2",
  "  config = 3",
  "return config",
}

-- Multi-line file for minimize_diff testing
M.file_for_minimize_diff = {
  "line 1 - change me",
  "line 2 - keep me",
  "line 3 - change me",
  "line 4 - keep me",
  "line 5 - change me",
}

-- File with special characters
M.file_with_special_chars = {
  "local pattern = 'test%d+'",
  "local regex = [[\\w+]]",
  "return pattern",
}

-- Large file for performance testing (optional)
M.large_file = {}
for i = 1, 100 do
  table.insert(M.large_file, "line " .. i)
end

return M
