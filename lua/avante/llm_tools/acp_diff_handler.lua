---@class avante.llm_tools.acp_diff_handler
local M = {}

local Utils = require("avante.utils")
local Config = require("avante.config")

---Check if tool call contains diff content
---@param tool_call avante.acp.ToolCall|avante.acp.ToolCallUpdate
---@return boolean has_diff Whether the tool call contains diff content
function M.has_diff_content(tool_call)
  -- Check for diff in content array format
  for _, content_item in ipairs(tool_call.content or {}) do
    if content_item.type == "diff" and content_item.oldText ~= vim.NIL and content_item.newText ~= vim.NIL then
      return true
    end
  end

  -- Check for diff in rawInput format (legacy format)
  if tool_call.rawInput then
    local raw = tool_call.rawInput
    if raw then
      local has_old = (raw["old_string"] ~= nil) or (raw["oldString"] ~= nil)
      local has_new = (raw["new_string"] ~= nil) or (raw["newString"] ~= nil)
      local has_path = (raw["file_path"] ~= nil) or (raw["filePath"] ~= nil)
      if has_old and has_new and has_path then return true end
    end
  end

  return false
end

---Extract diff blocks from ACP tool call content
---@param tool_call avante.acp.ToolCall|avante.acp.ToolCallUpdate
---@return table<string, avante.DiffBlock[]> diff_blocks_by_file Maps file path to list of diff blocks
function M.extract_diff_blocks(tool_call)
  local diff_blocks_by_file = {}

  -- Handle rawInput format (legacy format)
  if tool_call.rawInput then
    local raw = tool_call.rawInput
    if raw then
      local file_path = raw.file_path or raw.filePath
      local old_string = raw.old_string or raw.oldString or ""
      local new_string = raw.new_string or raw.newString

      if file_path and new_string then
        local old_lines = (old_string and old_string ~= "" and type(old_string) == "string")
            and vim.split(old_string, "\n")
          or {}
        local new_lines = (new_string and type(new_string) == "string") and vim.split(new_string, "\n") or {}

        local abs_path = Utils.to_absolute_path(file_path)
        local file_lines = Utils.read_file_from_buf_or_disk(abs_path) or {}

        if #old_lines == 0 then
          -- New file case
          local diff_block = {
            start_line = 1,
            end_line = 0,
            old_lines = {},
            new_lines = new_lines,
          }
          diff_blocks_by_file[file_path] = { diff_block }
        else
          local replace_all = raw.replace_all or raw.replaceAll

          if replace_all then
            local matches = Utils.find_all_matches(file_lines, old_lines)

            if #matches > 0 then
              diff_blocks_by_file[file_path] = {}
              for _, match in ipairs(matches) do
                local diff_block = {
                  start_line = match.start_line,
                  end_line = match.end_line,
                  old_lines = old_lines,
                  new_lines = new_lines,
                }
                table.insert(diff_blocks_by_file[file_path], diff_block)
              end
            else
              Utils.warn("Failed to find any matches for replace_all in file: " .. file_path)
            end
          else
            local start_line, end_line = Utils.fuzzy_match(file_lines, old_lines)

            if start_line and end_line then
              local diff_block = {
                start_line = start_line,
                end_line = end_line,
                old_lines = old_lines,
                new_lines = new_lines,
              }
              diff_blocks_by_file[file_path] = { diff_block }
            else
              Utils.warn("Failed to find location for diff in file: " .. file_path)
            end
          end
        end
      end
    end
  end

  -- Handle content array format (standard format)
  for _, content_item in ipairs(tool_call.content or {}) do
    if content_item.type == "diff" and content_item.oldText ~= vim.NIL and content_item.newText ~= vim.NIL then
      local path = content_item.path
      local oldText = content_item.oldText or ""
      local newText = content_item.newText

      if oldText == "" or oldText == vim.NIL then
        local diff_block = {
          start_line = 1,
          end_line = 0,
          old_lines = {},
          new_lines = vim.split(newText, "\n"),
        }
        diff_blocks_by_file[path] = diff_blocks_by_file[path] or {}
        table.insert(diff_blocks_by_file[path], diff_block)
      else
        local old_lines = vim.split(oldText, "\n")
        local new_lines = vim.split(newText, "\n")

        local abs_path = Utils.to_absolute_path(path)
        local file_lines = Utils.read_file_from_buf_or_disk(abs_path) or {}
        local start_line, end_line = Utils.fuzzy_match(file_lines, old_lines)

        if start_line and end_line then
          local diff_block = {
            start_line = start_line,
            end_line = end_line,
            old_lines = old_lines,
            new_lines = new_lines,
          }
          diff_blocks_by_file[path] = diff_blocks_by_file[path] or {}
          table.insert(diff_blocks_by_file[path], diff_block)
        else
          Utils.warn("Failed to find location for diff in file: " .. path)
        end
      end
    end
  end

  for path, diff_blocks in pairs(diff_blocks_by_file) do
    -- Sort by start_line to handle multiple diffs correctly
    table.sort(diff_blocks, function(a, b) return a.start_line < b.start_line end)

    -- Apply minimize_diff if enabled (before calculating new_start_line/new_end_line)
    if Config.behaviour.minimize_diff then
      diff_blocks = M.minimize_diff_blocks(diff_blocks)
      diff_blocks_by_file[path] = diff_blocks
    end

    -- Calculate new_start_line and new_end_line with cumulative offset
    local base_line = 0
    for _, diff_block in ipairs(diff_blocks) do
      diff_block.new_start_line = diff_block.start_line + base_line
      diff_block.new_end_line = diff_block.new_start_line + #diff_block.new_lines - 1
      base_line = base_line + #diff_block.new_lines - #diff_block.old_lines
    end
  end

  return diff_blocks_by_file
end

---Minimize diff blocks by removing unchanged lines (similar to replace_in_file.lua)
---@param diff_blocks avante.DiffBlock[]
---@return avante.DiffBlock[]
function M.minimize_diff_blocks(diff_blocks)
  local minimized = {}
  for _, diff_block in ipairs(diff_blocks) do
    local old_string = table.concat(diff_block.old_lines, "\n")
    local new_string = table.concat(diff_block.new_lines, "\n")

    ---@diagnostic disable-next-line: assign-type-mismatch, missing-fields
    local patch = vim.diff(old_string, new_string, { ---@type integer[][]
      algorithm = "histogram",
      result_type = "indices",
      ctxlen = 0,
    })

    for _, hunk in ipairs(patch) do
      local start_a, count_a, start_b, count_b = unpack(hunk)
      local minimized_block = {}
      if count_a > 0 then
        minimized_block.old_lines = vim.list_slice(diff_block.old_lines, start_a, start_a + count_a - 1)
      else
        minimized_block.old_lines = {}
      end
      if count_b > 0 then
        minimized_block.new_lines = vim.list_slice(diff_block.new_lines, start_b, start_b + count_b - 1)
      else
        minimized_block.new_lines = {}
      end
      if count_a > 0 then
        minimized_block.start_line = diff_block.start_line + start_a - 1
      else
        minimized_block.start_line = diff_block.start_line + start_a
      end
      minimized_block.end_line = diff_block.start_line + start_a + math.max(count_a, 1) - 2
      table.insert(minimized, minimized_block)
    end
  end

  table.sort(minimized, function(a, b) return a.start_line < b.start_line end)

  return minimized
end

return M
