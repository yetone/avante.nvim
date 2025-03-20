local Popup = require("nui.popup")
local NuiText = require("nui.text")
local Highlights = require("avante.highlights")
local Utils = require("avante.utils")

---@class avante.ui.Confirm
---@field message string
---@field callback fun(yes: boolean)
---@field _container_winid number | nil
---@field _focus boolean | nil
---@field _group number | nil
---@field _popup NuiPopup | nil
---@field _prev_winid number | nil
local M = {}
M.__index = M

---@param message string
---@param callback fun(yes: boolean)
---@param opts { container_winid: number, focus?: boolean }
---@return avante.ui.Confirm
function M:new(message, callback, opts)
  local this = setmetatable({}, M)
  this.message = message
  this.callback = callback
  this._container_winid = opts.container_winid
  this._focus = opts.focus
  return this
end

function M:open()
  self._prev_winid = vim.api.nvim_get_current_win()
  local message = self.message
  local callback = self.callback

  local win_width = 60

  local focus_index = 2 -- 1 = Yes, 2 = No

  local BUTTON_NORMAL = Highlights.BUTTON_DEFAULT
  local BUTTON_FOCUS = Highlights.BUTTON_DEFAULT_HOVER

  local keybindings_content = "<C-w>f: focus; c: code; r: resp; i: input"
  local keybidings_start_col = math.floor((win_width - #keybindings_content) / 2)
  local buttons_content = " Yes       No "
  local buttons_start_col = math.floor((win_width - #buttons_content) / 2)
  local yes_button_pos = { buttons_start_col, buttons_start_col + 5 }
  local no_button_pos = { buttons_start_col + 10, buttons_start_col + 14 }
  local keybindings_line = string.rep(" ", keybidings_start_col) .. keybindings_content
  local buttons_line = string.rep(" ", buttons_start_col) .. buttons_content
  local keybindings_line_num = 1 + #vim.split(message, "\n")
  local buttons_line_num = 2 + #vim.split(message, "\n")
  local content = vim
    .iter({
      "",
      vim.tbl_map(function(line) return "  " .. line end, vim.split(message, "\n")),
      keybindings_line,
      buttons_line,
      "",
    })
    :flatten()
    :totable()
  local button_row = #content - 1

  local container_winid = self._container_winid or vim.api.nvim_get_current_win()
  local container_width = vim.api.nvim_win_get_width(container_winid)

  local popup = Popup({
    relative = {
      type = "win",
      winid = container_winid,
    },
    position = {
      row = vim.o.lines - #content - 3,
      col = (container_width - win_width) / 2,
    },
    size = { width = win_width, height = #content + 3 },
    enter = self._focus ~= false,
    focusable = true,
    border = {
      style = "rounded",
      text = { top = NuiText(" Confirmation ", Highlights.CONFIRM_TITLE) },
    },
    buf_options = {
      filetype = "avante-confirm",
      modifiable = false,
      readonly = true,
    },
    win_options = {
      winblend = 10,
    },
  })

  local function focus_button(row)
    row = row or button_row
    if focus_index == 1 then
      vim.api.nvim_win_set_cursor(popup.winid, { row, yes_button_pos[1] })
    else
      vim.api.nvim_win_set_cursor(popup.winid, { row, no_button_pos[1] })
    end
  end

  local function render_content()
    local yes_style = (focus_index == 1) and BUTTON_FOCUS or BUTTON_NORMAL
    local no_style = (focus_index == 2) and BUTTON_FOCUS or BUTTON_NORMAL

    Utils.unlock_buf(popup.bufnr)
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, content)
    Utils.lock_buf(popup.bufnr)

    vim.api.nvim_buf_add_highlight(
      popup.bufnr,
      0,
      "Comment",
      keybindings_line_num,
      keybidings_start_col,
      keybidings_start_col + #keybindings_content
    )
    vim.api.nvim_buf_add_highlight(popup.bufnr, 0, yes_style, buttons_line_num, yes_button_pos[1], yes_button_pos[2])
    vim.api.nvim_buf_add_highlight(popup.bufnr, 0, no_style, buttons_line_num, no_button_pos[1], no_button_pos[2])
    focus_button(buttons_line_num + 1)
  end

  local function select_button()
    self:close()
    callback(focus_index == 1)
  end

  vim.keymap.set("n", "c", function()
    local sidebar = require("avante").get()
    if not sidebar then return end
    if sidebar.code.winid and vim.api.nvim_win_is_valid(sidebar.code.winid) then
      vim.api.nvim_set_current_win(sidebar.code.winid)
    end
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "r", function()
    local sidebar = require("avante").get()
    if not sidebar then return end
    if sidebar.winids.result_container and vim.api.nvim_win_is_valid(sidebar.winids.result_container) then
      vim.api.nvim_set_current_win(sidebar.winids.result_container)
    end
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "i", function()
    local sidebar = require("avante").get()
    if not sidebar then return end
    if sidebar.winids.input_container and vim.api.nvim_win_is_valid(sidebar.winids.input_container) then
      vim.api.nvim_set_current_win(sidebar.winids.input_container)
    end
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "y", function()
    focus_index = 1
    render_content()
    select_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "n", function()
    focus_index = 2
    render_content()
    select_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<Left>", function()
    focus_index = 1
    focus_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<Right>", function()
    focus_index = 2
    focus_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<Tab>", function()
    focus_index = (focus_index == 1) and 2 or 1
    focus_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<S-Tab>", function()
    focus_index = (focus_index == 1) and 2 or 1
    focus_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<CR>", function() select_button() end, { buffer = popup.bufnr })

  vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "<LeftMouse>", "", {
    callback = function()
      local pos = vim.fn.getmousepos()
      local row, col = pos["winrow"], pos["wincol"]
      if row == button_row then
        if col >= yes_button_pos[1] and col <= yes_button_pos[2] then
          focus_index = 1
          render_content()
          select_button()
        elseif col >= no_button_pos[1] and col <= no_button_pos[2] then
          focus_index = 2
          render_content()
          select_button()
        end
      end
    end,
    noremap = true,
    silent = true,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = popup.bufnr,
    callback = function()
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      if row ~= button_row then vim.api.nvim_win_set_cursor(self._popup.winid, { button_row, buttons_start_col }) end
      if col >= yes_button_pos[1] and col <= yes_button_pos[2] then
        focus_index = 1
        render_content()
      elseif col >= no_button_pos[1] and col <= no_button_pos[2] then
        focus_index = 2
        render_content()
      end
    end,
  })

  self._group = self._group and self._group or vim.api.nvim_create_augroup("AvanteConfirm", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = self._group,
    callback = function()
      local winids = vim.api.nvim_list_wins()
      if not vim.list_contains(winids, self._container_winid) then self:close() end
    end,
  })

  popup:mount()
  render_content()
  self._popup = popup
  self:bind_window_focus_keymaps()
end

function M:window_focus_handler()
  local current_winid = vim.api.nvim_get_current_win()
  if
    current_winid == self._popup.winid
    and current_winid ~= self._prev_winid
    and vim.api.nvim_win_is_valid(self._prev_winid)
  then
    vim.api.nvim_set_current_win(self._prev_winid)
    return
  end
  self._prev_winid = current_winid
  vim.api.nvim_set_current_win(self._popup.winid)
end

function M:bind_window_focus_keymaps()
  vim.keymap.set({ "n", "i" }, "<C-w>f", function() self:window_focus_handler() end)
end

function M:unbind_window_focus_keymaps() vim.keymap.del({ "n", "i" }, "<C-w>f") end

function M:close()
  self:unbind_window_focus_keymaps()
  if self._group then
    vim.api.nvim_del_augroup_by_id(self._group)
    self._group = nil
  end
  if self._popup then
    self._popup:unmount()
    self._popup = nil
    return true
  end
  return false
end

return M
