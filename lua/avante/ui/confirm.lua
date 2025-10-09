local Popup = require("nui.popup")
local NuiText = require("nui.text")
local Highlights = require("avante.highlights")
local Utils = require("avante.utils")
local Line = require("avante.ui.line")
local PromptInput = require("avante.ui.prompt_input")
local Config = require("avante.config")

---@class avante.ui.Confirm.ButtonAvailability
---@field has_allow_once boolean
---@field has_allow_always boolean
---@field has_reject boolean

---@class avante.ui.Confirm
---@field message string
---@field callback fun(type: "yes" | "all" | "no", reason?: string)
---@field _container_winid number
---@field _focus boolean | nil
---@field _group number | nil
---@field _popup NuiPopup | nil
---@field _prev_winid number | nil
---@field _ns_id number | nil
---@field _button_availability avante.ui.Confirm.ButtonAvailability | nil
---@field _skip_reject_prompt boolean | nil
---@field _button_count number | nil
---@field _button_map table<number, string> | nil
---@field _focus_index number | nil
local M = {}
M.__index = M

---@param message string
---@param callback fun(type: "yes" | "all" | "no", reason?: string)
---@param opts { container_winid: number, focus?: boolean, button_availability?: avante.ui.Confirm.ButtonAvailability, skip_reject_prompt?: boolean }
---@return avante.ui.Confirm
function M:new(message, callback, opts)
  local this = setmetatable({}, M)
  this.message = message
  this.callback = callback
  this._container_winid = opts.container_winid or vim.api.nvim_get_current_win()
  this._focus = opts.focus
  this._button_availability = opts.button_availability
  this._skip_reject_prompt = opts.skip_reject_prompt
  this._ns_id = vim.api.nvim_create_namespace("avante_confirm")
  return this
end

