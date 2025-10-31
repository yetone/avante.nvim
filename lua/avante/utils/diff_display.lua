---@class avante.utils.diff_display
local M = {}

local Utils = require("avante.utils")
local Highlights = require("avante.highlights")
local Config = require("avante.config")

M.NAMESPACE = vim.api.nvim_create_namespace("avante-diff-display")
M.KEYBINDING_NAMESPACE = vim.api.nvim_create_namespace("avante-diff-keybinding")

---@class avante.DiffDisplayInstance
---@field bufnr integer Buffer number
---@field diff_blocks avante.DiffBlock[] List of diff blocks (mutable reference)
---@field augroup integer Autocommand group ID
---@field show_keybinding_hint_extmark_id integer? Current keybinding hint extmark ID
local DiffDisplayInstance = {}
DiffDisplayInstance.__index = DiffDisplayInstance

---Create a new diff display instance
---@param opts { bufnr: integer, diff_blocks: avante.DiffBlock[], augroup: integer }
---@return avante.DiffDisplayInstance
function M.new(opts)
  local instance = setmetatable({
    bufnr = opts.bufnr,
    diff_blocks = opts.diff_blocks,
    augroup = opts.augroup,
    show_keybinding_hint_extmark_id = nil,
  }, DiffDisplayInstance)

  return instance
end

---Get the current diff block under cursor
---@return avante.DiffBlock?, integer? The diff block and its index, or nil if not found
function DiffDisplayInstance:get_current_diff_block()
  local winid = Utils.get_winid(self.bufnr)
  local cursor_line = Utils.get_cursor_pos(winid)
  for idx, diff_block in ipairs(self.diff_blocks) do
    if cursor_line >= diff_block.new_start_line and cursor_line <= diff_block.new_end_line then
      return diff_block, idx
    end
  end
  return nil, nil
end

