local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")
local Utils = require("avante.utils")
local Highlights = require("avante.highlights")
local Config = require("avante.config")

local PRIORITY = (vim.hl or vim.highlight).priorities.user
local NAMESPACE = vim.api.nvim_create_namespace("avante-diff")
local KEYBINDING_NAMESPACE = vim.api.nvim_create_namespace("avante-diff-keybinding")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "replace_in_file"

M.description =
  "Request to replace sections of content in an existing file using SEARCH/REPLACE blocks that define exact changes to specific parts of the file. This tool should be used when you need to make targeted changes to specific parts of a file."

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      description = "The path to the file in the current project scope",
      type = "string",
    },
    {
      name = "diff",
      description = [[
One or more SEARCH/REPLACE blocks following this exact format:
  \`\`\`
  <<<<<<< SEARCH
  [exact content to find]
  =======
  [new content to replace with]
  >>>>>>> REPLACE
  \`\`\`
  Critical rules:
  1. SEARCH content must match the associated file section to find EXACTLY:
     * Do not refer to the `diff` argument of the previous `replace_in_file` function call for SEARCH content matching, as it may have been modified. Always match from the latest file content in <selected_files> or from the `view` function call result.
     * Match character-for-character including whitespace, indentation, line endings
     * Include all comments, docstrings, etc.
  2. SEARCH/REPLACE blocks will ONLY replace the first match occurrence.
     * Including multiple unique SEARCH/REPLACE blocks if you need to make multiple changes.
     * Include *just* enough lines in each SEARCH section to uniquely match each set of lines that need to change.
     * When using multiple SEARCH/REPLACE blocks, list them in the order they appear in the file.
  3. Keep SEARCH/REPLACE blocks concise:
     * Break large SEARCH/REPLACE blocks into a series of smaller blocks that each change a small portion of the file.
     * Include just the changing lines, and a few surrounding lines if needed for uniqueness.
     * Do not include long runs of unchanging lines in SEARCH/REPLACE blocks.
     * Each line must be complete. Never truncate lines mid-way through as this can cause matching failures.
  4. Special operations:
     * To move code: Use two SEARCH/REPLACE blocks (one to delete from original + one to insert at new location)
     * To delete code: Use empty REPLACE section
      ]],
      type = "string",
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "True if the replacement was successful, false otherwise",
    type = "boolean",
  },
  {
    name = "error",
    description = "Error message if the replacement failed",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ path: string, diff: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  if not opts.path or not opts.diff then return false, "path and diff are required" end
  if on_log then on_log("path: " .. opts.path) end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end

  local diff_lines = vim.split(opts.diff, "\n")
  local is_searching = false
  local is_replacing = false
  local current_search = {}
  local current_replace = {}
  local rough_diff_blocks = {}

  for _, line in ipairs(diff_lines) do
    if line:match("^%s*<<<<<<< SEARCH") then
      is_searching = true
      is_replacing = false
      current_search = {}
    elseif line:match("^%s*=======") and is_searching then
      is_searching = false
      is_replacing = true
      current_replace = {}
    elseif line:match("^%s*>>>>>>> REPLACE") and is_replacing then
      is_replacing = false
      table.insert(
        rough_diff_blocks,
        { search = table.concat(current_search, "\n"), replace = table.concat(current_replace, "\n") }
      )
    elseif is_searching then
      table.insert(current_search, line)
    elseif is_replacing then
      table.insert(current_replace, line)
    end
  end

  if #rough_diff_blocks == 0 then return false, "No diff blocks found" end

  local bufnr, err = Helpers.get_bufnr(abs_path)
  if err then return false, err end
  local original_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sidebar = require("avante").get()
  if not sidebar then return false, "Avante sidebar not found" end

  local function parse_rough_diff_block(rough_diff_block, current_lines)
    local old_lines = vim.split(rough_diff_block.search, "\n")
    local new_lines = vim.split(rough_diff_block.replace, "\n")
    local start_line, end_line
    for i = 1, #current_lines - #old_lines + 1 do
      local match = true
      for j = 1, #old_lines do
        if Utils.remove_indentation(current_lines[i + j - 1]) ~= Utils.remove_indentation(old_lines[j]) then
          match = false
          break
        end
      end
      if match then
        start_line = i
        end_line = i + #old_lines - 1
        break
      end
    end
    if start_line == nil or end_line == nil then
      return "Failed to find the old string:\n" .. rough_diff_block.search
    end
    local old_str = rough_diff_block.search
    local new_str = rough_diff_block.replace
    local original_indentation = Utils.get_indentation(current_lines[start_line])
    if original_indentation ~= Utils.get_indentation(old_lines[1]) then
      old_lines = vim.tbl_map(function(line) return original_indentation .. line end, old_lines)
      new_lines = vim.tbl_map(function(line) return original_indentation .. line end, new_lines)
      old_str = table.concat(old_lines, "\n")
      new_str = table.concat(new_lines, "\n")
    end
    rough_diff_block.old_lines = old_lines
    rough_diff_block.new_lines = new_lines
    rough_diff_block.search = old_str
    rough_diff_block.replace = new_str
    rough_diff_block.start_line = start_line
    rough_diff_block.end_line = end_line
    return nil
  end

  local function rough_diff_blocks_to_diff_blocks(rough_diff_blocks_)
    local res = {}
    local base_line_ = 0
    for _, rough_diff_block in ipairs(rough_diff_blocks_) do
      ---@diagnostic disable-next-line: assign-type-mismatch, missing-fields
      local patch = vim.diff(rough_diff_block.search, rough_diff_block.replace, { ---@type integer[][]
        algorithm = "histogram",
        result_type = "indices",
        ctxlen = vim.o.scrolloff,
      })
      for _, hunk in ipairs(patch) do
        local start_a, count_a, start_b, count_b = unpack(hunk)
        local diff_block = {}
        if count_a > 0 then
          diff_block.old_lines = vim.list_slice(rough_diff_block.old_lines, start_a, start_a + count_a - 1)
        else
          diff_block.old_lines = {}
        end
        if count_b > 0 then
          diff_block.new_lines = vim.list_slice(rough_diff_block.new_lines, start_b, start_b + count_b - 1)
        else
          diff_block.new_lines = {}
        end
        if count_a > 0 then
          diff_block.start_line = base_line_ + rough_diff_block.start_line + start_a - 1
        else
          diff_block.start_line = base_line_ + rough_diff_block.start_line + start_a
        end
        diff_block.end_line = base_line_ + rough_diff_block.start_line + start_a + math.max(count_a, 1) - 2
        diff_block.search = table.concat(diff_block.old_lines, "\n")
        diff_block.replace = table.concat(diff_block.new_lines, "\n")
        table.insert(res, diff_block)
      end

      local distance = 0
      for _, hunk in ipairs(patch) do
        local _, count_a, _, count_b = unpack(hunk)
        distance = distance + count_b - count_a
      end

      local old_distance = #rough_diff_block.new_lines - #rough_diff_block.old_lines

      base_line_ = base_line_ + distance - old_distance
    end
    return res
  end

  for _, rough_diff_block in ipairs(rough_diff_blocks) do
    local error = parse_rough_diff_block(rough_diff_block, original_lines)
    if error then
      on_complete(false, error)
      return
    end
  end

  local diff_blocks = rough_diff_blocks_to_diff_blocks(rough_diff_blocks)

  table.sort(diff_blocks, function(a, b) return a.start_line < b.start_line end)

  local base_line = 0
  for _, diff_block in ipairs(diff_blocks) do
    diff_block.new_start_line = diff_block.start_line + base_line
    diff_block.new_end_line = diff_block.new_start_line + #diff_block.new_lines - 1
    base_line = base_line + #diff_block.new_lines - #diff_block.old_lines
  end

  local function remove_diff_block(removed_idx, use_new_lines)
    local new_diff_blocks = {}
    local distance = 0
    for idx, diff_block in ipairs(diff_blocks) do
      if idx == removed_idx then
        if not use_new_lines then distance = #diff_block.old_lines - #diff_block.new_lines end
        goto continue
      end
      if idx > removed_idx then
        diff_block.new_start_line = diff_block.new_start_line + distance
        diff_block.new_end_line = diff_block.new_end_line + distance
      end
      table.insert(new_diff_blocks, diff_block)
      ::continue::
    end

    diff_blocks = new_diff_blocks
  end

  local function get_current_diff_block()
    local winid = Utils.get_winid(bufnr)
    local cursor_line = Utils.get_cursor_pos(winid)
    for idx, diff_block in ipairs(diff_blocks) do
      if cursor_line >= diff_block.new_start_line and cursor_line <= diff_block.new_end_line then
        return diff_block, idx
      end
    end
    return nil, nil
  end

  local function get_prev_diff_block()
    local winid = Utils.get_winid(bufnr)
    local cursor_line = Utils.get_cursor_pos(winid)
    local distance = nil
    local idx = nil
    for i, diff_block in ipairs(diff_blocks) do
      if cursor_line >= diff_block.new_start_line and cursor_line <= diff_block.new_end_line then
        local new_i = i - 1
        if new_i < 1 then return diff_blocks[#diff_blocks] end
        return diff_blocks[new_i]
      end
      if diff_block.new_start_line < cursor_line then
        local distance_ = cursor_line - diff_block.new_start_line
        if distance == nil or distance_ < distance then
          distance = distance_
          idx = i
        end
      end
    end
    if idx ~= nil then return diff_blocks[idx] end
    if #diff_blocks > 0 then return diff_blocks[#diff_blocks] end
    return nil
  end

  local function get_next_diff_block()
    local winid = Utils.get_winid(bufnr)
    local cursor_line = Utils.get_cursor_pos(winid)
    local distance = nil
    local idx = nil
    for i, diff_block in ipairs(diff_blocks) do
      if cursor_line >= diff_block.new_start_line and cursor_line <= diff_block.new_end_line then
        local new_i = i + 1
        if new_i > #diff_blocks then return diff_blocks[1] end
        return diff_blocks[new_i]
      end
      if diff_block.new_start_line > cursor_line then
        local distance_ = diff_block.new_start_line - cursor_line
        if distance == nil or distance_ < distance then
          distance = distance_
          idx = i
        end
      end
    end
    if idx ~= nil then return diff_blocks[idx] end
    if #diff_blocks > 0 then return diff_blocks[1] end
    return nil
  end

  local show_keybinding_hint_extmark_id = nil
  local function register_cursor_move_events()
    local function show_keybinding_hint(lnum)
      if show_keybinding_hint_extmark_id then
        vim.api.nvim_buf_del_extmark(bufnr, KEYBINDING_NAMESPACE, show_keybinding_hint_extmark_id)
      end

      local hint = string.format(
        "[<%s>: OURS, <%s>: THEIRS, <%s>: PREV, <%s>: NEXT]",
        Config.mappings.diff.ours,
        Config.mappings.diff.theirs,
        Config.mappings.diff.prev,
        Config.mappings.diff.next
      )

      show_keybinding_hint_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, KEYBINDING_NAMESPACE, lnum - 1, -1, {
        hl_group = "AvanteInlineHint",
        virt_text = { { hint, "AvanteInlineHint" } },
        virt_text_pos = "right_align",
        priority = PRIORITY,
      })
    end

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinLeave" }, {
      buffer = bufnr,
      callback = function(event)
        local diff_block = get_current_diff_block()
        if (event.event == "CursorMoved" or event.event == "CursorMovedI") and diff_block then
          show_keybinding_hint(diff_block.new_start_line)
        else
          vim.api.nvim_buf_clear_namespace(bufnr, KEYBINDING_NAMESPACE, 0, -1)
        end
      end,
    })
  end

  local confirm
  local has_rejected = false
  local augroup = vim.api.nvim_create_augroup("avante_replace_in_file", { clear = true })

  local function register_buf_write_events()
    vim.api.nvim_create_autocmd({ "BufWritePost" }, {
      buffer = bufnr,
      group = augroup,
      callback = function()
        if #diff_blocks ~= 0 then return end
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
        if confirm then confirm:close() end
        if has_rejected then
          on_complete(false, "User canceled")
          return
        end
        if session_ctx then Helpers.mark_as_not_viewed(opts.path, session_ctx) end
        on_complete(true, nil)
      end,
    })
  end

  local function register_keybinding_events()
    vim.keymap.set({ "n", "v" }, Config.mappings.diff.ours, function()
      if vim.api.nvim_get_current_buf() ~= bufnr then return end
      local diff_block, idx = get_current_diff_block()
      if not diff_block then return end
      pcall(vim.api.nvim_buf_del_extmark, bufnr, NAMESPACE, diff_block.delete_extmark_id)
      pcall(vim.api.nvim_buf_del_extmark, bufnr, NAMESPACE, diff_block.incoming_extmark_id)
      vim.api.nvim_buf_set_lines(
        bufnr,
        diff_block.new_start_line - 1,
        diff_block.new_end_line,
        false,
        diff_block.old_lines
      )
      diff_block.incoming_extmark_id = nil
      diff_block.delete_extmark_id = nil
      remove_diff_block(idx, false)
      local next_diff_block = get_next_diff_block()
      if next_diff_block then
        local winnr = Utils.get_winid(bufnr)
        vim.api.nvim_win_set_cursor(winnr, { next_diff_block.new_start_line, 0 })
        vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
      end
      has_rejected = true
    end)

    vim.keymap.set({ "n", "v" }, Config.mappings.diff.theirs, function()
      if vim.api.nvim_get_current_buf() ~= bufnr then return end
      local diff_block, idx = get_current_diff_block()
      if not diff_block then return end
      pcall(vim.api.nvim_buf_del_extmark, bufnr, NAMESPACE, diff_block.incoming_extmark_id)
      pcall(vim.api.nvim_buf_del_extmark, bufnr, NAMESPACE, diff_block.delete_extmark_id)
      diff_block.incoming_extmark_id = nil
      diff_block.delete_extmark_id = nil
      remove_diff_block(idx, true)
      local next_diff_block = get_next_diff_block()
      if next_diff_block then
        local winnr = Utils.get_winid(bufnr)
        vim.api.nvim_win_set_cursor(winnr, { next_diff_block.new_start_line, 0 })
        vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
      end
    end)

    vim.keymap.set({ "n", "v" }, Config.mappings.diff.next, function()
      if vim.api.nvim_get_current_buf() ~= bufnr then return end
      local diff_block = get_next_diff_block()
      if not diff_block then return end
      local winnr = Utils.get_winid(bufnr)
      vim.api.nvim_win_set_cursor(winnr, { diff_block.new_start_line, 0 })
      vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
    end)

    vim.keymap.set({ "n", "v" }, Config.mappings.diff.prev, function()
      if vim.api.nvim_get_current_buf() ~= bufnr then return end
      local diff_block = get_prev_diff_block()
      if not diff_block then return end
      local winnr = Utils.get_winid(bufnr)
      vim.api.nvim_win_set_cursor(winnr, { diff_block.new_start_line, 0 })
      vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
    end)
  end

  local function unregister_keybinding_events()
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", Config.mappings.diff.ours)
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", Config.mappings.diff.theirs)
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", Config.mappings.diff.next)
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", Config.mappings.diff.prev)
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "v", Config.mappings.diff.ours)
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "v", Config.mappings.diff.theirs)
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "v", Config.mappings.diff.next)
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "v", Config.mappings.diff.prev)
  end

  local function clear()
    if bufnr and not vim.api.nvim_buf_is_valid(bufnr) then return end
    vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, KEYBINDING_NAMESPACE, 0, -1)
    unregister_keybinding_events()
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end

  local function insert_diff_blocks_new_lines()
    local base_line_ = 0
    for _, diff_block in ipairs(diff_blocks) do
      local start_line = diff_block.start_line + base_line_
      local end_line = diff_block.end_line + base_line_
      base_line_ = base_line_ + #diff_block.new_lines - #diff_block.old_lines
      vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, diff_block.new_lines)
    end
  end

  local function highlight_diff_blocks()
    vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
    local base_line_ = 0
    local max_col = vim.o.columns
    for _, diff_block in ipairs(diff_blocks) do
      local start_line = diff_block.start_line + base_line_
      base_line_ = base_line_ + #diff_block.new_lines - #diff_block.old_lines
      local deleted_virt_lines = vim
        .iter(diff_block.old_lines)
        :map(function(line)
          --- append spaces to the end of the line
          local line_ = line .. string.rep(" ", max_col - #line)
          return { { line_, Highlights.TO_BE_DELETED_WITHOUT_STRIKETHROUGH } }
        end)
        :totable()
      local extmark_line = math.max(0, start_line - 2)
      local delete_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, extmark_line, 0, {
        virt_lines = deleted_virt_lines,
        hl_eol = true,
        hl_mode = "combine",
      })
      local end_row = start_line + #diff_block.new_lines - 1
      local incoming_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, start_line - 1, 0, {
        hl_group = Highlights.INCOMING,
        hl_eol = true,
        hl_mode = "combine",
        end_row = end_row,
      })
      diff_block.delete_extmark_id = delete_extmark_id
      diff_block.incoming_extmark_id = incoming_extmark_id
    end
  end

  insert_diff_blocks_new_lines()
  highlight_diff_blocks()
  register_cursor_move_events()
  register_keybinding_events()
  register_buf_write_events()

  if diff_blocks[1] then
    local winnr = Utils.get_winid(bufnr)
    vim.api.nvim_win_set_cursor(winnr, { diff_blocks[1].new_start_line, 0 })
    vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
  end

  confirm = Helpers.confirm("Are you sure you want to apply this modification?", function(ok, reason)
    clear()
    if not ok then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original_lines)
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("noautocmd write") end)
    if session_ctx then Helpers.mark_as_not_viewed(opts.path, session_ctx) end
    on_complete(true, nil)
  end, { focus = not Config.behaviour.auto_focus_on_diff_view }, session_ctx)
end

return M
