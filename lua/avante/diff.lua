-- This file COPY and MODIFIED based on: https://github.com/akinsho/git-conflict.nvim/blob/main/lua/git-conflict.lua

local M = {}

local Config = require("avante.config")
local Utils = require("avante.utils")
local Highlights = require("avante.highlights")

local fn = vim.fn
local api = vim.api
local fmt = string.format
local map = vim.keymap.set
-----------------------------------------------------------------------------//
-- REFERENCES:
-----------------------------------------------------------------------------//
-- Detecting the state of a git repository based on files in the .git directory.
-- https://stackoverflow.com/questions/49774200/how-to-tell-if-my-git-repo-is-in-a-conflict
-- git diff commands to git a list of conflicted files
-- https://stackoverflow.com/questions/3065650/whats-the-simplest-way-to-list-conflicted-files-in-git
-- how to show a full path for files in a git diff command
-- https://stackoverflow.com/questions/10459374/making-git-diff-stat-show-full-file-path
-- Advanced merging
-- https://git-scm.com/book/en/v2/Git-Tools-Advanced-Merging

-----------------------------------------------------------------------------//
-- Types
-----------------------------------------------------------------------------//

---@alias ConflictSide "'ours'"|"'theirs'"|"'both'"|"'cursor'"|"'base'"|"'none'"

--- @class AvanteConflictHighlights
--- @field current string
--- @field incoming string
--- @field ancestor string?

---@class RangeMark
---@field label integer
---@field content string

--- @class PositionMarks
--- @field current RangeMark
--- @field incoming RangeMark
--- @field ancestor RangeMark

--- @class Range
--- @field range_start integer
--- @field range_end integer
--- @field content_start integer
--- @field content_end integer

--- @class ConflictPosition
--- @field incoming Range
--- @field middle Range
--- @field current Range
--- @field marks PositionMarks

--- @class ConflictBufferCache
--- @field lines table<integer, boolean> map of conflicted line numbers
--- @field positions ConflictPosition[]
--- @field tick integer
--- @field bufnr integer

-----------------------------------------------------------------------------//
-- Constants
-----------------------------------------------------------------------------//
---@enum AvanteConflictSides
local SIDES = {
  OURS = "ours",
  THEIRS = "theirs",
  BOTH = "both",
  BASE = "base",
  NONE = "none",
  CURSOR = "cursor",
}

-- A mapping between the internal names and the display names
local name_map = {
  ours = "current",
  theirs = "incoming",
  base = "ancestor",
  both = "both",
  none = "none",
  cursor = "cursor",
}

local CURRENT_HL = "AvanteConflictCurrent"
local INCOMING_HL = "AvanteConflictIncoming"
local ANCESTOR_HL = "AvanteConflictAncestor"
local CURRENT_LABEL_HL = "AvanteConflictCurrentLabel"
local INCOMING_LABEL_HL = "AvanteConflictIncomingLabel"
local ANCESTOR_LABEL_HL = "AvanteConflictAncestorLabel"
local PRIORITY = vim.highlight.priorities.user
local NAMESPACE = api.nvim_create_namespace("avante-conflict")
local KEYBINDING_NAMESPACE = api.nvim_create_namespace("avante-conflict-keybinding")
local AUGROUP_NAME = "avante_conflicts"

local conflict_start = "^<<<<<<<"
local conflict_middle = "^======="
local conflict_end = "^>>>>>>>"
local conflict_ancestor = "^|||||||"

local DEFAULT_CURRENT_BG_COLOR = 4218238 -- #405d7e
local DEFAULT_INCOMING_BG_COLOR = 3229523 -- #314753
local DEFAULT_ANCESTOR_BG_COLOR = 6824314 -- #68217A
-----------------------------------------------------------------------------//

--- @return table<string, ConflictBufferCache>
local function create_visited_buffers()
  return setmetatable({}, {
    __index = function(t, k)
      if type(k) == "number" then
        return t[api.nvim_buf_get_name(k)]
      end
    end,
  })
end

--- A list of buffers that have conflicts in them. This is derived from
--- git using the diff command, and updated at intervals
local visited_buffers = create_visited_buffers()

-----------------------------------------------------------------------------//

