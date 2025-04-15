local Utils = require("avante.utils")
local Path = require("plenary.path")
local scan = require("plenary.scandir")
local Config = require("avante.config")
local Selector = require("avante.ui.selector")

local PROMPT_TITLE = "(Avante) Add a file"

--- @class FileSelector
local FileSelector = {}

--- @class FileSelector
--- @field id integer
--- @field selected_filepaths string[]
--- @field event_handlers table<string, function[]>

---@alias FileSelectorHandler fun(self: FileSelector, on_select: fun(filepaths: string[] | nil)): nil

local function has_scheme(path) return path:find("^%w+://") ~= nil end

function FileSelector:process_directory(absolute_path, project_root)
  if absolute_path:sub(-1) == Utils.path_sep then absolute_path = absolute_path:sub(1, -2) end
  local files = scan.scan_dir(absolute_path, {
    hidden = false,
    depth = math.huge,
    add_dirs = false,
    respect_gitignore = true,
  })

  for _, file in ipairs(files) do
    local rel_path = Utils.make_relative_path(file, project_root)
    if not vim.tbl_contains(self.selected_filepaths, rel_path) then table.insert(self.selected_filepaths, rel_path) end
  end
  self:emit("update")
end

---@param selected_paths string[] | nil
---@return nil
function FileSelector:handle_path_selection(selected_paths)
  if not selected_paths then return end
  local project_root = Utils.get_project_root()

  for _, selected_path in ipairs(selected_paths) do
    local absolute_path = Path:new(project_root):joinpath(selected_path):absolute()

    local stat = vim.loop.fs_stat(absolute_path)
    if stat and stat.type == "directory" then
      self.process_directory(self, absolute_path, project_root)
    else
      local uniform_path = Utils.uniform_path(selected_path)
      if Config.file_selector.provider == "native" then
        table.insert(self.selected_filepaths, uniform_path)
      else
        if not vim.tbl_contains(self.selected_filepaths, uniform_path) then
          table.insert(self.selected_filepaths, uniform_path)
        end
      end
    end
  end
  self:emit("update")
end

local function get_project_filepaths()
  local project_root = Utils.get_project_root()
  local files = Utils.scan_directory({ directory = project_root, add_dirs = true })
  files = vim.iter(files):map(function(filepath) return Utils.make_relative_path(filepath, project_root) end):totable()

  return vim.tbl_map(function(path)
    local rel_path = Utils.make_relative_path(path, project_root)
    local stat = vim.loop.fs_stat(path)
    if stat and stat.type == "directory" then rel_path = rel_path .. "/" end
    return rel_path
  end, files)
end

---@param id integer
---@return FileSelector
function FileSelector:new(id)
  return setmetatable({
    id = id,
    selected_filepaths = {},
    event_handlers = {},
  }, { __index = self })
end

function FileSelector:reset()
  self.selected_filepaths = {}
  self.event_handlers = {}
  self:emit("update")
end

function FileSelector:add_selected_file(filepath)
  if not filepath or filepath == "" then return end

  local absolute_path = filepath:sub(1, 1) == "/" and filepath
    or Path:new(Utils.get_project_root()):joinpath(filepath):absolute()
  local stat = vim.loop.fs_stat(absolute_path)

  if stat and stat.type == "directory" then
    self.process_directory(self, absolute_path, Utils.get_project_root())
    return
  end
  local uniform_path = Utils.uniform_path(filepath)

  -- Avoid duplicates
  if not vim.tbl_contains(self.selected_filepaths, uniform_path) then
    table.insert(self.selected_filepaths, uniform_path)
    self:emit("update")
  end
end

function FileSelector:add_current_buffer()
  local current_buf = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(current_buf)

  -- Only process if it's a real file buffer
  if filepath and filepath ~= "" and not has_scheme(filepath) then
    local relative_path = require("avante.utils").relative_path(filepath)

    -- Check if file is already in list
    for i, path in ipairs(self.selected_filepaths) do
      if path == relative_path then
        -- Remove if found
        table.remove(self.selected_filepaths, i)
        self:emit("update")
        return true
      end
    end

    -- Add if not found
    self:add_selected_file(relative_path)
    return true
  end
  return false
end

function FileSelector:on(event, callback)
  local handlers = self.event_handlers[event]
  if not handlers then
    handlers = {}
    self.event_handlers[event] = handlers
  end

  table.insert(handlers, callback)
end

function FileSelector:emit(event, ...)
  local handlers = self.event_handlers[event]
  if not handlers then return end

  for _, handler in ipairs(handlers) do
    handler(...)
  end
end

function FileSelector:off(event, callback)
  if not callback then
    self.event_handlers[event] = {}
    return
  end
  local handlers = self.event_handlers[event]
  if not handlers then return end

  for i, handler in ipairs(handlers) do
    if handler == callback then
      table.remove(handlers, i)
      break
    end
  end
end

function FileSelector:open() self:show_selector_ui() end

