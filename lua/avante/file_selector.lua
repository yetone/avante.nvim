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
  if not filepath or filepath == "" then return end

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

---@return nil
function FileSelector:open()
  if Config.file_selector.provider == "native" then self:update_file_cache() end
  self:show_select_ui()
end

---@return nil
function FileSelector:update_file_cache()
  local project_root = Path:new(Utils.get_project_root()):absolute()

  local filepaths = scan.scan_dir(project_root, {
    respect_gitignore = true,
  })

  -- Sort buffer names alphabetically
  table.sort(filepaths, function(a, b) return a < b end)

  self.file_cache = vim
    .iter(filepaths)
    :map(function(filepath) return Path:new(filepath):make_relative(project_root) end)
    :totable()
end

---@type FileSelectorHandler
function FileSelector:fzf_ui(handler)
  local success, fzf_lua = pcall(require, "fzf-lua")
  if not success then
    Utils.error("fzf-lua is not installed. Please install fzf-lua to use it as a file selector.")
    return
  end

  local close_action = function() handler(nil) end
  fzf_lua.files(vim.tbl_deep_extend("force", Config.file_selector.provider_opts, {
    file_ignore_patterns = self.selected_filepaths,
    prompt = string.format("%s> ", PROMPT_TITLE),
    fzf_opts = {},
    git_icons = false,
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then return close_action() end
        local selections = {}
        for _, entry in ipairs(selected) do
          local file = fzf_lua.path.entry_to_file(entry)
          if file and file.path then table.insert(selections, file.path) end
        end

        if #selections > 0 then handler(#selections == 1 and selections[1] or selections) end
      end,
      ["esc"] = close_action,
      ["ctrl-c"] = close_action,
    },
  }))
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

  pickers
    .new(
      {},
      vim.tbl_extend("force", Config.file_selector.provider_opts, {
        file_ignore_patterns = self.selected_filepaths,
        prompt_title = string.format("%s> ", PROMPT_TITLE),
        finder = finders.new_oneshot_job({ "git", "ls-files" }, { cwd = Utils.get_project_root() }),
        sorter = conf.file_sorter(),
        attach_mappings = function(prompt_bufnr, map)
          map("i", "<esc>", require("telescope.actions").close)

          actions.select_default:replace(function()
            local picker = action_state.get_current_picker(prompt_bufnr)

            if #picker:get_multi_selection() ~= 0 then
              local selections = {}

              action_utils.map_selections(prompt_bufnr, function(selection) table.insert(selections, selection[1]) end)

              if #selections > 0 then handler(selections) end
            else
              local selection = action_state.get_selected_entry()

              handler(selection[1])
            end

            actions.close(prompt_bufnr)
          end)
          return true
        end,
      })
    )
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
  }, handler)
end

---@return nil
function FileSelector:show_select_ui()
  local handler = function(filepaths)
    if not filepaths then return end
    -- Convert single filepath to array for unified handling
    local paths = type(filepaths) == "string" and { filepaths } or filepaths

    for _, filepath in ipairs(paths) do
      local uniform_path = Utils.uniform_path(filepath)
      if Config.file_selector.provider == "native" then
        table.insert(self.selected_filepaths, uniform_path)
      else
        if not vim.tbl_contains(self.selected_filepaths, uniform_path) then
          table.insert(self.selected_filepaths, uniform_path)
        end
      end
    end

    self:emit("update")
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
    local file = io.open(file_path, "r")
    if file then
      local content = file:read("*all")
      file:close()

      -- Detect the file type
      local filetype = vim.filetype.match({ filename = file_path, contents = contents }) or "unknown"

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
