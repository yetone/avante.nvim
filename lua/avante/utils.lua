local Range = require("avante.range")
local SelectionResult = require("avante.selection_result")
local M = {}
function M.trim_suffix(str, suffix)
  return string.gsub(str, suffix .. "$", "")
end
function M.trim_line_number_prefix(line)
  return line:gsub("^L%d+: ", "")
end
function M.in_visual_mode()
  local current_mode = vim.fn.mode()
  return current_mode == "v" or current_mode == "V" or current_mode == ""
end
-- Get the selected content and range in Visual mode
-- @return avante.SelectionResult | nil Selected content and range
function M.get_visual_selection_and_range()
  if not M.in_visual_mode() then
    return nil
  end
  -- Get the start and end positions of Visual mode
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  -- Get the start and end line and column numbers
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]
  -- If the start point is after the end point, swap them
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end
  local content = ""
  local range = Range.new({ line = start_line, col = start_col }, { line = end_line, col = end_col })
  -- Check if it's a single-line selection
  if start_line == end_line then
    -- Get partial content of a single line
    local line = vim.fn.getline(start_line)
    -- content = string.sub(line, start_col, end_col)
    content = line
  else
    -- Multi-line selection: Get all lines in the selection
    local lines = vim.fn.getline(start_line, end_line)
    -- Extract partial content of the first line
    -- lines[1] = string.sub(lines[1], start_col)
    -- Extract partial content of the last line
    -- lines[#lines] = string.sub(lines[#lines], 1, end_col)
    -- Concatenate all lines in the selection into a string
    content = table.concat(lines, "\n")
  end
  if not content then
    return nil
  end
  -- Return the selected content and range
  return SelectionResult.new(content, range)
end
return M
