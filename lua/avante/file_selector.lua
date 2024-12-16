local Utils = require("avante.utils")
local Path = require("plenary.path")
local scan = require("plenary.scandir")
local Config = require("avante.config")

local PROMPT_TITLE = "(Avante) Add a file"

--- @class FileSelector
local FileSelector = {}

--- @class FileSelector
--- @field id integer
--- @field selected_filepaths string[]
--- @field file_cache string[]
--- @field event_handlers table<string, function[]>

---@alias FileSelectorHandler fun(self: FileSelector, on_select: fun(on_select: fun(filepath: string)|nil)): nil

local function process_directory(self, absolute_path, project_root)
  local files = scan.scan_dir(absolute_path, {
    hidden = false,
    depth = math.huge,
    add_dirs = false,
    respect_gitignore = true,
  })

  for _, file in ipairs(files) do
    local rel_path = Path:new(file):make_relative(project_root)
    if not vim.tbl_contains(self.selected_filepaths, rel_path) then table.insert(self.selected_filepaths, rel_path) end
  end
  self:emit("update")
end

local function handle_path_selection(self, selected_path)
  if not selected_path then return end
  local project_root = Utils.get_project_root()
  local absolute_path = Path:new(project_root):joinpath(selected_path):absolute()

  local stat = vim.loop.fs_stat(absolute_path)
  if stat and stat.type == "directory" then
    selected_path = selected_path:gsub("/$", "")
    process_directory(self, absolute_path, project_root)
  else
    local uniform_path = Utils.uniform_path(selected_path)
    if not vim.tbl_contains(self.selected_filepaths, uniform_path) then
      table.insert(self.selected_filepaths, uniform_path)
      self:emit("update")
    end
  end
end

local function get_project_files()
  local project_root = Utils.get_project_root()
  local files = scan.scan_dir(project_root, {
    hidden = true,
    add_dirs = true,
    respect_gitignore = true
  })

  return vim.tbl_map(function(path)
    local rel_path = Path:new(path):make_relative(project_root)
    local stat = vim.loop.fs_stat(path)
    if stat and stat.type == "directory" then
      rel_path = rel_path .. "/"
    end
    return rel_path
  end, files)
end

---@param id integer
---@return FileSelector
function FileSelector:new(id)
  return setmetatable({
    id = id,
    selected_files = {},
    file_cache = {},
    event_handlers = {},
  }, { __index = self })
end

function FileSelector:reset()
  self.selected_filepaths = {}
  self.event_handlers = {}
end

function FileSelector:add_selected_file(filepath)
  local absolute_path = Path:new(Utils.get_project_root()):joinpath(filepath):absolute()
  local stat = vim.loop.fs_stat(absolute_path)

  if stat and stat.type == "directory" then
    process_directory(self, absolute_path, Utils.get_project_root())
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
  if filepath and filepath ~= "" and not vim.startswith(filepath, "avante://") then
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

function FileSelector:open()
  if Config.file_selector.provider == "native" then self:update_file_cache() end
  self:show_select_ui()
end

function FileSelector:update_file_cache()
  local project_root = Path:new(Utils.get_project_root()):absolute()

  local filepaths = scan.scan_dir(project_root, {
    respect_gitignore = true,
    add_dirs = true,
  })

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

  self.file_cache = vim
    .iter(filepaths)
    :map(function(filepath)
      local rel_path = Path:new(filepath):make_relative(project_root)
      local stat = vim.loop.fs_stat(filepath)
      if stat and stat.type == "directory" then rel_path = rel_path .. "/" end
      return rel_path
    end)
    :totable()
end

---@type FileSelectorHandler
function FileSelector:fzf_ui(handler)
  local success, fzf_lua = pcall(require, "fzf-lua")
  if not success then
    Utils.error("fzf-lua is not installed. Please install fzf-lua to use it as a file selector.")
    return
  end

  local relative_paths = get_project_files()

  local close_action = function() handler(nil) end

  fzf_lua.fzf_exec(relative_paths, {
    prompt = string.format("%s> ", PROMPT_TITLE),
    actions = {
      ["default"] = function(selected) handle_path_selection(self, selected[1]) end,
      ["esc"] = close_action,
      ["ctrl-c"] = close_action,
    },
  })
end
function FileSelector:telescope_ui(handler)
  local success, _ = pcall(require, "telescope")
  if not success then
    Utils.error("telescope is not installed. Please install telescope to use it as a file selector.")
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local relative_paths = get_project_files()

  pickers
    .new({}, {
      prompt_title = string.format("%s> ", PROMPT_TITLE),
      finder = finders.new_table({
        results = relative_paths,
 a     }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        map("i", "<esc>", require("telescope.actions").close)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          handle_path_selection(self, selection[1])
        end)
        return true
      end,
    })
    :find()
end

function FileSelector:native_ui(handler)
  local filepaths = vim
    .iter(self.file_cache)
    :filter(function(filepath) return not vim.tbl_contains(self.selected_filepaths, filepath) end)
    :totable()

  vim.ui.select(filepaths, {
    prompt = string.format("%s:", PROMPT_TITLE),
    format_item = function(item) return item end,
  }, function(selected_path)
    handle_path_selection(self, selected_path)
  end)
end
---@return nil
function FileSelector:show_select_ui()
  local handler = function(filepath)
    if not filepath then return end
    local uniform_path = Utils.uniform_path(filepath)
    if Config.file_selector.provider == "native" then
      -- Native handler filters out already selected files
      table.insert(self.selected_filepaths, uniform_path)
      self:emit("update")
    else
      if not vim.tbl_contains(self.selected_filepaths, uniform_path) then
        table.insert(self.selected_filepaths, uniform_path)
        self:emit("update")
      end
    end
  end

  vim.schedule(function()
    if Config.file_selector.provider == "native" then
      self:native_ui(handler)
    elseif Config.file_selector.provider == "fzf" then
      self:fzf_ui(handler)
    elseif Config.file_selector.provider == "telescope" then
      self:telescope_ui(handler)
    else
      Utils.error("Unknown file selector provider: " .. Config.file_selector.provider)
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
function FileSelector:remove_selected_filepaths(idx)
  if idx > 0 and idx <= #self.selected_filepaths then
    table.remove(self.selected_filepaths, idx)
    self:emit("update")
    return true
  end
  return false
end

---@return { path: string, content: string, file_type: string }[]
function FileSelector:get_selected_files_contents()
  local contents = {}
  for _, file_path in ipairs(self.selected_filepaths) do
    local ok, file = pcall(io.open, file_path, "r")
    if ok and file then
      local content = file:read("*all")
      file:close()

      -- Detect the file type
      local filetype = vim.filetype.match({ filename = file_path, contents = content }) or "unknown"
      table.insert(contents, { path = file_path, content = content, file_type = filetype })
    end
  end
  return contents
end

function FileSelector:get_selected_filepaths() return vim.deepcopy(self.selected_filepaths) end

return FileSelector
