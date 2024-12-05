local scan = require("plenary.scandir")

--- @class avante.Context
local Context = {}

--- @class avante.Context
--- @field id integer
--- @field context_files string[]
--- @field file_cache string[]
--- @field on_update function

---@param id integer
---@return avante.Context
function Context:new(id)
  return setmetatable({
    id = id,
    context_files = {},
    file_cache = {},
    on_update = nil,
  }, { __index = self })
end

function Context:event(event, callback)
  if event == "on_update" then self.on_update = callback end
end

---@return nil
function Context:open()
  self:update_file_cache()
  self:add_context()
end

---@return nil
function Context:update_file_cache()
  local files = scan.scan_dir(".", {
    respect_gitignore = true,
  })

  -- Filter files in callback
  files = vim.tbl_filter(function(file)
    for _, ctx in ipairs(self.context_files) do
      if ctx == file then return false end
    end
    return true
  end, files)

  -- Sort buffer names alphabetically
  table.sort(files, function(a, b) return a < b end)

  self.file_cache = files
end

---@return nil
function Context:add_context()
  vim.schedule(function()
    vim.ui.select(self.file_cache, {
      prompt = "Add context:",
      format_item = function(item) return item end,
    }, function(choice)
      if choice then
        table.insert(self.context_files, choice)
        self:on_update()
      end
    end)
  end)

  -- unlist the current buffer as vim.ui.select will be listed
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  vim.api.nvim_buf_set_option(bufnr, "buflisted", false)
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
end

---@param id integer
---@return boolean
function Context:remove_context_file(id)
  if id > 0 and id <= #self.context_files then
    table.remove(self.context_files, id)
    if self.on_update then self:on_update() end
    return true
  end
  return false
end

---@return { path: string, content: string, file_type: string }[]
function Context:get_context_file_content()
  local contents = {}
  for _, file_path in ipairs(self.context_files) do
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

---@return string
function Context:get_context_summary()
  if #self.context_files < 1 then return "" end

  local summary = "- Selected files:\n"
  for _, file_path in ipairs(self.context_files) do
    summary = summary .. "  - " .. file_path .. "\n"
  end
  return summary
end

function Context:get_context_files()
  local selected_files = {}

  for _, selected_file in ipairs(self.context_files) do
    table.insert(selected_files, selected_file)
  end

  return selected_files
end

return Context
