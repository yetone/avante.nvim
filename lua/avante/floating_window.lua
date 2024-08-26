local api = vim.api

local namespace = api.nvim_create_namespace("avante_floating_window")

api.nvim_set_hl(namespace, "NormalFloat", { link = "Normal" })
api.nvim_set_hl(namespace, "FloatBorder", { link = "Normal" })

---@class FloatingWindow
---@field enter boolean | nil
---@field winid integer | nil
---@field bufnr integer | nil
---@field buf_options table | nil
---@field win_options table | nil
---@field float_options table | nil
---@field on_mount_handlers table | nil
---@field on_unmount_handlers table | nil
---@field augroup integer | nil
---@field keep_floating_style boolean | nil
local FloatingWindow = {}
FloatingWindow.__index = FloatingWindow

setmetatable(FloatingWindow, {
  __call = function(cls, ...)
    return cls.new(...)
  end,
})

---@class FloatingWindowOptions
---@field enter? boolean
---@field buf_options? table<string, any>
---@field win_options? table<string, any>
---@field float_options? table<string, any>
---@field keep_floating_style? boolean

---@param opts FloatingWindowOptions
---@return FloatingWindow
function FloatingWindow.new(opts)
  local instance = setmetatable({}, FloatingWindow)
  instance.winid = nil
  instance.bufnr = nil
  instance.enter = opts.enter or true
  instance.buf_options = opts.buf_options or {}
  instance.win_options = opts.win_options or {}
  instance.float_options = opts.float_options or {}
  instance.on_mount_handlers = {}
  instance.on_unmount_handlers = {}
  instance.augroup = nil
  instance.keep_floating_style = opts.keep_floating_style or false
  return instance
end

---@param split_winid integer
---@param opts FloatingWindowOptions
---@return FloatingWindow
function FloatingWindow.from_split_win(split_winid, opts)
  local split_win_width = api.nvim_win_get_width(split_winid)
  local split_win_height = api.nvim_win_get_height(split_winid)

  local calc_floating_win_size = function(width, height)
    return {
      width = math.max(width - 2, 1),
      height = math.max(height - 3, 1),
    }
  end

  local floating_win_size = calc_floating_win_size(split_win_width, split_win_height)

  local float_opts_ = vim.tbl_deep_extend("force", {
    relative = "win",
    win = split_winid,
    width = floating_win_size.width,
    height = floating_win_size.height,
    row = 1,
    col = 0,
    style = "minimal",
    border = { " " },
  }, opts.float_options or {})

  local win_opts_ = vim.tbl_deep_extend("force", {}, opts.win_options or {})

  local buf_opts_ = vim.tbl_deep_extend("force", {}, opts.buf_options or {})

  local floating_win = FloatingWindow({
    buf_options = buf_opts_,
    win_options = win_opts_,
    float_options = float_opts_,
    keep_floating_style = opts.keep_floating_style,
  })

  floating_win:on_mount(function(winid)
    api.nvim_create_autocmd("WinResized", {
      group = floating_win.augroup,
      callback = function()
        if
          not split_winid
          or not winid
          or not api.nvim_win_is_valid(split_winid)
          or not api.nvim_win_is_valid(winid)
        then
          return
        end

        local current_width = api.nvim_win_get_width(winid)
        local current_height = api.nvim_win_get_height(winid)

        if current_width == floating_win_size.width and current_height == floating_win_size.height then
          return
        end

        floating_win_size.width = current_width
        floating_win_size.height = current_height

        api.nvim_win_set_height(split_winid, current_height + 3)
        api.nvim_win_set_width(split_winid, current_width + 2)
      end,
    })

    api.nvim_create_autocmd("WinResized", {
      group = floating_win.augroup,
      callback = function()
        if
          not split_winid
          or not winid
          or not api.nvim_win_is_valid(split_winid)
          or not api.nvim_win_is_valid(winid)
        then
          return
        end

        local current_split_win_width = api.nvim_win_get_width(split_winid)
        local current_split_win_height = api.nvim_win_get_height(split_winid)

        if current_split_win_width == split_win_width and current_split_win_height == split_win_height then
          return
        end

        split_win_width = current_split_win_width
        split_win_height = current_split_win_height

        local current_floating_win_size = calc_floating_win_size(current_split_win_width, current_split_win_height)

        local old_floating_win_options = api.nvim_win_get_config(winid)
        local new_floating_win_options = vim.tbl_deep_extend("force", old_floating_win_options, {
          width = current_floating_win_size.width,
          height = current_floating_win_size.height,
        })
        api.nvim_win_set_config(winid, new_floating_win_options)
      end,
    })
  end)

  return floating_win
end

function FloatingWindow:__gc()
  self:unmount()
end

function FloatingWindow:__tostring()
  return "FloatingWindow"
end

function FloatingWindow:__eq(other)
  return self.winid == other.winid
end

---@param handler fun(number, number): nil
---@return nil
function FloatingWindow:on_mount(handler)
  table.insert(self.on_mount_handlers, handler)
end

---@param handler fun(nuber, nubmer): nil
---@return nil
function FloatingWindow:on_unmount(handler)
  table.insert(self.on_unmount_handlers, handler)
end

---@return nil
function FloatingWindow:mount()
  self.bufnr = api.nvim_create_buf(false, true)

  for option, value in pairs(self.buf_options) do
    api.nvim_set_option_value(option, value, { buf = self.bufnr })
  end

  self.winid = api.nvim_open_win(self.bufnr, self.enter, self.float_options)

  self.augroup = api.nvim_create_augroup("avante_floating_window_" .. tostring(self.winid), { clear = true })

  for option, value in pairs(self.win_options) do
    api.nvim_set_option_value(option, value, { win = self.winid })
  end

  if not self.keep_floating_style then
    api.nvim_win_set_hl_ns(self.winid, namespace)
  end

  for _, handler in ipairs(self.on_mount_handlers) do
    handler(self.winid, self.bufnr)
  end
end

---@return nil
function FloatingWindow:unmount()
  for _, handler in ipairs(self.on_unmount_handlers) do
    handler(self.winid, self.bufnr)
  end

  if self.augroup ~= nil then
    pcall(api.nvim_delete_augroup, self.augroup)
    self.augroup = nil
  end

  if self.bufnr and api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_delete(self.bufnr, { force = true })
    self.bufnr = nil
  end

  if self.winid and api.nvim_win_is_valid(self.winid) then
    api.nvim_win_close(self.winid, true)
    self.winid = nil
  end
end

---@param event string | string[]
---@param handler string | function
---@param options? table<"'once'" | "'nested'", boolean>
---@return nil
function FloatingWindow:on(event, handler, options)
  api.nvim_create_autocmd(event, {
    buffer = self.bufnr,
    callback = handler,
    once = options and options["once"] or false,
    nested = options and options["nested"] or false,
  })
end

---@param mode string|string[] check `:h :map-modes`
---@param lhs string|string[]
---@param handler string|fun(): nil handler for the mapping
---@param opts? vim.keymap.set.Opts
---@return nil
function FloatingWindow:map(mode, lhs, handler, opts)
  if not self.bufnr then
    error("floating buffer not found.")
  end
  local options = vim.deepcopy(opts or {})
  options.buffer = self.bufnr
  if type(lhs) ~= "table" then
    lhs = { lhs }
  end
  for _, lhs_ in ipairs(lhs) do
    vim.keymap.set(mode, lhs_, handler, options)
  end
end

return FloatingWindow
