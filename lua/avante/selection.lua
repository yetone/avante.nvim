local Config = require("avante.config")

local api = vim.api
local fn = vim.fn

local NAMESPACE = api.nvim_create_namespace("avante_selection")
local PRIORITY = vim.highlight.priorities.user

---@class avante.Selection
local Selection = {}

Selection.did_setup = false

---@param id integer the tabpage id retrieved from api.nvim_get_current_tabpage()
function Selection:new(id)
  return setmetatable({
    hints_popup_extmark_id = nil,
    edit_popup_renderer = nil,
    augroup = api.nvim_create_augroup("avante_selection_" .. id, { clear = true }),
  }, { __index = self })
end

function Selection:get_virt_text_line()
  local current_pos = fn.getpos(".")

  -- Get the current and start position line numbers
  local current_line = current_pos[2] - 1 -- 0-indexed

  -- Ensure line numbers are not negative and don't exceed buffer range
  local total_lines = api.nvim_buf_line_count(0)
  if current_line < 0 then
    current_line = 0
  end
  if current_line >= total_lines then
    current_line = total_lines - 1
  end

  -- Take the first line of the selection to ensure virt_text is always in the top right corner
  return current_line
end

function Selection:show_hints_popup()
  self:close_hints_popup()

  local hint_text = string.format(" [Ask %s] ", Config.mappings.ask)

  local virt_text_line = self:get_virt_text_line()

  self.hints_popup_extmark_id = api.nvim_buf_set_extmark(0, NAMESPACE, virt_text_line, -1, {
    virt_text = { { hint_text, "Keyword" } },
    virt_text_pos = "eol",
    priority = PRIORITY,
  })
end

function Selection:close_hints_popup()
  if self.hints_popup_extmark_id then
    api.nvim_buf_del_extmark(0, NAMESPACE, self.hints_popup_extmark_id)
    self.hints_popup_extmark_id = nil
  end
end

function Selection:setup_autocmds()
  Selection.did_setup = true
  api.nvim_create_autocmd({ "ModeChanged" }, {
    group = self.augroup,
    pattern = { "n:v", "n:V", "n:" }, -- Entering Visual mode from Normal mode
    callback = function(ev)
      if vim.bo[ev.buf].filetype ~= "Avante" then
        self:show_hints_popup()
      end
    end,
  })

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = self.augroup,
    callback = function(ev)
      if vim.bo[ev.buf].filetype ~= "Avante" then
        if vim.fn.mode() == "v" or vim.fn.mode() == "V" or vim.fn.mode() == "" then
          self:show_hints_popup()
        else
          self:close_hints_popup()
        end
      end
    end,
  })

  api.nvim_create_autocmd({ "ModeChanged" }, {
    group = self.augroup,
    pattern = { "v:n", "v:i", "v:c" }, -- Switching from visual mode back to normal, insert, or other modes
    callback = function(ev)
      if vim.bo[ev.buf].filetype ~= "Avante" then
        self:close_hints_popup()
      end
    end,
  })
  return self
end

function Selection:delete_autocmds()
  if self.augroup then
    api.nvim_del_augroup_by_id(self.augroup)
  end
  self.augroup = nil
  Selection.did_setup = false
end

return Selection
