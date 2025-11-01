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
    if content_item.type == "diff" and content_item.newText ~= vim.NIL then return true end
  end

  -- Check for diff in rawInput format (legacy format)
  local raw = tool_call.rawInput
  if raw then
    local has_new = (raw["new_string"] ~= nil) or (raw["newString"] ~= nil)
    local has_path = (raw["file_path"] ~= nil) or (raw["filePath"] ~= nil)
    if has_new and has_path then return true end
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
      local old_string = raw.old_string or raw.oldString

      if old_string == vim.NIL then old_string = nil end

      local new_string = raw.new_string or raw.newString
      if new_string == vim.NIL then new_string = nil end

      if file_path and new_string then
        local old_lines = {}
        if old_string and old_string ~= "" and type(old_string) == "string" then
          old_lines = vim.split(old_string, "\n")
        end

        local new_lines = (new_string and type(new_string) == "string") and vim.split(new_string, "\n") or {}

        local abs_path = Utils.to_absolute_path(file_path)
        local file_lines = Utils.read_file_from_buf_or_disk(abs_path) or {}

        if #old_lines == 0 or (#old_lines == 1 and old_lines[1] == "") then
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
            if #old_lines == 1 and #new_lines == 1 then
              local search_text = old_lines[1]
              local replace_text = new_lines[1]
              diff_blocks_by_file[file_path] = {}

              -- Find all lines containing the substring
              for line_idx, line_content in ipairs(file_lines) do
                if line_content:find(search_text, 1, true) then
                  -- Replace all occurrences in this line
                  local modified_line =
                    line_content:gsub(search_text:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"), replace_text)
                  local diff_block = {
                    start_line = line_idx,
                    end_line = line_idx,
                    old_lines = { line_content },
                    new_lines = { modified_line },
                  }
                  table.insert(diff_blocks_by_file[file_path], diff_block)
                end
              end

              if #diff_blocks_by_file[file_path] == 0 then
                Utils.warn("Failed to find substring '" .. search_text .. "' in file: " .. file_path)
              end
            else
              -- Multi-line replace_all: use line matching
              local matches = Utils.find_all_matches(file_lines, old_lines)

              if #matches == 0 then
                Utils.warn("Failed to find any matches for replace_all in file: " .. file_path)
              else
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
              end
            end
          else
            local start_line, end_line = Utils.fuzzy_match(file_lines, old_lines)

            if not start_line or not end_line then
              Utils.warn("Failed to find location for diff in file: " .. file_path)
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
  end

  -- Handle content array format (standard format)
  for _, content_item in ipairs(tool_call.content or {}) do
    if content_item.type == "diff" and content_item.newText ~= vim.NIL then
      local path = content_item.path
      local oldText = content_item.oldText or ""
      local newText = content_item.newText

      if not path then
        Utils.warn("Diff content missing path field")
      elseif oldText == "" or oldText == vim.NIL then
        -- New file case
        local new_lines = type(newText) == "string" and vim.split(newText, "\n") or {}
        local diff_block = {
          start_line = 1,
          end_line = 0,
          old_lines = {},
          new_lines = new_lines,
        }
        diff_blocks_by_file[path] = diff_blocks_by_file[path] or {}
        table.insert(diff_blocks_by_file[path], diff_block)
      else
        -- Existing file case
        local old_lines = vim.split(oldText, "\n")
        local new_lines = vim.split(newText, "\n")

        local abs_path = Utils.to_absolute_path(path)
        local file_lines = Utils.read_file_from_buf_or_disk(abs_path) or {}
        local start_line, end_line = Utils.fuzzy_match(file_lines, old_lines)

        if not start_line or not end_line then
          Utils.warn("Failed to find location for diff in file: " .. path)
        else
          local diff_block = {
            start_line = start_line,
            end_line = end_line,
            old_lines = old_lines,
            new_lines = new_lines,
          }
          diff_blocks_by_file[path] = diff_blocks_by_file[path] or {}
          table.insert(diff_blocks_by_file[path], diff_block)
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
      if #diff_block.new_lines > 0 then
        diff_block.new_end_line = diff_block.new_start_line + #diff_block.new_lines - 1
      else
        -- For deletions, new_end_line is one before new_start_line
        diff_block.new_end_line = diff_block.new_start_line - 1
      end
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

return M
