---@class avante.test.acp_diff.fixtures
--- Anonymized ACP tool_call fixtures for testing acp_diff_handler
--- Based on real ACP session/update protocol messages

local M = {}

-- Simple single-line edit (most common case)
M.simple_single_line_edit = {
  content = { {
    type = "diff",
    path = "/project/README.md",
    oldText = "# Platform Frontend",
    newText = "# Platform Front-end",
  } },
  rawInput = {
    file_path = "/project/README.md",
    old_string = "# Platform Frontend",
    new_string = "# Platform Front-end",
  },
  kind = "edit",
  locations = { { path = "/project/README.md" } },
  status = "pending",
  title = "Edit `/project/README.md`",
  toolCallId = "test-tool-call-001",
}

-- Replace all occurrences (replace_all = true)
M.replace_all_occurrences = {
  content = { {
    type = "diff",
    path = "/project/app.lua",
    oldText = "config",
    newText = "configuration",
  } },
  rawInput = {
    file_path = "/project/app.lua",
    old_string = "config",
    new_string = "configuration",
    replace_all = true,
  },
  kind = "edit",
  locations = { { path = "/project/app.lua" } },
  status = "pending",
  title = "Edit `/project/app.lua`",
  toolCallId = "test-tool-call-002",
}

-- CRITICAL BUG TEST: Special characters in replacement text
-- Tests Lua pattern special chars: %1, %2, etc. should be literal
M.special_chars_in_replacement = {
  rawInput = {
    file_path = "/project/lib.lua",
    old_string = "variable",
    new_string = "result%1",
    replace_all = true,
  },
  kind = "edit",
  locations = { { path = "/project/lib.lua" } },
  status = "pending",
  title = "Edit `/project/lib.lua`",
  toolCallId = "test-tool-call-003",
}

-- More special characters: backslashes, percent signs
M.special_chars_backslash = {
  rawInput = {
    file_path = "/project/paths.lua",
    old_string = "path",
    new_string = "C:\\Users\\path",
    replace_all = false,
  },
  kind = "edit",
  toolCallId = "test-tool-call-004",
}

-- Multiple content items for same file
M.multiple_edits_same_file = {
  content = {
    {
      type = "diff",
      path = "/project/config.lua",
      oldText = "foo",
      newText = "bar",
    },
    {
      type = "diff",
      path = "/project/config.lua",
      oldText = "baz",
      newText = "qux",
    },
  },
  kind = "edit",
  locations = { { path = "/project/config.lua" } },
  status = "pending",
  title = "Edit `/project/config.lua`",
  toolCallId = "test-tool-call-005",
}

-- New file creation (oldText is empty or nil)
M.new_file_creation_empty_string = {
  content = { {
    type = "diff",
    path = "/project/new_module.lua",
    oldText = "",
    newText = "local M = {}\n\nfunction M.init()\n  return true\nend\n\nreturn M",
  } },
  rawInput = {
    file_path = "/project/new_module.lua",
    old_string = "",
    new_string = "local M = {}\n\nfunction M.init()\n  return true\nend\n\nreturn M",
  },
  kind = "edit",
  locations = { { path = "/project/new_module.lua" } },
  status = "pending",
  title = "Create `/project/new_module.lua`",
  toolCallId = "test-tool-call-006",
}

-- New file creation with vim.NIL
M.new_file_creation_vim_nil = {
  content = { {
    type = "diff",
    path = "/project/another_module.lua",
    oldText = vim.NIL,
    newText = "-- New file\nreturn {}",
  } },
  rawInput = {
    file_path = "/project/another_module.lua",
    old_string = vim.NIL,
    new_string = "-- New file\nreturn {}",
  },
  kind = "edit",
  locations = { { path = "/project/another_module.lua" } },
  status = "pending",
  title = "Create `/project/another_module.lua`",
  toolCallId = "test-tool-call-007",
}

-- Multi-line replacement
M.multiline_function_edit = {
  content = { {
    type = "diff",
    path = "/project/utils.lua",
    oldText = "function process(data)\n  return data\nend",
    newText = "function process(data)\n  -- Add validation\n  if not data then return nil end\n  return data\nend",
  } },
  rawInput = {
    file_path = "/project/utils.lua",
    old_string = "function process(data)\n  return data\nend",
    new_string = "function process(data)\n  -- Add validation\n  if not data then return nil end\n  return data\nend",
  },
  kind = "edit",
  locations = { { path = "/project/utils.lua" } },
  status = "pending",
  title = "Edit `/project/utils.lua`",
  toolCallId = "test-tool-call-008",
}

-- Multiple diff blocks in same file (for testing cumulative offset)
M.multiple_diff_blocks_offset_test = {
  content = {
    {
      type = "diff",
      path = "/project/main.lua",
      oldText = "local a = 1",
      newText = "local a = 1\nlocal b = 2",
    },
    {
      type = "diff",
      path = "/project/main.lua",
      oldText = "return result",
      newText = "return result",
    },
  },
  kind = "edit",
  locations = { { path = "/project/main.lua" } },
  status = "pending",
  title = "Edit `/project/main.lua`",
  toolCallId = "test-tool-call-009",
}

-- Edge case: Only rawInput present (no content array)
M.only_raw_input = {
  rawInput = {
    file_path = "/project/settings.lua",
    old_string = "debug = false",
    new_string = "debug = true",
    replace_all = false,
  },
  kind = "edit",
  locations = { { path = "/project/settings.lua" } },
  status = "pending",
  title = "Edit `/project/settings.lua`",
  toolCallId = "test-tool-call-010",
}

-- Edge case: Single-line file edit
M.single_line_file_edit = {
  content = { {
    type = "diff",
    path = "/project/.gitignore",
    oldText = "node_modules",
    newText = "node_modules\n.env",
  } },
  rawInput = {
    file_path = "/project/.gitignore",
    old_string = "node_modules",
    new_string = "node_modules\n.env",
  },
  kind = "edit",
  toolCallId = "test-tool-call-011",
}

-- Edge case: Deletion (new_string is empty)
M.delete_lines = {
  content = { {
    type = "diff",
    path = "/project/temp.lua",
    oldText = "-- TODO: Remove this\nlocal unused = 1",
    newText = "",
  } },
  rawInput = {
    file_path = "/project/temp.lua",
    old_string = "-- TODO: Remove this\nlocal unused = 1",
    new_string = "",
  },
  kind = "edit",
  toolCallId = "test-tool-call-012",
}

-- Edge case: Substring replacement within line (not full line)
M.substring_within_line = {
  content = { {
    type = "diff",
    path = "/project/code.lua",
    oldText = "old",
    newText = "new",
  } },
  rawInput = {
    file_path = "/project/code.lua",
    old_string = "old",
    new_string = "new",
    replace_all = false,
  },
  kind = "edit",
  toolCallId = "test-tool-call-013",
}

return M
