local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")
local Utils = require("avante.utils")
local Highlights = require("avante.highlights")
local Config = require("avante.config")

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
  local diff_blocks = {}

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
        diff_blocks,
        { search = table.concat(current_search, "\n"), replace = table.concat(current_replace, "\n") }
      )
    elseif is_searching then
      table.insert(current_search, line)
    elseif is_replacing then
      table.insert(current_replace, line)
    end
  end

  if #diff_blocks == 0 then return false, "No diff blocks found" end

  local bufnr, err = Helpers.get_bufnr(abs_path)
  if err then return false, err end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sidebar = require("avante").get()
  if not sidebar then return false, "Avante sidebar not found" end

  for _, diff_block in ipairs(diff_blocks) do
    local old_lines = vim.split(diff_block.search, "\n")
    local new_lines = vim.split(diff_block.replace, "\n")
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
      on_complete(false, "Failed to find the old string:\n" .. diff_block.search)
      return
    end
    local old_str = diff_block.search
    local new_str = diff_block.replace
    local original_indentation = Utils.get_indentation(lines[start_line])
    if original_indentation ~= Utils.get_indentation(old_lines[1]) then
      old_lines = vim.tbl_map(function(line) return original_indentation .. line end, old_lines)
      new_lines = vim.tbl_map(function(line) return original_indentation .. line end, new_lines)
      old_str = table.concat(old_lines, "\n")
      new_str = table.concat(new_lines, "\n")
    end
    diff_block.search = old_str
    diff_block.replace = new_str
    diff_block.start_line = start_line
    diff_block.end_line = end_line
  end

  table.sort(diff_blocks, function(a, b) return a.start_line < b.start_line end)

  local base_line = 0
  local max_col = vim.o.columns
  local ns_id = vim.api.nvim_create_namespace("avante_diff")

  for _, diff_block in ipairs(diff_blocks) do
    local start_line = diff_block.start_line + base_line
    local end_line = diff_block.end_line + base_line
    local old_lines = vim.split(diff_block.search, "\n")
    local new_lines = vim.split(diff_block.replace, "\n")
    base_line = base_line + #new_lines - #old_lines
    vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, new_lines)
    local deleted_virt_lines = vim
      .iter(old_lines)
      :map(function(line)
        --- append spaces to the end of the line
        local line_ = line .. string.rep(" ", max_col - #line)
        return { { line_, Highlights.TO_BE_DELETED_WITHOUT_STRIKETHROUGH } }
      end)
      :totable()
    local extmark_line = math.max(0, start_line - 2)
    -- Utils.debug("extmark_line", extmark_line)
    -- Utils.debug("start_line", start_line)
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, extmark_line, 0, {
      virt_lines = deleted_virt_lines,
      hl_eol = true,
      hl_mode = "combine",
    })
    local end_row = start_line + #new_lines - 1
    -- Utils.debug("end_row", end_row)
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line - 1, 0, {
      hl_group = Highlights.INCOMING,
      hl_eol = true,
      hl_mode = "combine",
      end_row = end_row,
    })
  end

  Helpers.confirm("Are you sure you want to apply this modification?", function(ok, reason)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    if not ok then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("noautocmd write") end)
    if session_ctx then Helpers.mark_as_not_viewed(opts.path, session_ctx) end
    on_complete(true, nil)
  end, { focus = not Config.behaviour.auto_focus_on_diff_view }, session_ctx)
end

return M
