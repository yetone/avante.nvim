-- This file COPY and MODIFIED based on: https://github.com/akinsho/git-conflict.nvim/blob/main/lua/git-conflict.lua

local M = {}

local color = require("avante.diff.colors")
local utils = require("avante.diff.utils")

local fn = vim.fn
local api = vim.api
local fmt = string.format
local map = vim.keymap.set
local job = utils.job
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

---@alias ConflictSide "'ours'"|"'theirs'"|"'both'"|"'base'"|"'none'"

--- @class ConflictHighlights
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

--- @class AvanteConflictMappings
--- @field ours string
--- @field theirs string
--- @field none string
--- @field both string
--- @field next string
--- @field prev string

--- @class AvanteConflictConfig
--- @field default_mappings AvanteConflictMappings
--- @field disable_diagnostics boolean
--- @field list_opener string|function
--- @field highlights ConflictHighlights
--- @field debug boolean

--- @class AvanteConflictUserConfig
--- @field default_mappings boolean|AvanteConflictMappings
--- @field disable_diagnostics boolean
--- @field list_opener string|function
--- @field highlights ConflictHighlights
--- @field debug boolean

-----------------------------------------------------------------------------//
-- Constants
-----------------------------------------------------------------------------//
local SIDES = {
  OURS = "ours",
  THEIRS = "theirs",
  BOTH = "both",
  BASE = "base",
  NONE = "none",
}

