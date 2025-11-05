local api = vim.api

local Utils = require("avante.utils")
local Config = require("avante.config")
local DiffDisplay = require("avante.utils.diff_display")
local ACPDiffHandler = require("avante.acp.acp_diff_handler")
local LLMToolHelpers = require("avante.llm_tools.helpers")

---@class avante.ACPDiffPreviewState
---@field bufnr integer
---@field path string
---@field lines string[] Original buffer lines
---@field changedtick integer Original changedtick
---@field modified boolean Original modified flag
---@field modifiable boolean Original modifiable flag
---@field diff_display avante.DiffDisplayInstance

---@class avante.ACPDiffPreviewOpts
---@field tool_call avante.acp.ToolCallUpdate The ACP tool call containing diff content
---@field session_ctx? table Session context (for auto-approval checks)

---@class avante.ui.acp_diff_preview
local M = {}

---Show diff preview for ACP tool call
---Returns a cleanup function that is safe to call in all cases (accept/reject/disabled)
---@param opts avante.ACPDiffPreviewOpts
---@return fun() cleanup Cleanup function - safe to call multiple times
function M.show_acp_diff(opts)
  local should_skip = not Config.behaviour.acp_show_diff_in_buffer
    or LLMToolHelpers.is_auto_approved(opts.session_ctx, opts.tool_call.kind)
    or not ACPDiffHandler.has_diff_content(opts.tool_call)

  if should_skip then
    return function() end
  end

  local diffs = ACPDiffHandler.extract_diff_blocks(opts.tool_call)

  ---@type avante.ACPDiffPreviewState[]
  local preview_states = {}

  for path, diff_blocks in pairs(diffs) do
    local abs_path = Utils.to_absolute_path(path)
    local bufnr = vim.fn.bufnr(abs_path)
    if bufnr == -1 then bufnr = vim.fn.bufnr(abs_path, true) end

    local diff_display = DiffDisplay.new({
      bufnr = bufnr,
      diff_blocks = diff_blocks,
    })

    local ok_changedtick, changedtick = pcall(function() return vim.b[bufnr].changedtick end)

    local state = {
      bufnr = bufnr,
      path = path,
      lines = api.nvim_buf_get_lines(bufnr, 0, -1, false),
      changedtick = ok_changedtick and changedtick or 0,
      modified = vim.bo[bufnr].modified,
      modifiable = vim.bo[bufnr].modifiable,
      diff_display = diff_display,
    }

    diff_display:highlight()
    diff_display:scroll_to_first_diff()
    diff_display:register_cursor_move_events()
    diff_display:register_navigation_keybindings()

    vim.bo[bufnr].modifiable = false

    table.insert(preview_states, state)
  end

  -- Cleanup function to clear diff display and restore buffer flags
  return function()
    if not preview_states or #preview_states == 0 then return end

    for _, state in ipairs(preview_states) do
      if state.diff_display then state.diff_display:clear() end

      -- Restore buffer flags if buffer is still valid
      if api.nvim_buf_is_valid(state.bufnr) then vim.bo[state.bufnr].modifiable = state.modifiable end
    end

    -- Clear references to help garbage collection
    preview_states = {}
  end
end

return M