---Add the positions to the buffer in our in memory buffer list
---positions are keyed by a list of range start and end for each mark
---@param buf integer
---@param positions ConflictPosition[]
local function update_visited_buffers(buf, positions)
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  local name = api.nvim_buf_get_name(buf)
  -- If this buffer is not in the list
  if not visited_buffers[name] then
    return
  end
  visited_buffers[name].bufnr = buf
  visited_buffers[name].tick = vim.b[buf].changedtick
  visited_buffers[name].positions = positions
end

function M.add_visited_buffer(bufnr)
  local name = api.nvim_buf_get_name(bufnr)
  visited_buffers[name] = visited_buffers[name] or {}
end

---Set an extmark for each section of the git conflict
---@param bufnr integer
---@param hl string
---@param range_start integer
---@param range_end integer
---@return integer? extmark_id
local function hl_range(bufnr, hl, range_start, range_end)
  if not range_start or not range_end then
    return
  end
  return api.nvim_buf_set_extmark(bufnr, NAMESPACE, range_start, 0, {
    hl_group = hl,
    hl_eol = true,
    hl_mode = "combine",
    end_row = range_end,
    priority = PRIORITY,
  })
end

---Add highlights and additional data to each section heading of the conflict marker
---These works by covering the underlying text with an extmark that contains the same information
---with some extra detail appended.
---TODO: ideally this could be done by using virtual text at the EOL and highlighting the
---background but this doesn't work and currently this is done by filling the rest of the line with
---empty space and overlaying the line content
---@param bufnr integer
---@param hl_group string
---@param label string
---@param lnum integer
---@return integer extmark id
local function draw_section_label(bufnr, hl_group, label, lnum)
  local remaining_space = api.nvim_win_get_width(0) - api.nvim_strwidth(label)
  return api.nvim_buf_set_extmark(bufnr, NAMESPACE, lnum, 0, {
    hl_group = hl_group,
    virt_text = { { label .. string.rep(" ", remaining_space), hl_group } },
    virt_text_pos = "overlay",
    priority = PRIORITY,
  })
end

---Highlight each part of a git conflict i.e. the incoming changes vs the current/HEAD changes
---TODO: should extmarks be ephemeral? or is it less expensive to save them and only re-apply
---them when a buffer changes since otherwise we have to reparse the whole buffer constantly
---@param positions table
---@param lines string[]
local function highlight_conflicts(positions, lines)
  local bufnr = api.nvim_get_current_buf()
  M.clear(bufnr)

  for _, position in ipairs(positions) do
    local current_start = position.current.range_start
    local current_end = position.current.range_end
    local incoming_start = position.incoming.range_start
    local incoming_end = position.incoming.range_end
    -- Add one since the index access in lines is 1 based
    local current_label = lines[current_start + 1] .. " (Current changes)"
    local incoming_label = lines[incoming_end + 1] .. " (Incoming changes)"

    local curr_label_id = draw_section_label(bufnr, CURRENT_LABEL_HL, current_label, current_start)
    local curr_id = hl_range(bufnr, CURRENT_HL, current_start, current_end + 1)
    local inc_id = hl_range(bufnr, INCOMING_HL, incoming_start, incoming_end + 1)
    local inc_label_id = draw_section_label(bufnr, INCOMING_LABEL_HL, incoming_label, incoming_end)

    position.marks = {
      current = { label = curr_label_id, content = curr_id },
      incoming = { label = inc_label_id, content = inc_id },
      ancestor = {},
    }
    if not vim.tbl_isempty(position.ancestor) then
      local ancestor_start = position.ancestor.range_start
      local ancestor_end = position.ancestor.range_end
      local ancestor_label = lines[ancestor_start + 1] .. " (Base changes)"
      local id = hl_range(bufnr, ANCESTOR_HL, ancestor_start + 1, ancestor_end + 1)
      local label_id = draw_section_label(bufnr, ANCESTOR_LABEL_HL, ancestor_label, ancestor_start)
      position.marks.ancestor = { label = label_id, content = id }
    end
  end
end

