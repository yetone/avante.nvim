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
--- @field event_handlers table<string, function[]>

---@alias FileSelectorHandler fun(self: FileSelector, on_select: fun(filepaths: string[] | nil)): nil

function FileSelector:process_directory(absolute_path, project_root)
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
  local files = Utils.scan_directory_respect_gitignore({ directory = project_root, add_dirs = true })
  files = vim.iter(files):map(function(filepath) return Path:new(filepath):make_relative(project_root) end):totable()

  return vim.tbl_map(function(path)
    local rel_path = Path:new(path):make_relative(project_root)
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
    selected_files = {},
    event_handlers = {},
  }, { __index = self })
end

function FileSelector:reset()
  self.selected_filepaths = {}
  self.event_handlers = {}
end

function FileSelector:add_selected_file(filepath)
  if not filepath or filepath == "" then return end

  local absolute_path = Path:new(Utils.get_project_root()):joinpath(filepath):absolute()
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

function FileSelector:open() self:show_select_ui() end

function FileSelector:get_filepaths()
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

---@type FileSelectorHandler
function FileSelector:fzf_ui(handler)
  local success, fzf_lua = pcall(require, "fzf-lua")
  if not success then
    Utils.error("fzf-lua is not installed. Please install fzf-lua to use it as a file selector.")
    return
  end

  local filepaths = self:get_filepaths()

  local close_action = function() handler(nil) end
  fzf_lua.fzf_exec(
    filepaths,
    vim.tbl_deep_extend("force", {
      prompt = string.format("%s> ", PROMPT_TITLE),
      fzf_opts = {},
      git_icons = false,
      actions = {
        ["default"] = function(selected)
          if not selected or #selected == 0 then return close_action() end
          ---@type string[]
          local selections = {}
          for _, entry in ipairs(selected) do
            local file = fzf_lua.path.entry_to_file(entry)
            if file and file.path then table.insert(selections, file.path) end
          end

          handler(selections)
        end,
        ["esc"] = close_action,
        ["ctrl-c"] = close_action,
      },
    }, Config.file_selector.provider_opts)
  )
end

function FileSelector:mini_pick_ui(handler)
  -- luacheck: globals MiniPick
  if not _G.MiniPick then
    Utils.error("mini.pick is not set up. Please install and set up mini.pick to use it as a file selector.")
    return
  end
  local choose = function(item) handler(type(item) == "string" and { item } or item) end
  local choose_marked = function(items_marked) handler(items_marked) end
  local source = { choose = choose, choose_marked = choose_marked }
  local result = MiniPick.builtin.files(nil, { source = source })
  if result == nil then handler(nil) end
end

function FileSelector:snacks_picker_ui(handler)
  Snacks.picker.files({
    exclude = self.selected_filepaths,
    confirm = function(picker)
      picker:close()
      local items = picker:selected({ fallback = true })
      local files = vim.tbl_map(function(item) return item.file end, items)
      handler(files)
    end,
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
  local action_utils = require("telescope.actions.utils")

  local files = self:get_filepaths()

  pickers
    .new(
      {},
      vim.tbl_extend("force", {
        file_ignore_patterns = self.selected_filepaths,
        prompt_title = string.format("%s> ", PROMPT_TITLE),
        finder = finders.new_table(files),
        sorter = conf.file_sorter(),
        attach_mappings = function(prompt_bufnr, map)
          map("i", "<esc>", require("telescope.actions").close)
          actions.select_default:replace(function()
            local picker = action_state.get_current_picker(prompt_bufnr)

            if #picker:get_multi_selection() ~= 0 then
              local selections = {}

              action_utils.map_selections(prompt_bufnr, function(selection) table.insert(selections, selection[1]) end)

              handler(selections)
            else
              local selections = action_state.get_selected_entry()

              handler(selections)
            end

            actions.close(prompt_bufnr)
          end)
          return true
        end,
      }, Config.file_selector.provider_opts)
    )
    :find()
end

function FileSelector:native_ui(handler)
  local filepaths = self:get_filepaths()

  vim.ui.select(filepaths, {
    prompt = string.format("%s:", PROMPT_TITLE),
    format_item = function(item) return item end,
  }, function(item)
    if item then
      handler({ item })
    else
      handler(nil)
    end
  end)
end

---@return nil
function FileSelector:show_select_ui()
  local function handler(selected_paths) self:handle_path_selection(selected_paths) end

  vim.schedule(function()
    if Config.file_selector.provider == "native" then
      self:native_ui(handler)
    elseif Config.file_selector.provider == "fzf" then
      self:fzf_ui(handler)
    elseif Config.file_selector.provider == "mini.pick" then
      self:mini_pick_ui(handler)
    elseif Config.file_selector.provider == "snacks" then
      self:snacks_picker_ui(handler)
    elseif Config.file_selector.provider == "telescope" then
      self:telescope_ui(handler)
    elseif type(Config.file_selector.provider) == "function" then
      local title = string.format("%s:", PROMPT_TITLE) ---@type string
      local filepaths = self:get_filepaths() ---@type string[]
      local params = { title = title, filepaths = filepaths, handler = handler } ---@type avante.file_selector.IParams
      Config.file_selector.provider(params)
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
  for _, file_path in ipairs(self.selected_filepaths) do
    local lines, error = Utils.read_file_from_buf_or_disk(file_path)
    lines = lines or {}
    local filetype = Utils.get_filetype(file_path)
    if error ~= nil then
      Utils.error("error reading file: " .. error)
    else
      local content = table.concat(lines, "\n")
      table.insert(contents, { path = file_path, content = content, file_type = filetype })
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

return FileSelector
