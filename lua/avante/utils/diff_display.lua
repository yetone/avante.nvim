---@class avante.utils.diff_display
local M = {}

local Utils = require("avante.utils")
local Highlights = require("avante.highlights")
local Config = require("avante.config")

M.NAMESPACE = vim.api.nvim_create_namespace("avante-diff-display")
M.KEYBINDING_NAMESPACE = vim.api.nvim_create_namespace("avante-diff-keybinding")

---Find character-level changes between two lines
---@param old_line string
---@param new_line string
---@return {old_start: integer, old_end: integer, new_start: integer, new_end: integer}|nil
local function find_inline_change(old_line, new_line)
  if old_line == new_line then return nil end

  -- Find common prefix
  local prefix_len = 0
  local min_len = math.min(#old_line, #new_line)
  for i = 1, min_len do
    if old_line:sub(i, i) == new_line:sub(i, i) then
      prefix_len = i
    else
      break
    end
  end

  -- Find common suffix (after the prefix)
  local suffix_len = 0
  for i = 1, min_len - prefix_len do
    if old_line:sub(#old_line - i + 1, #old_line - i + 1) == new_line:sub(#new_line - i + 1, #new_line - i + 1) then
      suffix_len = i
    else
      break
    end
  end

  -- Calculate change regions
  local old_start = prefix_len
  local old_end = #old_line - suffix_len
  local new_start = prefix_len
  local new_end = #new_line - suffix_len

  -- If no changes found, return nil
  if old_start >= old_end and new_start >= new_end then return nil end

  return {
    old_start = old_start,
    old_end = old_end,
    new_start = new_start,
    new_end = new_end,
  }
end

---@class avante.DiffDisplayInstance
---@field bufnr integer Buffer number
---@field diff_blocks avante.DiffBlock[] List of diff blocks (mutable reference)
---@field augroup integer Autocommand group ID
---@field show_keybinding_hint_extmark_id integer? Current keybinding hint extmark ID
---@field has_accept_reject_keybindings boolean Whether accept/reject keybindings are registered
local DiffDisplayInstance = {}
DiffDisplayInstance.__index = DiffDisplayInstance

---Create a new diff display instance
---@param opts { bufnr: integer, diff_blocks: avante.DiffBlock[] }
---@return avante.DiffDisplayInstance
function M.new(opts)
  local augroup = vim.api.nvim_create_augroup("avante-diff-display-" .. opts.bufnr, { clear = true })
  local instance = setmetatable({
    bufnr = opts.bufnr,
    diff_blocks = opts.diff_blocks,
    augroup = augroup,
    show_keybinding_hint_extmark_id = nil,
    has_accept_reject_keybindings = false,
  }, DiffDisplayInstance)

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    buffer = opts.bufnr,
    group = augroup,
    once = true,
    callback = function() instance:clear() end,
  })

  return instance
end

---Get the current diff block under cursor
---@return avante.DiffBlock?, integer? The diff block and its index, or nil if not found
function DiffDisplayInstance:get_current_diff_block()
  local winid = Utils.get_winid(self.bufnr)
  if not winid then return nil, nil end

  local cursor_line = Utils.get_cursor_pos(winid)

  for idx, diff_block in ipairs(self.diff_blocks) do
    if cursor_line >= diff_block.start_line and cursor_line <= diff_block.end_line then return diff_block, idx end
  end
  return nil, nil
end