---Iterate through the buffer line by line checking there is a matching conflict marker
---when we find a starting mark we collect the position details and add it to a list of positions
---@param lines string[]
---@return boolean
---@return ConflictPosition[]
local function detect_conflicts(lines)
  local positions = {}
  local position, has_middle, has_ancestor = nil, false, false
  for index, line in ipairs(lines) do
    local lnum = index - 1
    if line:match(conflict_start) then
      position = {
        current = { range_start = lnum, content_start = lnum + 1 },
        middle = {},
        incoming = {},
        ancestor = {},
      }
    end
    if position ~= nil and line:match(conflict_ancestor) then
      has_ancestor = true
      position.ancestor.range_start = lnum
      position.ancestor.content_start = lnum + 1
      position.current.range_end = lnum - 1
      position.current.content_end = lnum - 1
    end
    if position ~= nil and line:match(conflict_middle) then
      has_middle = true
      if has_ancestor then
        position.ancestor.content_end = lnum - 1
        position.ancestor.range_end = lnum - 1
      else
        position.current.range_end = lnum - 1
        position.current.content_end = lnum - 1
      end
      position.middle.range_start = lnum
      position.middle.range_end = lnum + 1
      position.incoming.range_start = lnum + 1
      position.incoming.content_start = lnum + 1
    end
    if position ~= nil and has_middle and line:match(conflict_end) then
      position.incoming.range_end = lnum
      position.incoming.content_end = lnum - 1
      positions[#positions + 1] = position

      position, has_middle, has_ancestor = nil, false, false
    end
  end
  return #positions > 0, positions
end

---Helper function to find a conflict position based on a comparator function
---@param bufnr integer
---@param comparator fun(string, integer): boolean
---@param opts table?
---@return ConflictPosition?
local function find_position(bufnr, comparator, opts)
  local match = visited_buffers[bufnr]
  if not match then
    return
  end
  local line = Utils.get_cursor_pos()
  line = line - 1 -- Convert to 0-based for position comparison

  if opts and opts.reverse then
    for i = #match.positions, 1, -1 do
      local position = match.positions[i]
      if comparator(line, position) then
        return position
      end
    end
    return nil
  end

  for _, position in ipairs(match.positions) do
    if comparator(line, position) then
      return position
    end
  end
  return nil
end

---Retrieves a conflict marker position by checking the visited buffers for a supported range
---@param bufnr integer
---@return ConflictPosition?
local function get_current_position(bufnr)
  return find_position(bufnr, function(line, position)
    return position.current.range_start <= line and position.incoming.range_end >= line
  end)
end

---@param position ConflictPosition?
---@param side ConflictSide
local function set_cursor(position, side)
  if not position then
    return
  end
  local target = side == SIDES.OURS and position.current or position.incoming
  api.nvim_win_set_cursor(0, { target.range_start + 1, 0 })
end

local show_keybinding_hint_extmark_id = nil
local function register_cursor_move_events(bufnr)
  local function show_keybinding_hint(lnum)
    if show_keybinding_hint_extmark_id then
      api.nvim_buf_del_extmark(bufnr, KEYBINDING_NAMESPACE, show_keybinding_hint_extmark_id)
    end

    local hint = string.format(
      "[<%s> for OURS, <%s> for THEIRS, <%s> for BOTH, <%s> for CURSOR, <%s> for PREV, <%s> for NEXT]",
      Config.diff.mappings.ours,
      Config.diff.mappings.theirs,
      Config.diff.mappings.both,
      Config.diff.mappings.cursor,
      Config.diff.mappings.prev,
      Config.diff.mappings.next
    )
    local win_width = api.nvim_win_get_width(0)
    local col = win_width - #hint - math.ceil(win_width * 0.3) - 4

    if col < 0 then
      col = 0
    end

    show_keybinding_hint_extmark_id = api.nvim_buf_set_extmark(bufnr, KEYBINDING_NAMESPACE, lnum - 1, -1, {
      hl_group = "Keyword",
      virt_text = { { hint, "Keyword" } },
      virt_text_pos = "right_align",
      priority = PRIORITY,
    })
  end

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = bufnr,
    callback = function()
      local position = get_current_position(bufnr)

      if position then
        show_keybinding_hint(position.current.range_start + 1)
      else
        api.nvim_buf_clear_namespace(bufnr, KEYBINDING_NAMESPACE, 0, -1)
      end
    end,
  })
end

---Get the conflict marker positions for a buffer if any and update the buffers state
---@param bufnr integer
---@param range_start? integer
---@param range_end? integer
local function parse_buffer(bufnr, range_start, range_end)
  local lines = Utils.get_buf_lines(range_start or 0, range_end or -1, bufnr)
  local prev_conflicts = visited_buffers[bufnr].positions ~= nil and #visited_buffers[bufnr].positions > 0
  local has_conflict, positions = detect_conflicts(lines)

  update_visited_buffers(bufnr, positions)
  if has_conflict then
    register_cursor_move_events(bufnr)
    highlight_conflicts(positions, lines)
  else
    M.clear(bufnr)
  end
  if prev_conflicts ~= has_conflict or not vim.b[bufnr].conflict_mappings_set then
    local pattern = has_conflict and "AvanteConflictDetected" or "AvanteConflictResolved"
    api.nvim_exec_autocmds("User", { pattern = pattern })
  end