-- A mapping between the internal names and the display names
local name_map = {
  ours = "current",
  theirs = "incoming",
  base = "ancestor",
  both = "both",
  none = "none",
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
local AUGROUP_NAME = "AvanteConflictCommands"

local conflict_start = "^<<<<<<<"
local conflict_middle = "^======="
local conflict_end = "^>>>>>>>"
local conflict_ancestor = "^|||||||"

local DEFAULT_CURRENT_BG_COLOR = 4218238 -- #405d7e
local DEFAULT_INCOMING_BG_COLOR = 3229523 -- #314753
local DEFAULT_ANCESTOR_BG_COLOR = 6824314 -- #68217A
-----------------------------------------------------------------------------//

--- @type AvanteConflictMappings
local DEFAULT_MAPPINGS = {
  ours = "co",
  theirs = "ct",
  none = "c0",
  both = "cb",
  next = "]x",
  prev = "[x",
}

--- @type AvanteConflictConfig
local config = {
  debug = false,
  default_mappings = DEFAULT_MAPPINGS,
  default_commands = true,
  disable_diagnostics = false,
  list_opener = "copen",
  highlights = {
    current = "DiffText",
    incoming = "DiffAdd",
    ancestor = nil,
  },
}

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
  local position, has_start, has_middle, has_ancestor = nil, false, false, false
  for index, line in ipairs(lines) do
    local lnum = index - 1
    if line:match(conflict_start) then
      has_start = true
      position = {
        current = { range_start = lnum, content_start = lnum + 1 },
        middle = {},
        incoming = {},
        ancestor = {},
      }
    end
    if has_start and line:match(conflict_ancestor) then
      has_ancestor = true
      position.ancestor.range_start = lnum
      position.ancestor.content_start = lnum + 1
      position.current.range_end = lnum - 1
      position.current.content_end = lnum - 1
    end
    if has_start and line:match(conflict_middle) then
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
    if has_start and has_middle and line:match(conflict_end) then
      position.incoming.range_end = lnum
      position.incoming.content_end = lnum - 1
      positions[#positions + 1] = position

      position, has_start, has_middle, has_ancestor = nil, false, false, false
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
  local line = utils.get_cursor_pos()
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

local function register_cursor_move_events(bufnr)
  local show_keybinding_hint_extmark_id = nil

  local function show_keybinding_hint(lnum)
    if show_keybinding_hint_extmark_id then
      api.nvim_buf_del_extmark(bufnr, KEYBINDING_NAMESPACE, show_keybinding_hint_extmark_id)
    end

    local hint = string.format(
      " [Press <%s> for CHOICE OURS, <%s> for CHOICE THEIRS, <%s> for PREV, <%s> for NEXT] ",
      config.default_mappings.ours,
      config.default_mappings.theirs,
      config.default_mappings.prev,
      config.default_mappings.next
    )
    local win_width = api.nvim_win_get_width(0)
    local col = win_width - #hint - math.ceil(win_width * 0.3) - 4

    if col < 0 then
      col = 0
    end

    show_keybinding_hint_extmark_id = api.nvim_buf_set_extmark(bufnr, KEYBINDING_NAMESPACE, lnum - 1, -1, {
      hl_group = "Keyword",
      virt_text = { { hint, "Keyword" } },
      virt_text_win_col = col,
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
---@param range_start integer
---@param range_end integer
local function parse_buffer(bufnr, range_start, range_end)
  local lines = utils.get_buf_lines(range_start or 0, range_end or -1, bufnr)
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
        if type(config.list_opener) == "function" then
          config.list_opener()
        else
          vim.cmd(config.list_opener)
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
  map("n", "<Plug>(git-conflict-next-conflict)", "<Cmd>AvanteConflictNextConflict<CR>", opts("Next Conflict"))
  map("n", "<Plug>(git-conflict-prev-conflict)", "<Cmd>AvanteConflictPrevConflict<CR>", opts("Previous Conflict"))
end

local function setup_buffer_mappings(bufnr)
  local function opts(desc)
    return { silent = true, buffer = bufnr, desc = "Git Conflict: " .. desc }
  end

  map({ "n", "v" }, config.default_mappings.ours, "<Plug>(git-conflict-ours)", opts("Choose Ours"))
  map({ "n", "v" }, config.default_mappings.both, "<Plug>(git-conflict-both)", opts("Choose Both"))
  map({ "n", "v" }, config.default_mappings.none, "<Plug>(git-conflict-none)", opts("Choose None"))
  map({ "n", "v" }, config.default_mappings.theirs, "<Plug>(git-conflict-theirs)", opts("Choose Theirs"))
  map({ "v", "v" }, config.default_mappings.ours, "<Plug>(git-conflict-ours)", opts("Choose Ours"))
  -- map('V', config.default_mappings.ours, '<Plug>(git-conflict-ours)', opts('Choose Ours'))
  map("n", config.default_mappings.prev, "<Plug>(git-conflict-prev-conflict)", opts("Previous Conflict"))
  map("n", config.default_mappings.next, "<Plug>(git-conflict-next-conflict)", opts("Next Conflict"))
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
  for _, mapping in pairs(config.default_mappings) do
    if is_mapped(mapping) then
      api.nvim_buf_del_keymap(bufnr, "n", mapping)
    end
  end
  vim.b[bufnr].conflict_mappings_set = false
end

-----------------------------------------------------------------------------//
-- Highlights
-----------------------------------------------------------------------------//

---Derive the colour of the section label highlights based on each sections highlights
---@param highlights ConflictHighlights
local function set_highlights(highlights)
  local current_color = utils.get_hl(highlights.current)
  local incoming_color = utils.get_hl(highlights.incoming)
  local ancestor_color = utils.get_hl(highlights.ancestor)
  local current_bg = current_color.background or DEFAULT_CURRENT_BG_COLOR
  local incoming_bg = incoming_color.background or DEFAULT_INCOMING_BG_COLOR
  local ancestor_bg = ancestor_color.background or DEFAULT_ANCESTOR_BG_COLOR
  local current_label_bg = color.shade_color(current_bg, 60)
  local incoming_label_bg = color.shade_color(incoming_bg, 60)
  local ancestor_label_bg = color.shade_color(ancestor_bg, 60)
  api.nvim_set_hl(0, CURRENT_HL, { background = current_bg, bold = true, default = true })
  api.nvim_set_hl(0, INCOMING_HL, { background = incoming_bg, bold = true, default = true })
  api.nvim_set_hl(0, ANCESTOR_HL, { background = ancestor_bg, bold = true, default = true })
  api.nvim_set_hl(0, CURRENT_LABEL_HL, { background = current_label_bg, default = true })
  api.nvim_set_hl(0, INCOMING_LABEL_HL, { background = incoming_label_bg, default = true })
  api.nvim_set_hl(0, ANCESTOR_LABEL_HL, { background = ancestor_label_bg, default = true })
end

---@param user_config AvanteConflictUserConfig
function M.setup(user_config)
  local _user_config = user_config or {}

  if _user_config.default_mappings == true then
    _user_config.default_mappings = DEFAULT_MAPPINGS
  end

  config = vim.tbl_deep_extend("force", config, _user_config)

  set_highlights(config.highlights)

  if config.default_commands then
    set_commands()
  end

  set_plug_mappings()

  api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
  api.nvim_create_autocmd("ColorScheme", {
    group = AUGROUP_NAME,
    callback = function()
      set_highlights(config.highlights)
    end,
  })

  api.nvim_create_autocmd("User", {
    group = AUGROUP_NAME,
    pattern = "AvanteConflictDetected",
    callback = function()
      local bufnr = api.nvim_get_current_buf()
      if config.disable_diagnostics then
        vim.diagnostic.disable(bufnr)
      end
      if config.default_mappings then
        setup_buffer_mappings(bufnr)
      end
    end,
  })

  api.nvim_create_autocmd("User", {
    group = AUGROUP_NAME,
    pattern = "AvanteConflictResolved",
    callback = function()
      local bufnr = api.nvim_get_current_buf()
      if config.disable_diagnostics then
        vim.diagnostic.enable(bufnr)
      end
      if config.default_mappings then
        clear_buffer_mappings(bufnr)
      end
    end,
  })

  api.nvim_set_decoration_provider(NAMESPACE, {
    on_buf = function(_, bufnr, _)
      return utils.is_valid_buf(bufnr)
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
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
    -- have to defer so that the < and > marks are set
    vim.defer_fn(function()
      local start = vim.api.nvim_buf_get_mark(0, "<")[1]
      local finish = vim.api.nvim_buf_get_mark(0, ">")[1]
      local position = find_position(bufnr, function(line, pos)
        local left = pos.current.range_start >= start - 1
        local right = pos.incoming.range_end <= finish + 1
        return left and right
      end)
      while position ~= nil do
        local lines = {}
        if vim.tbl_contains({ SIDES.OURS, SIDES.THEIRS, SIDES.BASE }, side) then
          local data = position[name_map[side]]
          lines = utils.get_buf_lines(data.content_start, data.content_end + 1)
        elseif side == SIDES.BOTH then
          local first = utils.get_buf_lines(position.current.content_start, position.current.content_end + 1)
          local second = utils.get_buf_lines(position.incoming.content_start, position.incoming.content_end + 1)
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
    return
  end
  local position = get_current_position(bufnr)
  if not position then
    return
  end
  local lines = {}
  if vim.tbl_contains({ SIDES.OURS, SIDES.THEIRS, SIDES.BASE }, side) then
    local data = position[name_map[side]]
    lines = utils.get_buf_lines(data.content_start, data.content_end + 1)
  elseif side == SIDES.BOTH then
    local first = utils.get_buf_lines(position.current.content_start, position.current.content_end + 1)
    local second = utils.get_buf_lines(position.incoming.content_start, position.incoming.content_end + 1)
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