---Get the previous diff block
---@return avante.DiffBlock? The previous diff block, or nil if not found
function DiffDisplayInstance:get_prev_diff_block()
  local winid = Utils.get_winid(self.bufnr)

  if not winid then return nil end

  local cursor_line = Utils.get_cursor_pos(winid)
  local distance = nil
  local idx = nil
  for i, diff_block in ipairs(self.diff_blocks) do
    if cursor_line >= diff_block.start_line and cursor_line <= diff_block.end_line then
      local new_i = i - 1
      if new_i < 1 then return self.diff_blocks[#self.diff_blocks] end
      return self.diff_blocks[new_i]
    end
    if diff_block.start_line < cursor_line then
      local distance_ = cursor_line - diff_block.start_line
      if distance == nil or distance_ < distance then
        distance = distance_
        idx = i
      end
    end
  end
  if idx ~= nil then return self.diff_blocks[idx] end
  if #self.diff_blocks > 0 then return self.diff_blocks[#self.diff_blocks] end
  return nil
end

---Get the next diff block
---@return avante.DiffBlock? The next diff block, or nil if not found
function DiffDisplayInstance:get_next_diff_block()
  local winid = Utils.get_winid(self.bufnr)

  if not winid then return nil end

  local cursor_line = Utils.get_cursor_pos(winid)
  local distance = nil
  local idx = nil
  for i, diff_block in ipairs(self.diff_blocks) do
    if cursor_line >= diff_block.start_line and cursor_line <= diff_block.end_line then
      local new_i = i + 1
      if new_i > #self.diff_blocks then return self.diff_blocks[1] end
      return self.diff_blocks[new_i]
    end
    if diff_block.start_line > cursor_line then
      local distance_ = diff_block.start_line - cursor_line
      if distance == nil or distance_ < distance then
        distance = distance_
        idx = i
      end
    end
  end
  if idx ~= nil then return self.diff_blocks[idx] end
  if #self.diff_blocks > 0 then return self.diff_blocks[1] end
  return nil
end

---@param on_complete? function Optional callback to run after scroll completes
function DiffDisplayInstance:scroll_to_first_diff(on_complete)
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end
  if #self.diff_blocks == 0 then return end

  local first_diff = self.diff_blocks[1]
  local bufnr = self.bufnr

  -- Schedule the scroll to happen after the UI settles and confirmation dialog is shown
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local winnr = Utils.get_winid(bufnr)

    -- If buffer is not visible in any window, open it in a suitable window
    if not winnr then
      local sidebar = require("avante").get()
      local target_winid = nil

      -- Try to find a code window (non-sidebar window)
      if
        sidebar
        and sidebar.code.winid
        and sidebar.code.winid ~= 0
        and vim.api.nvim_win_is_valid(sidebar.code.winid)
      then
        target_winid = sidebar.code.winid
      else
        -- Find first non-sidebar window in the current tab
        local all_wins = vim.api.nvim_tabpage_list_wins(0)
        for _, winid in ipairs(all_wins) do
          if vim.api.nvim_win_is_valid(winid) and (not sidebar or not sidebar:is_sidebar_winid(winid)) then
            target_winid = winid
            break
          end
        end
      end

      -- If we found a suitable window, open the buffer in it
      if target_winid then
        pcall(vim.api.nvim_win_set_buf, target_winid, bufnr)
        winnr = target_winid
      else
        return
      end
    end

    if not winnr then return end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local target_line = math.min(first_diff.start_line, line_count)
    local current_win = vim.api.nvim_get_current_win()

    -- Respect auto_focus_on_diff_view config when deciding whether to switch windows
    local should_switch_window = Config.behaviour.auto_focus_on_diff_view and winnr ~= current_win

    if should_switch_window then pcall(vim.api.nvim_set_current_win, winnr) end

    pcall(vim.api.nvim_win_set_cursor, winnr, { target_line, 0 })
    pcall(vim.api.nvim_win_call, winnr, function() vim.cmd("normal! zz") end)

    -- If auto_focus_on_diff_view is true, stay in the code window
    -- Otherwise, return to the original window
    if should_switch_window and not Config.behaviour.auto_focus_on_diff_view then
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(current_win) then pcall(vim.api.nvim_set_current_win, current_win) end
      end)
    end

    -- Call completion callback if provided
    if on_complete and type(on_complete) == "function" then vim.schedule(function() pcall(on_complete) end) end
  end)
end

