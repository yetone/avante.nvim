---@class FloatingWindow
---@field enter boolean | nil
---@field winid integer | nil
---@field bufnr integer | nil
---@field buf_options table | nil
---@field win_options table | nil
---@field float_options table | nil
local FloatingWindow = {}
FloatingWindow.__index = FloatingWindow

setmetatable(FloatingWindow, {
  __call = function(cls, ...)
    return cls.new(...)
  end,
})

---@class opts
---@field enter? boolean
---@field buf_options? table<string, any>
---@field win_options? table<string, any>
---@field float_options? table<string, any>

---@param opts opts
---@return FloatingWindow
function FloatingWindow.new(opts)
  local instance = setmetatable({}, FloatingWindow)
  instance.winid = nil
  instance.bufnr = nil
  instance.enter = opts.enter or true
  instance.buf_options = opts.buf_options or {}
  instance.win_options = opts.win_options or {}
  instance.float_options = opts.float_options or {}
  return instance
end

---@return nil
function FloatingWindow:mount()
  self.bufnr = vim.api.nvim_create_buf(false, true)

  for option, value in pairs(self.buf_options) do
    vim.api.nvim_set_option_value(option, value, { buf = self.bufnr })
  end

  self.winid = vim.api.nvim_open_win(self.bufnr, self.enter, self.float_options)

  for option, value in pairs(self.win_options) do
    vim.api.nvim_set_option_value(option, value, { win = self.winid })
  end
end

---@return nil
function FloatingWindow:unmount()
  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
    self.bufnr = nil
  end

  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_win_close(self.winid, true)
    self.winid = nil
  end
end

---@param event string | string[]
---@param handler string | function
---@param options? table<"'once'" | "'nested'", boolean>
---@return nil
function FloatingWindow:on(event, handler, options)
  vim.api.nvim_create_autocmd(event, {
    buffer = self.bufnr,
    callback = handler,
    once = options and options["once"] or false,
    nested = options and options["nested"] or false,
  })
end

---@param mode string check `:h :map-modes`
---@param key string|string[] key for the mapping
---@param handler string | fun(): nil handler for the mapping
---@param opts? table<"'expr'"|"'noremap'"|"'nowait'"|"'remap'"|"'script'"|"'silent'"|"'unique'", boolean>
---@return nil
function FloatingWindow:map(mode, key, handler, opts)
  local options = opts or {}
  if type(key) == "string" then
    vim.keymap.set(mode, key, handler, options)
    return
  end
  for _, key_ in ipairs(key) do
    vim.keymap.set(mode, key_, handler, options)
  end
end

return FloatingWindow