function M:open()
  if self._popup then return end
  self._prev_winid = vim.api.nvim_get_current_win()
  local message = self.message
  local callback = self.callback

  local win_width = 60

  local BUTTON_NORMAL = Highlights.BUTTON_DEFAULT
  local BUTTON_FOCUS = Highlights.BUTTON_DEFAULT_HOVER

  local commentfg = Highlights.AVANTE_COMMENT_FG

  -- Build button configuration based on availability
  local btn_avail = self._button_availability
  local buttons = {}
  local button_map = {} -- maps button index to type ("yes", "all", "no")

  if not btn_avail or btn_avail.has_allow_once then
    table.insert(buttons, {
      key = "yes",
      label = " [Y]es ",
      index = #buttons + 1,
    })
    button_map[#buttons] = "yes"
  end

  if not btn_avail or btn_avail.has_allow_always then
    table.insert(buttons, {
      key = "all",
      label = " [A]ll yes ",
      index = #buttons + 1,
    })
    button_map[#buttons] = "all"
  end

  if not btn_avail or btn_avail.has_reject then
    table.insert(buttons, {
      key = "no",
      label = " [N]o ",
      index = #buttons + 1,
    })
    button_map[#buttons] = "no"
  end

  local button_count = #buttons
  local focus_index = button_count -- default focus on last button (no/reject)

  -- Store as instance fields for testability
  self._button_count = button_count
  self._button_map = button_map
  self._focus_index = focus_index

  -- Build buttons line with spacing
  local buttons_line_sections = {}
  for i, btn in ipairs(buttons) do
    table.insert(buttons_line_sections, {
      btn.label,
      function() return focus_index == btn.index and BUTTON_FOCUS or BUTTON_NORMAL end,
    })
    if i < button_count then table.insert(buttons_line_sections, { "   " }) end
  end

  local keybindings_line = Line:new({
    { " " .. Config.mappings.confirm.focus_window .. " ", "visual" },
    { " - focus ", commentfg },
    { "  " },
    { " " .. Config.mappings.confirm.code .. " ", "visual" },
    { " - code ", commentfg },
    { "  " },
    { " " .. Config.mappings.confirm.resp .. " ", "visual" },
    { " - resp ", commentfg },
    { "  " },
    { " " .. Config.mappings.confirm.input .. " ", "visual" },
    { " - input ", commentfg },
    { "  " },
  })
  local buttons_line = Line:new(buttons_line_sections)
  local buttons_content = tostring(buttons_line)
  local buttons_start_col = math.floor((win_width - #buttons_content) / 2)

  -- Calculate button positions
  local button_positions = {}
  local section_index = 1
  for i = 1, button_count do
    button_positions[i] = buttons_line:get_section_pos(section_index, buttons_start_col)
    section_index = section_index + 2 -- skip spacer
  end
  local buttons_line_content = string.rep(" ", buttons_start_col) .. buttons_content
  local keybindings_line_num = 5 + #vim.split(message, "\n")
  local buttons_line_num = 2 + #vim.split(message, "\n")
  local content = vim
    .iter({
      "",
      vim.tbl_map(function(line) return "  " .. line end, vim.split(message, "\n")),
      "",
      buttons_line_content,
      "",
      "",
      tostring(keybindings_line),
    })
    :flatten()
    :totable()

  local win_height = #content

  for _, line in ipairs(vim.split(message, "\n")) do
    win_height = win_height + math.floor(#line / (win_width - 2))
  end

  local button_row = buttons_line_num + 1

  local container_winid = self._container_winid
  local container_width = vim.api.nvim_win_get_width(container_winid)

  local popup = Popup({
    relative = {
      type = "win",
      winid = container_winid,
    },
    position = {
      row = vim.o.lines - win_height,
      col = math.floor((container_width - win_width) / 2),
    },
    size = { width = win_width, height = win_height },
    enter = self._focus ~= false,
    focusable = true,
    border = {
      padding = { 0, 1 },
      text = { top = NuiText(" Confirmation ", Highlights.CONFIRM_TITLE) },
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
    },
    buf_options = {
      filetype = "AvanteConfirm",
      modifiable = false,
      readonly = true,
      buftype = "nofile",
    },
    win_options = {
      winfixbuf = true,
      cursorline = false,
      winblend = 5,
      winhighlight = "NormalFloat:Normal,FloatBorder:Comment",
    },
  })

  local function focus_button()
    if focus_index >= 1 and focus_index <= button_count then
      local pos = button_positions[focus_index]
      if pos then vim.api.nvim_win_set_cursor(popup.winid, { button_row, pos[1] }) end
    end
  end

  local function render_content()
    Utils.unlock_buf(popup.bufnr)
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, content)
    Utils.lock_buf(popup.bufnr)

    buttons_line:set_highlights(self._ns_id, popup.bufnr, buttons_line_num, buttons_start_col)
    keybindings_line:set_highlights(self._ns_id, popup.bufnr, keybindings_line_num)
    focus_button()
  end

  local function click_button()
    local button_type = button_map[focus_index]

    if button_type == "yes" then
      self:close()
      callback("yes")
      return
    end

    if button_type == "all" then
      self:close()
      Utils.notify("Accept all")
      callback("all")
      return
    end

    if button_type == "no" then
      if self._skip_reject_prompt then
        self:close()
        callback("no")
        return
      end

      local prompt_input = PromptInput:new({
        submit_callback = function(input)
          self:close()
          callback("no", input ~= "" and input or nil)
        end,
        close_on_submit = true,
        win_opts = {
          relative = "win",
          win = self._container_winid,
          border = Config.windows.ask.border,
          title = { { "Reject reason", "FloatTitle" } },
        },
        start_insert = Config.windows.ask.start_insert,
      })
      prompt_input:open()
    end
  end

  vim.keymap.set("n", Config.mappings.confirm.code, function()
    local sidebar = require("avante").get()
    if not sidebar then return end
    if sidebar.code.winid and vim.api.nvim_win_is_valid(sidebar.code.winid) then
      vim.api.nvim_set_current_win(sidebar.code.winid)
    end
  end, { buffer = popup.bufnr, nowait = true })

  vim.keymap.set("n", Config.mappings.confirm.resp, function()
    local sidebar = require("avante").get()
    if sidebar and sidebar.containers.result and vim.api.nvim_win_is_valid(sidebar.containers.result.winid) then
      vim.api.nvim_set_current_win(sidebar.containers.result.winid)
    end
  end, { buffer = popup.bufnr, nowait = true })

  vim.keymap.set("n", Config.mappings.confirm.input, function()
    local sidebar = require("avante").get()
    if sidebar and sidebar.containers.input and vim.api.nvim_win_is_valid(sidebar.containers.input.winid) then
      vim.api.nvim_set_current_win(sidebar.containers.input.winid)
    end
  end, { buffer = popup.bufnr, nowait = true })

  -- Helper to find button index by type
  local function find_button_index(button_type)
    for idx, btype in pairs(button_map) do
      if btype == button_type then return idx end
    end
    return nil
  end

  -- Keyboard shortcuts for direct button access
  local yes_index = find_button_index("yes")
  if yes_index then
    vim.keymap.set("n", "y", function()
      focus_index = yes_index
      render_content()
      click_button()
    end, { buffer = popup.bufnr, nowait = true })

    vim.keymap.set("n", "Y", function()
      focus_index = yes_index
      render_content()
      click_button()
    end, { buffer = popup.bufnr, nowait = true })
  end

  local all_index = find_button_index("all")
  if all_index then
    vim.keymap.set("n", "a", function()
      focus_index = all_index
      render_content()
      click_button()
    end, { buffer = popup.bufnr, nowait = true })

    vim.keymap.set("n", "A", function()
      focus_index = all_index
      render_content()
      click_button()
    end, { buffer = popup.bufnr, nowait = true })
  end

  local no_index = find_button_index("no")
  if no_index then
    vim.keymap.set("n", "n", function()
      focus_index = no_index
      render_content()
      click_button()
    end, { buffer = popup.bufnr, nowait = true })

    vim.keymap.set("n", "N", function()
      focus_index = no_index
      render_content()
      click_button()
    end, { buffer = popup.bufnr, nowait = true })
  end

  -- Navigation shortcuts
  vim.keymap.set("n", "<Left>", function()
    focus_index = focus_index - 1
    if focus_index < 1 then focus_index = button_count end
    focus_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<Right>", function()
    focus_index = focus_index + 1
    if focus_index > button_count then focus_index = 1 end
    focus_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "h", function()
    -- Jump to first button (yes)
    if yes_index then
      focus_index = yes_index
      focus_button()
    end
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "l", function()
    -- Jump to second button (all if available, otherwise no)
    if all_index then
      focus_index = all_index
      focus_button()
    end
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<Tab>", function()
    focus_index = focus_index + 1
    if focus_index > button_count then focus_index = 1 end
    focus_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<S-Tab>", function()
    focus_index = focus_index - 1
    if focus_index < 1 then focus_index = button_count end
    focus_button()
  end, { buffer = popup.bufnr })

  vim.keymap.set("n", "<CR>", function() click_button() end, { buffer = popup.bufnr })

  vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "<LeftMouse>", "", {
    callback = function()
      local pos = vim.fn.getmousepos()
      local row, col = pos["winrow"], pos["wincol"]
      if row == button_row then
        -- Check which button was clicked
        for i = 1, button_count do
          local btn_pos = button_positions[i]
          if btn_pos and col >= btn_pos[1] and col <= btn_pos[2] then
            focus_index = i
            break
          end
        end
        render_content()
        click_button()
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

      -- Check which button cursor is on
      for i = 1, button_count do
        local btn_pos = button_positions[i]
        if btn_pos and col >= btn_pos[1] and col <= btn_pos[2] then
          focus_index = i
          render_content()
          break
        end
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
  vim.keymap.set({ "n", "i" }, Config.mappings.confirm.focus_window, function() self:window_focus_handler() end)
end

function M:unbind_window_focus_keymaps() pcall(vim.keymap.del, { "n", "i" }, Config.mappings.confirm.focus_window) end

function M:cancel()
  self.callback("no", "cancel")
  return self:close()
end

function M:close()
  self:unbind_window_focus_keymaps()
  if self._group then
    pcall(vim.api.nvim_del_augroup_by_id, self._group)
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
