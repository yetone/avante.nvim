local Utils = require("avante.utils")
local Path = require("plenary.path")
local scan = require("plenary.scandir")

--- @class FileSelector
local FileSelector = {}

--- @class FileSelector
--- @field id integer
--- @field selected_filepaths string[]
--- @field file_cache string[]
--- @field event_handlers table<string, function[]>

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
  self:update_file_cache()
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

---@return nil
function FileSelector:show_select_ui()
  vim.schedule(function()
    local filepaths = vim
      .iter(self.file_cache)
      :filter(function(filepath) return not vim.tbl_contains(self.selected_filepaths, filepath) end)
      :totable()

    vim.ui.select(filepaths, {
      prompt = "(Avante) Add a file:",
      format_item = function(item) return item end,
    }, function(filepath)
      if not filepath then return end
      table.insert(self.selected_filepaths, Utils.uniform_path(filepath))
      self:emit("update")
    end)
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

return FileSelector
