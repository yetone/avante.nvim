local Popup = require("nui.popup")
local NuiText = require("nui.text")
local event = require("nui.utils.autocmd").event
local Highlights = require("avante.highlights")
local Utils = require("avante.utils")

local M = {}

---@param message string
---@param callback fun(yes: boolean)
---@param opts { container_winid: number }
---@return nil
function M.confirm(message, callback, opts)
  local focus_index = 2 -- 1 = Yes, 2 = No
  local yes_button_pos = { 23, 28 }
  local no_button_pos = { 33, 37 }

  local BUTTON_NORMAL = Highlights.BUTTON_DEFAULT
  local BUTTON_FOCUS = Highlights.BUTTON_DEFAULT_HOVER

  local button_line = string.rep(" ", 23) .. " Yes       No "
  local button_line_num = 2 + #vim.split(message, "\n")
  local content = vim
    .iter({
      "",
      vim.tbl_map(function(line) return "  " .. line end, vim.split(message, "\n")),
      "",
      button_line,
      "",
    })
    :flatten()
    :totable()
  local button_row = #content - 1

  local container_winid = opts.container_winid or vim.api.nvim_get_current_win()
  local container_width = vim.api.nvim_win_get_width(container_winid)

  local popup = Popup({
    relative = {
      type = "win",
      winid = container_winid,
    },
    position = {
      row = vim.o.lines - #content - 3,
      col = (container_width - 60) / 2,
    },
    size = { width = 60, height = #content + 3 },
    enter = true,
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

  local function render_buttons()
    local yes_style = (focus_index == 1) and BUTTON_FOCUS or BUTTON_NORMAL
    local no_style = (focus_index == 2) and BUTTON_FOCUS or BUTTON_NORMAL

    Utils.unlock_buf(popup.bufnr)
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, content)
    Utils.lock_buf(popup.bufnr)

    vim.api.nvim_buf_add_highlight(popup.bufnr, 0, yes_style, button_line_num, yes_button_pos[1], yes_button_pos[2])
    vim.api.nvim_buf_add_highlight(popup.bufnr, 0, no_style, button_line_num, no_button_pos[1], no_button_pos[2])
    focus_button(button_line_num + 1)
  end

  local function select_button()
    popup:unmount()
    callback(focus_index == 1)
  end

  vim.keymap.set("n", "y", function()
    focus_index = 1
    render_buttons()
    select_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "n", function()
    focus_index = 2
    render_buttons()
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
          render_buttons()
          select_button()
        elseif col >= no_button_pos[1] and col <= no_button_pos[2] then
          focus_index = 2
          render_buttons()
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
      if row == button_row then
        if col >= yes_button_pos[1] and col <= yes_button_pos[2] then
          focus_index = 1
          render_buttons()
        elseif col >= no_button_pos[1] and col <= no_button_pos[2] then
          focus_index = 2
          render_buttons()
        end
      end
    end,
  })

  -- popup:on(event.BufLeave, function() popup:unmount() end)

  popup:mount()
  render_buttons()
end

return M