function FileSelector:get_filepaths()
  if type(Config.file_selector.provider_opts.get_filepaths) == "function" then
    ---@type avante.file_selector.opts.IGetFilepathsParams
    local params = {
      cwd = Utils.get_project_root(),
      selected_filepaths = self.selected_filepaths,
    }
    return Config.file_selector.provider_opts.get_filepaths(params)
  end

  local filepaths = get_project_filepaths()

  table.sort(filepaths, function(a, b)
    local a_stat = vim.loop.fs_stat(a)
    local b_stat = vim.loop.fs_stat(b)
    local a_is_dir = a_stat and a_stat.type == "directory"
    local b_is_dir = b_stat and b_stat.type == "directory"

    if a_is_dir and not b_is_dir then
      return true
    elseif not a_is_dir and b_is_dir then
      return false
    else
      return a < b
    end
  end)

  return vim
    .iter(filepaths)
    :filter(function(filepath) return not vim.tbl_contains(self.selected_filepaths, filepath) end)
    :totable()
end

---@return nil
function FileSelector:show_selector_ui()
  local function handler(selected_paths) self:handle_path_selection(selected_paths) end

  vim.schedule(function()
    if Config.file_selector.provider ~= nil then
      Utils.warn("config.file_selector is deprecated, please use config.selector instead!")
      if type(Config.file_selector.provider) == "function" then
        local title = string.format("%s:", PROMPT_TITLE) ---@type string
        local filepaths = self:get_filepaths() ---@type string[]
        local params = { title = title, filepaths = filepaths, handler = handler } ---@type avante.file_selector.IParams
        Config.file_selector.provider(params)
      else
        ---@type avante.SelectorProvider
        local provider = "native"
        if Config.file_selector.provider == "native" then
          provider = "native"
        elseif Config.file_selector.provider == "fzf" then
          provider = "fzf_lua"
        elseif Config.file_selector.provider == "mini.pick" then
          provider = "mini_pick"
        elseif Config.file_selector.provider == "snacks" then
          provider = "snacks"
        elseif Config.file_selector.provider == "telescope" then
          provider = "telescope"
        elseif type(Config.file_selector.provider) == "function" then
          provider = Config.file_selector.provider
        end
        ---@cast provider avante.SelectorProvider
        local selector = Selector:new({
          provider = provider,
          title = PROMPT_TITLE,
          items = vim.tbl_map(function(filepath) return { id = filepath, title = filepath } end, self:get_filepaths()),
          default_item_id = self.selected_filepaths[1],
          selected_item_ids = self.selected_filepaths,
          provider_opts = Config.file_selector.provider_opts,
          on_select = function(item_ids) self:handle_path_selection(item_ids) end,
        })
        selector:open()
      end
    else
      local selector = Selector:new({
        provider = Config.selector.provider,
        title = PROMPT_TITLE,
        items = vim.tbl_map(function(filepath) return { id = filepath, title = filepath } end, self:get_filepaths()),
        default_item_id = self.selected_filepaths[1],
        selected_item_ids = self.selected_filepaths,
        provider_opts = Config.selector.provider_opts,
        on_select = function(item_ids) self:handle_path_selection(item_ids) end,
      })
      selector:open()
    end
  end)

  -- unlist the current buffer as vim.ui.select will be listed
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
end

---@param idx integer
---@return boolean
function FileSelector:remove_selected_filepaths_with_index(idx)
  if idx > 0 and idx <= #self.selected_filepaths then
    table.remove(self.selected_filepaths, idx)
    self:emit("update")
    return true
  end
  return false
end

function FileSelector:remove_selected_file(rel_path)
  local uniform_path = Utils.uniform_path(rel_path)
  local idx = Utils.tbl_indexof(self.selected_filepaths, uniform_path)
  if idx then self:remove_selected_filepaths_with_index(idx) end
end

---@return { path: string, content: string, file_type: string }[]
function FileSelector:get_selected_files_contents()
  local contents = {}
  for _, filepath in ipairs(self.selected_filepaths) do
    local lines, error = Utils.read_file_from_buf_or_disk(filepath)
    lines = lines or {}
    local filetype = Utils.get_filetype(filepath)
    if error ~= nil then
      Utils.error("error reading file: " .. error)
    else
      local content = table.concat(lines, "\n")
      table.insert(contents, { path = filepath, content = content, file_type = filetype })
    end
  end
  return contents
end

function FileSelector:get_selected_filepaths() return vim.deepcopy(self.selected_filepaths) end

---@return nil
function FileSelector:add_quickfix_files()
  local quickfix_files = vim
    .iter(vim.fn.getqflist({ items = 0 }).items)
    :filter(function(item) return item.bufnr ~= 0 end)
    :map(function(item) return Utils.relative_path(vim.api.nvim_buf_get_name(item.bufnr)) end)
    :totable()
  for _, filepath in ipairs(quickfix_files) do
    self:add_selected_file(filepath)
  end
end

---@return nil
function FileSelector:add_buffer_files()
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    -- Skip invalid or unlisted buffers
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      -- Skip empty paths and special buffers (like terminals)
      if filepath ~= "" and not has_scheme(filepath) then
        local relative_path = Utils.relative_path(filepath)
        self:add_selected_file(relative_path)
      end
    end
  end
end

return FileSelector