---Get the previous diff block
---@return avante.DiffBlock? The previous diff block, or nil if not found
function DiffDisplayInstance:get_prev_diff_block()
  local winid = Utils.get_winid(self.bufnr)
  local cursor_line = Utils.get_cursor_pos(winid)
  local distance = nil
  local idx = nil
  for i, diff_block in ipairs(self.diff_blocks) do
    if cursor_line >= diff_block.new_start_line and cursor_line <= diff_block.new_end_line then
      local new_i = i - 1
      if new_i < 1 then return self.diff_blocks[#self.diff_blocks] end
      return self.diff_blocks[new_i]
    end
    if diff_block.new_start_line < cursor_line then
      local distance_ = cursor_line - diff_block.new_start_line
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
  local cursor_line = Utils.get_cursor_pos(winid)
  local distance = nil
  local idx = nil
  for i, diff_block in ipairs(self.diff_blocks) do
    if cursor_line >= diff_block.new_start_line and cursor_line <= diff_block.new_end_line then
      local new_i = i + 1
      if new_i > #self.diff_blocks then return self.diff_blocks[1] end
      return self.diff_blocks[new_i]
    end
    if diff_block.new_start_line > cursor_line then
      local distance_ = diff_block.new_start_line - cursor_line
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

function DiffDisplayInstance:insert_new_lines()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  local base_line_ = 0
  for _, diff_block in ipairs(self.diff_blocks) do
    local start_line = diff_block.start_line + base_line_
    local end_line = diff_block.end_line + base_line_
    base_line_ = base_line_ + #diff_block.new_lines - #diff_block.old_lines
    vim.api.nvim_buf_set_lines(self.bufnr, start_line - 1, end_line, false, diff_block.new_lines)
  end
end

function DiffDisplayInstance:highlight()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  local line_count = vim.api.nvim_buf_line_count(self.bufnr)
  vim.api.nvim_buf_clear_namespace(self.bufnr, M.NAMESPACE, 0, -1)
  local base_line_ = 0
  local max_col = vim.o.columns
  for _, diff_block in ipairs(self.diff_blocks) do
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
    local end_row = start_line + #diff_block.new_lines - 1
    local delete_extmark_id =
      vim.api.nvim_buf_set_extmark(self.bufnr, M.NAMESPACE, math.min(math.max(end_row - 1, 0), line_count - 1), 0, {
        virt_lines = deleted_virt_lines,
        hl_eol = true,
        hl_mode = "combine",
      })
    local incoming_extmark_id = vim.api.nvim_buf_set_extmark(
      self.bufnr,
      M.NAMESPACE,
      math.min(math.max(start_line - 1, 0), line_count - 1),
      0,
      {
        hl_group = Highlights.INCOMING,
        hl_eol = true,
        hl_mode = "combine",
        end_row = end_row,
      }
    )
    diff_block.delete_extmark_id = delete_extmark_id
    diff_block.incoming_extmark_id = incoming_extmark_id
  end
end

function DiffDisplayInstance:register_navigation_keybindings()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  local keymap_opts = { buffer = self.bufnr }

  vim.keymap.set({ "n", "v" }, Config.mappings.diff.next, function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    if self.show_keybinding_hint_extmark_id then
      vim.api.nvim_buf_del_extmark(self.bufnr, M.KEYBINDING_NAMESPACE, self.show_keybinding_hint_extmark_id)
    end
    local diff_block = self:get_next_diff_block()
    if not diff_block then return end
    local winnr = Utils.get_winid(self.bufnr)
    vim.api.nvim_win_set_cursor(winnr, { diff_block.new_start_line, 0 })
    vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
  end, keymap_opts)

  vim.keymap.set({ "n", "v" }, Config.mappings.diff.prev, function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    if self.show_keybinding_hint_extmark_id then
      vim.api.nvim_buf_del_extmark(self.bufnr, M.KEYBINDING_NAMESPACE, self.show_keybinding_hint_extmark_id)
    end
    local diff_block = self:get_prev_diff_block()
    if not diff_block then return end
    local winnr = Utils.get_winid(self.bufnr)
    vim.api.nvim_win_set_cursor(winnr, { diff_block.new_start_line, 0 })
    vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
  end, keymap_opts)
end

---@param on_accept function(idx: integer) Callback when user accepts a hunk
---@param on_reject function(idx: integer) Callback when user rejects a hunk
function DiffDisplayInstance:register_accept_reject_keybindings(on_accept, on_reject)
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  local keymap_opts = { buffer = self.bufnr }

  -- "co" - Choose OURS (reject incoming changes, keep original)
  vim.keymap.set({ "n", "v" }, Config.mappings.diff.ours, function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    if self.show_keybinding_hint_extmark_id then
      vim.api.nvim_buf_del_extmark(self.bufnr, M.KEYBINDING_NAMESPACE, self.show_keybinding_hint_extmark_id)
    end
    local diff_block, idx = self:get_current_diff_block()
    if not diff_block then return end

    pcall(vim.api.nvim_buf_del_extmark, self.bufnr, M.NAMESPACE, diff_block.delete_extmark_id)
    pcall(vim.api.nvim_buf_del_extmark, self.bufnr, M.NAMESPACE, diff_block.incoming_extmark_id)

    vim.api.nvim_buf_set_lines(
      self.bufnr,
      diff_block.new_start_line - 1,
      diff_block.new_end_line,
      false,
      diff_block.old_lines
    )

    diff_block.incoming_extmark_id = nil
    diff_block.delete_extmark_id = nil

    if on_reject then on_reject(idx) end

    local next_diff_block = self:get_next_diff_block()
    if next_diff_block then
      local winnr = Utils.get_winid(self.bufnr)
      vim.api.nvim_win_set_cursor(winnr, { next_diff_block.new_start_line, 0 })
      vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
    end
  end, keymap_opts)

  -- "ct" - Choose THEIRS (accept incoming changes)
  vim.keymap.set({ "n", "v" }, Config.mappings.diff.theirs, function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    if self.show_keybinding_hint_extmark_id then
      vim.api.nvim_buf_del_extmark(self.bufnr, M.KEYBINDING_NAMESPACE, self.show_keybinding_hint_extmark_id)
    end
    local diff_block, idx = self:get_current_diff_block()
    if not diff_block then return end

    pcall(vim.api.nvim_buf_del_extmark, self.bufnr, M.NAMESPACE, diff_block.incoming_extmark_id)
    pcall(vim.api.nvim_buf_del_extmark, self.bufnr, M.NAMESPACE, diff_block.delete_extmark_id)

    diff_block.incoming_extmark_id = nil
    diff_block.delete_extmark_id = nil

    if on_accept then on_accept(idx) end

    local next_diff_block = self:get_next_diff_block()
    if next_diff_block then
      local winnr = Utils.get_winid(self.bufnr)
      vim.api.nvim_win_set_cursor(winnr, { next_diff_block.new_start_line, 0 })
      vim.api.nvim_win_call(winnr, function() vim.cmd("normal! zz") end)
    end
  end, keymap_opts)
end

function DiffDisplayInstance:register_cursor_move_events()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  local function show_keybinding_hint(lnum)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then return end
    if self.show_keybinding_hint_extmark_id then
      vim.api.nvim_buf_del_extmark(self.bufnr, M.KEYBINDING_NAMESPACE, self.show_keybinding_hint_extmark_id)
    end

    local hint = string.format(
      "[<%s>: OURS, <%s>: THEIRS, <%s>: PREV, <%s>: NEXT]",
      Config.mappings.diff.ours,
      Config.mappings.diff.theirs,
      Config.mappings.diff.prev,
      Config.mappings.diff.next
    )

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
        show_keybinding_hint(diff_block.new_start_line)
      else
        vim.api.nvim_buf_clear_namespace(self.bufnr, M.KEYBINDING_NAMESPACE, 0, -1)
      end
    end,
  })
end

function DiffDisplayInstance:unregister_keybindings()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  pcall(vim.api.nvim_buf_del_keymap, self.bufnr, "n", Config.mappings.diff.ours)
  pcall(vim.api.nvim_buf_del_keymap, self.bufnr, "n", Config.mappings.diff.theirs)
  pcall(vim.api.nvim_buf_del_keymap, self.bufnr, "n", Config.mappings.diff.next)
  pcall(vim.api.nvim_buf_del_keymap, self.bufnr, "n", Config.mappings.diff.prev)
  pcall(vim.api.nvim_buf_del_keymap, self.bufnr, "v", Config.mappings.diff.ours)
  pcall(vim.api.nvim_buf_del_keymap, self.bufnr, "v", Config.mappings.diff.theirs)
  pcall(vim.api.nvim_buf_del_keymap, self.bufnr, "v", Config.mappings.diff.next)
  pcall(vim.api.nvim_buf_del_keymap, self.bufnr, "v", Config.mappings.diff.prev)
end

function DiffDisplayInstance:clear()
  if self.bufnr and not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  vim.api.nvim_buf_clear_namespace(self.bufnr, M.NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.bufnr, M.KEYBINDING_NAMESPACE, 0, -1)
  self:unregister_keybindings()

  pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
end

return M
