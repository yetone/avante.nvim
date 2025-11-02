local P = {}

---@class avante.ACPDiffHandler
local M = {}

local Utils = require("avante.utils")
local Config = require("avante.config")

---ACP handler to check if tool call contains diff content and display them in the buffer
---@param tool_call avante.acp.ToolCallUpdate
---@return boolean has_diff
function M.has_diff_content(tool_call)
  for _, content_item in ipairs(tool_call.content or {}) do
    if content_item.type == "diff" then return true end
  end

  local raw = tool_call.rawInput
  if not raw then return false end

  local has_new = (raw.new_string ~= nil and raw.new_string ~= vim.NIL)
  return has_new
end

--- Extract diff blocks from ACP tool call content
---
--- IMPORTANT ASSUMPTION: rawInput and content always reference the same file(s).
--- If rawInput exists with a file path, the content array will reference the same file(s).
--- This means we can safely skip processing the content array when rawInput.replace_all=true,
--- as they represent the same operation on the same file(s).
---
--- @param tool_call avante.acp.ToolCallUpdate
--- @return table<string, avante.DiffBlock[]> diff_blocks_by_file Maps file path to list of diff blocks
function M.extract_diff_blocks(tool_call)
  --- @type table<string, avante.DiffBlock[]>
  local diff_blocks_by_file = {}

  -- PRIORITY: If rawInput exists with replace_all=true, process it even if content exists,
  -- because the content array cannot express replace_all semantics.
  local raw = tool_call.rawInput
  local should_use_raw_input = raw and raw.replace_all == true
  -- Note: rawInput and content array reference the same file(s), so skipping content array is safe.

  -- `content` doesn't support replace_all semantics, it could generate false-positives when replacing the same string multiple times.
  if not should_use_raw_input then
    -- Handle content array (standard)
    for _, content_item in ipairs(tool_call.content or {}) do
      if content_item.type == "diff" then
        local path = content_item.path
        local oldText = content_item.oldText
        local newText = content_item.newText

        if oldText == "" or oldText == vim.NIL or oldText == nil then
          -- New file case
          local new_lines = P._normalize_text_to_lines(newText)
          local diff_block = P._create_new_file_diff_block(new_lines)
          P._add_diff_block(diff_blocks_by_file, path, diff_block)
        else
          -- Existing file case
          local old_lines = P._normalize_text_to_lines(oldText)
          local new_lines = P._normalize_text_to_lines(newText)

          local abs_path = Utils.to_absolute_path(path)
          local file_lines = Utils.read_file_from_buf_or_disk(abs_path) or {}
          local start_line, end_line = Utils.fuzzy_match(file_lines, old_lines)

          if not start_line or not end_line then
            -- Fallback: if oldText is a single word/line and exact match failed,
            -- try substring matching within lines (but NOT replace_all - that requires rawInput)
            -- This handles cases where the text is part of a longer line
            -- NOTE: content array represents a SINGLE replacement, not replace_all
            if #old_lines == 1 and #new_lines == 1 then
              local search_text = old_lines[1]
              local replace_text = new_lines[1]
              local found_blocks = P._find_substring_replacements(file_lines, search_text, replace_text, false)

              if #found_blocks > 0 then
                for _, block in ipairs(found_blocks) do
                  P._add_diff_block(diff_blocks_by_file, path, block)
                end
              else
                Utils.debug(
                  "[ACP diff content] Failed to find location for diff in file (tried substring matching): ",
                  {
                    path = path,
                    oldText = oldText,
                    newText = newText,
                    i = _,
                    content_item = content_item,
                    tool_call = tool_call,
                  }
                )
              end
            else
              Utils.debug("[ACP diff content] Failed to find location for diff in file: ", {
                path = path,
                oldText = oldText,
                newText = newText,
                i = _,
                content_item = content_item,
                tool_call = tool_call,
              })
            end
          else
            local diff_block = {
              start_line = start_line,
              end_line = end_line,
              old_lines = old_lines,
              new_lines = new_lines,
            }
            P._add_diff_block(diff_blocks_by_file, path, diff_block)
          end
        end
      end
    end
  end

  local has_diff_blocks = not P._is_table_empty(diff_blocks_by_file)

  -- Use rawInput if no diff blocks found from content array OR replace_all is true
  if raw and (should_use_raw_input or not has_diff_blocks) then
    Utils.debug("[ACP diff] Processing rawInput", {
      tool_call = tool_call,
      reason = raw.replace_all and "replace_all semantics" or "fallback",
    })

    local file_path = raw.file_path
    local old_string = raw.old_string == vim.NIL and nil or raw.old_string
    local new_string = raw.new_string == vim.NIL and nil or raw.new_string

    if file_path and new_string then
      local old_lines = P._normalize_text_to_lines(old_string)
      local new_lines = P._normalize_text_to_lines(new_string)

      local abs_path = Utils.to_absolute_path(file_path)
      local file_lines = Utils.read_file_from_buf_or_disk(abs_path) or {}

      if #old_lines == 0 or (#old_lines == 1 and old_lines[1] == "") then
        -- New file case
        local diff_block = P._create_new_file_diff_block(new_lines)
        diff_blocks_by_file[file_path] = { diff_block }
      else
        local replace_all = raw.replace_all

        if replace_all then
          if #old_lines == 1 and #new_lines == 1 then
            local search_text = old_lines[1]
            local replace_text = new_lines[1]
            local found_blocks = P._find_substring_replacements(file_lines, search_text, replace_text, true)

            if #found_blocks > 0 then
              diff_blocks_by_file[file_path] = found_blocks
            else
              Utils.debug("[ACP diff rawInput] [replace_all] Failed to find substring", {
                file_path = file_path,
                old_string = old_string,
                new_string = new_string,
                raw = raw,
              })
            end
          else
            -- Multi-line replace_all: use line matching
            local matches = Utils.find_all_matches(file_lines, old_lines)

            if #matches == 0 then
              Utils.debug("[ACP diff rawInput] [replace_all] Failed to find any matches for replace_all in file: ", {
                file_path = file_path,
                old_string = old_string,
                new_string = new_string,
                raw = raw,
              })
            else
              diff_blocks_by_file[file_path] = {}

              for _, match in ipairs(matches) do
                P._add_diff_block(diff_blocks_by_file, file_path, {
                  start_line = match.start_line,
                  end_line = match.end_line,
                  old_lines = old_lines,
                  new_lines = new_lines,
                })
              end
            end
          end
        else
          local start_line, end_line = Utils.fuzzy_match(file_lines, old_lines)

          if not start_line or not end_line then
            -- Fallback: try substring replacement for single-line case
            if #old_lines == 1 and #new_lines == 1 then
              local search_text = old_lines[1]
              local replace_text = new_lines[1]
              local found_blocks = P._find_substring_replacements(file_lines, search_text, replace_text, false)

              if #found_blocks > 0 then
                diff_blocks_by_file[file_path] = found_blocks
              else
                Utils.debug("[ACP diff rawInput] Failed to find location for diff in file: ", {
                  file_path = file_path,
                  old_string = old_string,
                  new_string = new_string,
                  raw = raw,
                })
              end
            else
              Utils.debug("[ACP diff rawInput] Failed to find location for diff in file: ", {
                file_path = file_path,
                old_string = old_string,
                new_string = new_string,
                raw = raw,
              })
            end
          else
            local diff_block = {
              start_line = start_line,
              end_line = end_line,
              old_lines = old_lines,
              new_lines = new_lines,
            }
            diff_blocks_by_file[file_path] = { diff_block }
          end
        end
      end
    end
  end

  for path, diff_blocks in pairs(diff_blocks_by_file) do
    -- Sort by start_line to handle multiple diffs correctly
    table.sort(diff_blocks, function(a, b) return a.start_line < b.start_line end)

    -- Apply minimize_diff if enabled (before calculating new_start_line/new_end_line)
    if Config.behaviour.minimize_diff then
      diff_blocks = P.minimize_diff_blocks(diff_blocks)
      diff_blocks_by_file[path] = diff_blocks
    end

    -- Calculate new_start_line and new_end_line with cumulative offset
    local base_line = 0
    for _, diff_block in ipairs(diff_blocks) do
      diff_block.new_start_line = diff_block.start_line + base_line
      if #diff_block.new_lines > 0 then
        diff_block.new_end_line = diff_block.new_start_line + #diff_block.new_lines - 1
      else
        -- For deletions, new_end_line is one before new_start_line
        diff_block.new_end_line = diff_block.new_start_line - 1
      end
      base_line = base_line + #diff_block.new_lines - #diff_block.old_lines
    end
  end

  if P._is_table_empty(diff_blocks_by_file) then
    Utils.debug("[ACP diff] No diff blocks extracted from tool call", {
      tool_call = tool_call,
    })
  end

  return diff_blocks_by_file