end

---Process a buffer if the changed tick has changed
---@param bufnr integer?
function M.process(bufnr, range_start, range_end)
  bufnr = bufnr or api.nvim_get_current_buf()
  if visited_buffers[bufnr] and visited_buffers[bufnr].tick == vim.b[bufnr].changedtick then
    return
  end
  parse_buffer(bufnr, range_start, range_end)
end

-----------------------------------------------------------------------------//
-- Commands
-----------------------------------------------------------------------------//

local function set_commands()
  local command = api.nvim_create_user_command
  command("AvanteConflictListQf", function()
    M.conflicts_to_qf_items(function(items)
      if #items > 0 then
        fn.setqflist(items, "r")
        if type(Config.diff.list_opener) == "function" then
          Config.diff.list_opener()
        else
          vim.cmd(Config.diff.list_opener)
        end
      end
    end)
  end, { nargs = 0 })
  command("AvanteConflictChooseOurs", function()
    M.choose("ours")
  end, { nargs = 0 })
  command("AvanteConflictChooseTheirs", function()
    M.choose("theirs")
  end, { nargs = 0 })
  command("AvanteConflictChooseBoth", function()
    M.choose("both")
  end, { nargs = 0 })
  command("AvanteConflictChooseCursor", function()
    M.choose("cursor")
  end, { nargs = 0 })
  command("AvanteConflictChooseBase", function()
    M.choose("base")
  end, { nargs = 0 })
  command("AvanteConflictChooseNone", function()
    M.choose("none")
  end, { nargs = 0 })
  command("AvanteConflictNextConflict", function()
    M.find_next("ours")
  end, { nargs = 0 })
  command("AvanteConflictPrevConflict", function()
    M.find_prev("ours")
  end, { nargs = 0 })
end

-----------------------------------------------------------------------------//
-- Mappings
-----------------------------------------------------------------------------//

local function set_plug_mappings()
  local function opts(desc)
    return { silent = true, desc = "Git Conflict: " .. desc }
  end

  map({ "n", "v" }, "<Plug>(git-conflict-ours)", "<Cmd>AvanteConflictChooseOurs<CR>", opts("Choose Ours"))
  map({ "n", "v" }, "<Plug>(git-conflict-both)", "<Cmd>AvanteConflictChooseBoth<CR>", opts("Choose Both"))
  map({ "n", "v" }, "<Plug>(git-conflict-none)", "<Cmd>AvanteConflictChooseNone<CR>", opts("Choose None"))
  map({ "n", "v" }, "<Plug>(git-conflict-theirs)", "<Cmd>AvanteConflictChooseTheirs<CR>", opts("Choose Theirs"))
  map("n", "<Plug>(git-conflict-cursor)", "<Cmd>AvanteConflictChooseCursor<CR>", opts("Choose Cursor"))
  map("n", "<Plug>(git-conflict-next-conflict)", "<Cmd>AvanteConflictNextConflict<CR>", opts("Next Conflict"))
  map("n", "<Plug>(git-conflict-prev-conflict)", "<Cmd>AvanteConflictPrevConflict<CR>", opts("Previous Conflict"))
end

---@param bufnr integer given buffer id
local function setup_buffer_mappings(bufnr)
  ---@param desc string
  local function opts(desc)
    return { silent = true, buffer = bufnr, desc = "Git Conflict: " .. desc }
  end

  map({ "n", "v" }, Config.diff.mappings.ours, "<Plug>(git-conflict-ours)", opts("Choose Ours"))
  map({ "n", "v" }, Config.diff.mappings.both, "<Plug>(git-conflict-both)", opts("Choose Both"))
  map({ "n", "v" }, Config.diff.mappings.none, "<Plug>(git-conflict-none)", opts("Choose None"))
  map({ "n", "v" }, Config.diff.mappings.theirs, "<Plug>(git-conflict-theirs)", opts("Choose Theirs"))
  map({ "v", "v" }, Config.diff.mappings.ours, "<Plug>(git-conflict-ours)", opts("Choose Ours"))
  map("n", Config.diff.mappings.cursor, "<Plug>(git-conflict-cursor)", opts("Choose Cursor"))
  -- map('V', Config.diff.mappings.ours, '<Plug>(git-conflict-ours)', opts('Choose Ours'))
  map("n", Config.diff.mappings.prev, "<Plug>(git-conflict-prev-conflict)", opts("Previous Conflict"))
  map("n", Config.diff.mappings.next, "<Plug>(git-conflict-next-conflict)", opts("Next Conflict"))
  vim.b[bufnr].conflict_mappings_set = true
