local Path = require("plenary.path")
local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")
local Diff = require("avante.diff")
local Config = require("avante.config")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "str_replace"

M.description =
  "The str_replace tool allows you to replace a specific string in a file with a new string. This is used for making precise edits."

function M.enabled() return false end

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
      name = "old_str",
      description = "The text to replace (must match exactly, including whitespace and indentation)",
      type = "string",
    },
    {
      name = "new_str",
      description = "The new text to insert in place of the old text",
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

---@type AvanteLLMToolFunc<{ path: string, old_str: string, new_str: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  if on_log then on_log("path: " .. opts.path) end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  local sidebar = require("avante").get()
  if not sidebar then return false, "Avante sidebar not found" end
  if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
  if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
  local file = io.open(abs_path, "r")
  if not file then return false, "file not found: " .. abs_path end
  if opts.old_str == nil then return false, "old_str not provided" end
  if opts.new_str == nil then return false, "new_str not provided" end
  -- Utils.debug("old_str", opts.old_str)
  -- Utils.debug("new_str", opts.new_str)
  local bufnr, err = Helpers.get_bufnr(abs_path)
  if err then return false, err end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lines_content = table.concat(lines, "\n")
  local old_lines = vim.split(opts.old_str, "\n")
  local new_lines = vim.split(opts.new_str, "\n")
  local start_line, end_line
  for i = 1, #lines - #old_lines + 1 do
    local match = true
    for j = 1, #old_lines do
      if Utils.remove_indentation(lines[i + j - 1]) ~= Utils.remove_indentation(old_lines[j]) then
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
    on_complete(false, "Failed to find the old string:\n" .. opts.old_str)
    return
  end
  local old_str = opts.old_str
  local new_str = opts.new_str
  local original_indentation = Utils.get_indentation(lines[start_line])
  if original_indentation ~= Utils.get_indentation(old_lines[1]) then
    old_lines = vim.tbl_map(function(line) return original_indentation .. line end, old_lines)
    new_lines = vim.tbl_map(function(line) return original_indentation .. line end, new_lines)
    old_str = table.concat(old_lines, "\n")
    new_str = table.concat(new_lines, "\n")
  end
  ---@diagnostic disable-next-line: assign-type-mismatch, missing-fields
  local patch = vim.diff(old_str, new_str, { ---@type integer[][]
    algorithm = "histogram",
    result_type = "indices",
    ctxlen = vim.o.scrolloff,
  })
  local patch_start_line_content = "<<<<<<< HEAD"
  local patch_end_line_content = ">>>>>>> new "
  --- add random characters to the end of the line to avoid conflicts
  patch_end_line_content = patch_end_line_content .. Utils.random_string(10)
  local current_start_a = 1
  local patched_new_lines = {}
  for _, hunk in ipairs(patch) do
    local start_a, count_a, start_b, count_b = unpack(hunk)
    if current_start_a <= start_a then
      if count_a > 0 then
        vim.list_extend(patched_new_lines, vim.list_slice(old_lines, current_start_a, start_a - 1))
      else
        vim.list_extend(patched_new_lines, vim.list_slice(old_lines, current_start_a, start_a))
      end
    end
    table.insert(patched_new_lines, patch_start_line_content)
    if count_a > 0 then
      vim.list_extend(patched_new_lines, vim.list_slice(old_lines, start_a, start_a + count_a - 1))
    end
    table.insert(patched_new_lines, "=======")
    vim.list_extend(patched_new_lines, vim.list_slice(new_lines, start_b, start_b + count_b - 1))
    table.insert(patched_new_lines, patch_end_line_content)
    current_start_a = start_a + math.max(count_a, 1)
  end
  if current_start_a <= #old_lines then
    vim.list_extend(patched_new_lines, vim.list_slice(old_lines, current_start_a, #old_lines))
  end
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, patched_new_lines)
  Diff.add_visited_buffer(bufnr)
  Diff.process(bufnr)
  if #patch > 0 then
    vim.api.nvim_win_set_cursor(sidebar.code.winid, { math.max(patch[1][1] + start_line - 1, 1), 0 })
  end
  vim.api.nvim_win_call(sidebar.code.winid, function() vim.cmd("normal! zz") end)
  local augroup = vim.api.nvim_create_augroup("avante_str_replace_editor", { clear = true })
  if Config.behaviour.auto_focus_on_diff_view then vim.api.nvim_set_current_win(sidebar.code.winid) end
  local confirm
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local current_lines_content = table.concat(current_lines, "\n")
      if current_lines_content:find(patch_end_line_content) then return end
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
      if confirm then confirm:close() end
      if lines_content == current_lines_content then
        on_complete(false, "User canceled")
        return
      end
      if session_ctx then Helpers.mark_as_not_viewed(opts.path, session_ctx) end
      on_complete(true, nil)
    end,
  })
  confirm = Helpers.confirm("Are you sure you want to apply this modification?", function(ok, reason)
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    vim.api.nvim_win_call(sidebar.code.winid, function()
      vim.cmd("noautocmd stopinsert")
      vim.cmd("noautocmd undo")
    end)
    if not ok then
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, new_lines)
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("noautocmd write") end)
    if session_ctx then Helpers.mark_as_not_viewed(opts.path, session_ctx) end
    on_complete(true, nil)
  end, { focus = not Config.behaviour.auto_focus_on_diff_view }, session_ctx)
end

return M