end

---Minimize diff blocks by removing unchanged lines (similar to replace_in_file.lua)
---@param diff_blocks avante.DiffBlock[]
---@return avante.DiffBlock[]
function P.minimize_diff_blocks(diff_blocks)
  local minimized = {}
  for _, diff_block in ipairs(diff_blocks) do
    local old_string = table.concat(diff_block.old_lines, "\n")
    local new_string = table.concat(diff_block.new_lines, "\n")

    ---@type integer[][]
    ---@diagnostic disable-next-line: assign-type-mismatch
    local patch = vim.diff(old_string, new_string, {
      algorithm = "histogram",
      result_type = "indices",
      ctxlen = 0,
    })

    if #patch > 0 then
      for _, hunk in ipairs(patch) do
        local start_a, count_a, start_b, count_b = unpack(hunk)
        local minimized_block = {}
        if count_a > 0 then
          local end_a = math.min(start_a + count_a - 1, #diff_block.old_lines)
          minimized_block.old_lines = vim.list_slice(diff_block.old_lines, start_a, end_a)
        else
          minimized_block.old_lines = {}
        end
        if count_b > 0 then
          local end_b = math.min(start_b + count_b - 1, #diff_block.new_lines)
          minimized_block.new_lines = vim.list_slice(diff_block.new_lines, start_b, end_b)
        else
          minimized_block.new_lines = {}
        end
        if count_a > 0 then
          minimized_block.start_line = diff_block.start_line + start_a - 1
          minimized_block.end_line = minimized_block.start_line + count_a - 1
        else
          -- For insertions, start_line is the position before which to insert
          minimized_block.start_line = diff_block.start_line + start_a
          minimized_block.end_line = minimized_block.start_line - 1
        end
        table.insert(minimized, minimized_block)
      end
    end
  end

  table.sort(minimized, function(a, b) return a.start_line < b.start_line end)

  return minimized
end

---Create a diff block for a new file
---@param new_lines string[]
---@return avante.DiffBlock
function P._create_new_file_diff_block(new_lines)
  return {
    start_line = 1,
    end_line = 0,
    old_lines = {},
    new_lines = new_lines,
  }
end

---Normalize text to lines array, handling nil and vim.NIL
---@param text string|nil
---@return string[]
function P._normalize_text_to_lines(text)
  if not text or text == vim.NIL or text == "" then return {} end
  return type(text) == "string" and vim.split(text, "\n") or {}
end

---Add a diff block to the collection, ensuring the path array exists
---@param diff_blocks_by_file table<string, avante.DiffBlock[]>
---@param path string
---@param diff_block avante.DiffBlock
function P._add_diff_block(diff_blocks_by_file, path, diff_block)
  diff_blocks_by_file[path] = diff_blocks_by_file[path] or {}
  table.insert(diff_blocks_by_file[path], diff_block)
end

---Find and replace substring occurrences in file lines
---@param file_lines string[] File content lines
---@param search_text string Text to search for
---@param replace_text string Text to replace with
---@param replace_all boolean If true, replace all occurrences; if false, only first match
---@return avante.DiffBlock[] Array of diff blocks created
function P._find_substring_replacements(file_lines, search_text, replace_text, replace_all)
  local diff_blocks = {}
  local escaped_search = search_text:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")

  for line_idx, line_content in ipairs(file_lines) do
    if line_content:find(search_text, 1, true) then
      local modified_line
      if replace_all then
        -- Replace all occurrences in this line
        -- Use function replacement to avoid pattern interpretation of replace_text
        -- This ensures literal replacement (e.g., "result%1" stays as "result%1", not backreference)
        modified_line = line_content:gsub(escaped_search, function() return replace_text end)
      else
        -- Replace first occurrence only
        -- Use function replacement to ensure literal text (no pattern interpretation)
        modified_line = line_content:gsub(escaped_search, function() return replace_text end, 1)
      end

      table.insert(diff_blocks, {
        start_line = line_idx,
        end_line = line_idx,
        old_lines = { line_content },
        new_lines = { modified_line },
      })

      -- For single replacement mode, stop after first match
      if not replace_all then break end
    end
  end

  return diff_blocks
end

---Check if a table is empty (has no keys)
---@param tbl table
---@return boolean
function P._is_table_empty(tbl) return next(tbl) == nil end

return M