end

---@param key string
---@param mode "'n'|'v'|'o'|'nv'|'nvo'"?
---@return boolean
local function is_mapped(key, mode)
  return fn.hasmapto(key, mode or "n") > 0
end

local function clear_buffer_mappings(bufnr)
  if not bufnr or not vim.b[bufnr].conflict_mappings_set then
    return
  end
  for _, mapping in pairs(Config.diff.mappings) do
    if is_mapped(mapping) then
      api.nvim_buf_del_keymap(bufnr, "n", mapping)
    end
  end
  vim.b[bufnr].conflict_mappings_set = false
end

function M.setup()
  Highlights.conflict_highlights()

  set_commands()

  set_plug_mappings()

  local augroup = api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

  local is_inlay_enable = vim.lsp.inlay_hint and vim.lsp.inlay_hint.is_enabled() or false
  local previous_inlay = nil

  api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "AvanteConflictDetected",
    callback = function(ev)
      vim.diagnostic.enable(false, { bufnr = ev.buf })
      if is_inlay_enable then
        previous_inlay = vim.lsp.inlay_hint.is_enabled({ bufnr = ev.buf })
        vim.lsp.inlay_hint.enable(false, { bufnr = ev.buf })
      end
      setup_buffer_mappings(ev.buf)
    end,
  })

  api.nvim_create_autocmd("User", {
    group = AUGROUP_NAME,
    pattern = "AvanteConflictResolved",
    callback = function(ev)
      vim.diagnostic.enable(true, { bufnr = ev.buf })
      if is_inlay_enable then
        vim.lsp.inlay_hint.enable(previous_inlay, { bufnr = ev.buf })
        previous_inlay = nil
      end
      clear_buffer_mappings(ev.buf)
    end,
  })

  api.nvim_set_decoration_provider(NAMESPACE, {
    on_buf = function(_, bufnr, _)
      return Utils.is_valid_buf(bufnr)
    end,
    on_win = function(_, _, bufnr, _, _)
      if visited_buffers[bufnr] then
        M.process(bufnr)
      end
    end,
  })
end

--- Add additional metadata to a quickfix entry if we have already visited the buffer and have that
--- information
---@param item table<string, integer|string>
---@param items table<string, integer|string>[]
---@param visited_buf ConflictBufferCache
local function quickfix_items_from_positions(item, items, visited_buf)
  if vim.tbl_isempty(visited_buf.positions) then
    return
  end
  for _, pos in ipairs(visited_buf.positions) do
    for key, value in pairs(pos) do
      if vim.tbl_contains({ name_map.ours, name_map.theirs, name_map.base }, key) and not vim.tbl_isempty(value) then
        local lnum = value.range_start + 1
        local next_item = vim.deepcopy(item)
        next_item.text = fmt("%s change", key, lnum)
        next_item.lnum = lnum
        next_item.col = 0
        table.insert(items, next_item)
      end
    end
  end
end

--- Convert the conflicts detected via get conflicted files into a list of quickfix entries.
---@param callback fun(files: table<string, integer[]>)
function M.conflicts_to_qf_items(callback)
  local items = {}
  for filename, visited_buf in pairs(visited_buffers) do
    local item = {
      filename = filename,
      pattern = conflict_start,
      text = "git conflict",
      type = "E",
      valid = 1,
    }

    if visited_buf and next(visited_buf) then
      quickfix_items_from_positions(item, items, visited_buf)
    else
      table.insert(items, item)
    end
  end

  callback(items)
end

---@param bufnr integer?
function M.clear(bufnr)
  if bufnr and not api.nvim_buf_is_valid(bufnr) then
    return
  end
  bufnr = bufnr or 0
  api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  api.nvim_buf_clear_namespace(bufnr, KEYBINDING_NAMESPACE, 0, -1)
end