function DiffDisplayInstance:highlight()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  local line_count = vim.api.nvim_buf_line_count(self.bufnr)
  vim.api.nvim_buf_clear_namespace(self.bufnr, M.NAMESPACE, 0, -1)
  local max_col = vim.o.columns

  for _, diff_block in ipairs(self.diff_blocks) do
    -- Use original positions directly (no offset calculation needed since buffer unchanged)
    local start_line = diff_block.start_line
    local end_line = diff_block.end_line

    local is_modification = #diff_block.old_lines == #diff_block.new_lines and #diff_block.old_lines > 0

    -- Highlight OLD content in buffer with background for DELETED lines
    if #diff_block.old_lines > 0 then
      -- end_row is 0-indexed and exclusive, so use end_line directly
      local end_row = math.min(end_line, line_count)

      local ok_deleted_bg, deleted_bg_extmark_id = pcall(
        vim.api.nvim_buf_set_extmark,
        self.bufnr,
        M.NAMESPACE,
        math.min(math.max(start_line - 1, 0), line_count - 1),
        0,
        {
          hl_group = Highlights.DIFF_DELETED,
          hl_eol = true,
          hl_mode = "combine",
          end_row = end_row,
          priority = 100,
        }
      )

      if ok_deleted_bg then diff_block.delete_extmark_id = deleted_bg_extmark_id end

      -- Word-level highlighting on OLD content in buffer
      if is_modification then
        for i, old_line in ipairs(diff_block.old_lines) do
          local new_line = diff_block.new_lines[i]
          local ok_change, change = pcall(find_inline_change, old_line, new_line)
          if ok_change and change then
            local line_nr = start_line - 1 + (i - 1)

            if change.old_end > change.old_start then
              pcall(vim.api.nvim_buf_set_extmark, self.bufnr, M.NAMESPACE, line_nr, change.old_start, {
                hl_group = Highlights.DIFF_DELETED_WORD,
                end_col = change.old_end,
                priority = 200,
              })
            end
          end
        end
      end
    end

    -- Build virtual lines for NEW content (incoming changes)
    if #diff_block.new_lines > 0 then
      local incoming_virt_lines = {}
      for i, new_line in ipairs(diff_block.new_lines) do
        if is_modification then
          local old_line = diff_block.old_lines[i]
          local ok_change, change = pcall(find_inline_change, old_line, new_line)

          if ok_change and change and change.new_end > change.new_start then
            local virt_line = {}
            if change.new_start > 0 then
              table.insert(virt_line, { new_line:sub(1, change.new_start), Highlights.DIFF_INCOMING })
            end
            table.insert(
              virt_line,
              { new_line:sub(change.new_start + 1, change.new_end), Highlights.DIFF_INCOMING_WORD }
            )

            if change.new_end < #new_line then
              table.insert(virt_line, { new_line:sub(change.new_end + 1), Highlights.DIFF_INCOMING })
            end

            local line_len = #new_line
            if line_len < max_col and max_col > 0 then
              table.insert(virt_line, { string.rep(" ", max_col - line_len), Highlights.DIFF_INCOMING })
            end
            table.insert(incoming_virt_lines, virt_line)
          else
            -- No inline changes, use full line background
            local line_ = new_line .. string.rep(" ", max_col - #new_line)
            table.insert(incoming_virt_lines, { { line_, Highlights.DIFF_INCOMING } })
          end
        else
          -- Pure addition - use full line background
          local line_ = new_line .. string.rep(" ", max_col - #new_line)
          table.insert(incoming_virt_lines, { { line_, Highlights.DIFF_INCOMING } })
        end
      end

      -- Place virtual lines below old content
      local extmark_line = math.min(math.max(end_line - 1, 0), line_count - 1)

      local ok_incoming_virt, incoming_virt_extmark_id =
        pcall(vim.api.nvim_buf_set_extmark, self.bufnr, M.NAMESPACE, extmark_line, 0, {
          virt_lines = incoming_virt_lines,
          virt_lines_above = false,
          hl_eol = true,
          hl_mode = "combine",
        })

      if ok_incoming_virt then diff_block.incoming_extmark_id = incoming_virt_extmark_id end
    end
  end
end

function DiffDisplayInstance:register_navigation_keybindings()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  local keymap_opts = { buffer = self.bufnr }

  vim.keymap.set({ "n", "v" }, Config.mappings.diff.next, function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    if self.show_keybinding_hint_extmark_id then
      pcall(vim.api.nvim_buf_del_extmark, self.bufnr, M.KEYBINDING_NAMESPACE, self.show_keybinding_hint_extmark_id)
      self.show_keybinding_hint_extmark_id = nil
    end
    local diff_block = self:get_next_diff_block()
    if not diff_block then return end
    local winnr = Utils.get_winid(self.bufnr)

    if not winnr then return end

    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    local target_line = math.min(diff_block.start_line, line_count)
    vim.api.nvim_win_set_cursor(winnr, { target_line, 0 })
    vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
  end, keymap_opts)

  vim.keymap.set({ "n", "v" }, Config.mappings.diff.prev, function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    if self.show_keybinding_hint_extmark_id then
      pcall(vim.api.nvim_buf_del_extmark, self.bufnr, M.KEYBINDING_NAMESPACE, self.show_keybinding_hint_extmark_id)
      self.show_keybinding_hint_extmark_id = nil
    end
    local diff_block = self:get_prev_diff_block()
    if not diff_block then return end
    local winnr = Utils.get_winid(self.bufnr)

    if not winnr then return end

    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    local target_line = math.min(diff_block.start_line, line_count)
    vim.api.nvim_win_set_cursor(winnr, { target_line, 0 })
    vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
  end, keymap_opts)
end

---@param on_accept function(idx: integer) Callback when user accepts a hunk
---@param on_reject function(idx: integer) Callback when user rejects a hunk
function DiffDisplayInstance:register_accept_reject_keybindings(on_accept, on_reject)
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  self.has_accept_reject_keybindings = true
  local keymap_opts = { buffer = self.bufnr }

  -- "co" - Choose OURS (reject incoming changes, keep original)
  vim.keymap.set({ "n", "v" }, Config.mappings.diff.ours, function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    local diff_block, idx = self:get_current_diff_block()
    if not diff_block then return end

    -- Clear all extmarks in this diff block's range (background, virtual text, word highlights, and hints)
    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    local clear_start = math.max(0, diff_block.start_line - 1)
    local clear_end = math.min(line_count, diff_block.end_line + 1)
    pcall(vim.api.nvim_buf_clear_namespace, self.bufnr, M.NAMESPACE, clear_start, clear_end)
    pcall(vim.api.nvim_buf_clear_namespace, self.bufnr, M.KEYBINDING_NAMESPACE, clear_start, clear_end)

    -- Clear the stored hint ID
    self.show_keybinding_hint_extmark_id = nil

    diff_block.incoming_extmark_id = nil
    diff_block.delete_extmark_id = nil

    -- Remove the diff block from the list so it's no longer navigable
    table.remove(self.diff_blocks, idx)

    if on_reject then on_reject(idx) end

    -- Navigate to next diff block (if any)
    local next_diff_block = self:get_next_diff_block()
    if next_diff_block then
      local winnr = Utils.get_winid(self.bufnr)
      if not winnr then return end

      vim.api.nvim_win_set_cursor(winnr, { math.min(next_diff_block.start_line, line_count), 0 })
      vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
    end
  end, keymap_opts)

  -- "ct" - Choose THEIRS (accept incoming changes)
  vim.keymap.set({ "n", "v" }, Config.mappings.diff.theirs, function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    local diff_block, idx = self:get_current_diff_block()
    if not diff_block then return end

    local ok = pcall(
      vim.api.nvim_buf_set_lines,
      self.bufnr,
      diff_block.start_line - 1,
      diff_block.end_line,
      false,
      diff_block.new_lines
    )

    if not ok then
      Utils.error("Failed to apply changes to buffer")
      return
    end

    -- Clear all extmarks in this diff block's range (background, virtual text, word highlights, and hints)
    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    local clear_start = math.max(0, diff_block.start_line - 1)
    local clear_end = math.min(line_count, diff_block.start_line - 1 + #diff_block.new_lines + 1)
    pcall(vim.api.nvim_buf_clear_namespace, self.bufnr, M.NAMESPACE, clear_start, clear_end)
    pcall(vim.api.nvim_buf_clear_namespace, self.bufnr, M.KEYBINDING_NAMESPACE, clear_start, clear_end)

    self.show_keybinding_hint_extmark_id = nil

    diff_block.incoming_extmark_id = nil
    diff_block.delete_extmark_id = nil

    -- Remove the diff block from the list so it's no longer navigable
    table.remove(self.diff_blocks, idx)

    if on_accept then on_accept(idx) end

    -- Navigate to next diff block (if any)
    local next_diff_block = self:get_next_diff_block()
    if next_diff_block then
      local winnr = Utils.get_winid(self.bufnr)
      if not winnr then return end

      vim.api.nvim_win_set_cursor(winnr, { math.min(next_diff_block.start_line, line_count), 0 })
      vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
    end
  end, keymap_opts)
end

function DiffDisplayInstance:register_cursor_move_events()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  local function show_keybinding_hint(lnum)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    if self.show_keybinding_hint_extmark_id then
      pcall(vim.api.nvim_buf_del_extmark, self.bufnr, M.KEYBINDING_NAMESPACE, self.show_keybinding_hint_extmark_id)
      self.show_keybinding_hint_extmark_id = nil
    end

    -- Show different hints based on whether accept/reject keybindings are registered
    -- API providers: show OURS/THEIRS/PREV/NEXT (full partial accept/reject support)
    -- ACP providers: show PREV/NEXT only (navigation only, no partial accept/reject)
    local hint
    if not self.has_accept_reject_keybindings then
      hint = string.format("[<%s>: PREV, <%s>: NEXT]", Config.mappings.diff.prev, Config.mappings.diff.next)
    else
      hint = string.format(
        "[<%s>: OURS, <%s>: THEIRS, <%s>: PREV, <%s>: NEXT]",
        Config.mappings.diff.ours,
        Config.mappings.diff.theirs,
        Config.mappings.diff.prev,
        Config.mappings.diff.next
      )
    end

    self.show_keybinding_hint_extmark_id =
      vim.api.nvim_buf_set_extmark(self.bufnr, M.KEYBINDING_NAMESPACE, lnum - 1, -1, {
        hl_group = "AvanteInlineHint",
        virt_text = { { hint, "AvanteInlineHint" } },
        virt_text_pos = "right_align",
        priority = (vim.hl or vim.highlight).priorities.user,
      })
  end

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinLeave" }, {
    buffer = self.bufnr,
    group = self.augroup,
    callback = function(event)
      if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
      local diff_block = self:get_current_diff_block()
      if (event.event == "CursorMoved" or event.event == "CursorMovedI") and diff_block then
        show_keybinding_hint(diff_block.start_line)
      else
        vim.api.nvim_buf_clear_namespace(self.bufnr, M.KEYBINDING_NAMESPACE, 0, -1)
      end
    end,
  })
end

function DiffDisplayInstance:unregister_keybindings()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  -- We need to pcall each del separately to avoid stopping on first error, `del` errors if keymap doesn't exist
  pcall(vim.keymap.del, "n", Config.mappings.diff.next, { buffer = self.bufnr })
  pcall(vim.keymap.del, "v", Config.mappings.diff.next, { buffer = self.bufnr })
  pcall(vim.keymap.del, "n", Config.mappings.diff.prev, { buffer = self.bufnr })
  pcall(vim.keymap.del, "v", Config.mappings.diff.prev, { buffer = self.bufnr })
  pcall(vim.keymap.del, "n", Config.mappings.diff.ours, { buffer = self.bufnr })
  pcall(vim.keymap.del, "v", Config.mappings.diff.ours, { buffer = self.bufnr })
  pcall(vim.keymap.del, "n", Config.mappings.diff.theirs, { buffer = self.bufnr })
  pcall(vim.keymap.del, "v", Config.mappings.diff.theirs, { buffer = self.bufnr })
end

function DiffDisplayInstance:clear()
  self:unregister_keybindings()

  pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
  pcall(vim.api.nvim_buf_clear_namespace, self.bufnr, M.NAMESPACE, 0, -1)
  pcall(vim.api.nvim_buf_clear_namespace, self.bufnr, M.KEYBINDING_NAMESPACE, 0, -1)

  -- Clear extmark IDs from diff_blocks to help GC
  for _, block in ipairs(self.diff_blocks or {}) do
    block.incoming_extmark_id = nil
    block.delete_extmark_id = nil
  end

  -- Clear references to help GC
  self.bufnr = nil
  self.diff_blocks = nil
  self.augroup = nil
  self.show_keybinding_hint_extmark_id = nil
end

return M