---@param side ConflictSide
function M.find_next(side)
  local pos = find_position(0, function(line, position)
    return position.current.range_start >= line and position.incoming.range_end >= line
  end)
  set_cursor(pos, side)
end

---@param side ConflictSide
function M.find_prev(side)
  local pos = find_position(0, function(line, position)
    return position.current.range_start <= line and position.incoming.range_end <= line
  end, { reverse = true })
  set_cursor(pos, side)
end

---Select the changes to keep
---@param side ConflictSide
function M.choose(side)
  local bufnr = api.nvim_get_current_buf()
  if vim.fn.mode() == "v" or vim.fn.mode() == "V" or vim.fn.mode() == "" then
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
    -- have to defer so that the < and > marks are set
    vim.defer_fn(function()
      local start = api.nvim_buf_get_mark(0, "<")[1]
      local finish = api.nvim_buf_get_mark(0, ">")[1]
      local position = find_position(bufnr, function(line, pos)
        local left = pos.current.range_start >= start - 1
        local right = pos.incoming.range_end <= finish + 1
        return left and right
      end)
      while position ~= nil do
        local lines = {}
        if vim.tbl_contains({ SIDES.OURS, SIDES.THEIRS, SIDES.BASE }, side) then
          local data = position[name_map[side]]
          lines = Utils.get_buf_lines(data.content_start, data.content_end + 1)
        elseif side == SIDES.BOTH then
          local first = Utils.get_buf_lines(position.current.content_start, position.current.content_end + 1)
          local second = Utils.get_buf_lines(position.incoming.content_start, position.incoming.content_end + 1)
          lines = vim.list_extend(first, second)
        elseif side == SIDES.NONE then
          lines = {}
        else
          return
        end

        local pos_start = position.current.range_start < 0 and 0 or position.current.range_start
        local pos_end = position.incoming.range_end + 1

        api.nvim_buf_set_lines(0, pos_start, pos_end, false, lines)
        api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.incoming.label)
        api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.current.label)
        if position.marks.ancestor.label then
          api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.ancestor.label)
        end
        parse_buffer(bufnr)
        position = find_position(bufnr, function(line, pos)
          local left = pos.current.range_start >= start - 1
          local right = pos.incoming.range_end <= finish + 1
          return left and right
        end)
      end
    end, 50)
    if Config.diff.autojump then
      M.find_next(side)
      vim.cmd([[normal! zz]])
    end
    return
  end
  local position = get_current_position(bufnr)
  if not position then
    return
  end
  local lines = {}
  if vim.tbl_contains({ SIDES.OURS, SIDES.THEIRS, SIDES.BASE }, side) then
    local data = position[name_map[side]]
    lines = Utils.get_buf_lines(data.content_start, data.content_end + 1)
  elseif side == SIDES.BOTH then
    local first = Utils.get_buf_lines(position.current.content_start, position.current.content_end + 1)
    local second = Utils.get_buf_lines(position.incoming.content_start, position.incoming.content_end + 1)
    lines = vim.list_extend(first, second)
  elseif side == SIDES.NONE then
    lines = {}
  elseif side == SIDES.CURSOR then
    local cursor_line = Utils.get_cursor_pos()
    for _, pos in ipairs({ SIDES.OURS, SIDES.THEIRS, SIDES.BASE }) do
      local data = position[name_map[pos]] or {}
      if data.range_start and data.range_start + 1 <= cursor_line and data.range_end + 1 >= cursor_line then
        side = pos
        lines = Utils.get_buf_lines(data.content_start, data.content_end + 1)
        break
      end
    end
    if side == SIDES.CURSOR then
      return
    end
  else
    return
  end

  local pos_start = position.current.range_start < 0 and 0 or position.current.range_start
  local pos_end = position.incoming.range_end + 1

  api.nvim_buf_set_lines(0, pos_start, pos_end, false, lines)
  api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.incoming.label)
  api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.current.label)
  if position.marks.ancestor.label then
    api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.ancestor.label)
  end
  parse_buffer(bufnr)
  if Config.diff.autojump then
    M.find_next(side)
    vim.cmd([[normal! zz]])
  end
end

function M.conflict_count(bufnr)
  if bufnr and not api.nvim_buf_is_valid(bufnr) then
    return 0
  end
  bufnr = bufnr or 0

  local name = api.nvim_buf_get_name(bufnr)
  if not visited_buffers[name] then
    return 0
  end

  return #visited_buffers[name].positions
end

return M
