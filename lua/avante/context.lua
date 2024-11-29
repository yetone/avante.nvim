local api = vim.api
local Config = require("avante.config")
local Utils = require("avante.utils")
local scan = require("plenary.scandir")

--- @class avante.Context
local Context = {}

--- @class avante.Context
--- @field id integer
--- @field winid integer
--- @field bufnr integer
--- @field augroup integer | nil
--- @field context_files string[]
--- @field file_cache string[]

---@param id integer
---@return avante.Context
function Context:new(id)
  return setmetatable({
    id = id,
    augroup = api.nvim_create_augroup("AvanteContext", { clear = true }),
    context_files = {},
    file_cache = {},
  }, { __index = self })
end

---@return nil
function Context:open()
  self:close()

  local bufnr = api.nvim_create_buf(false, true)
  self.bufnr = bufnr
  vim.bo[bufnr].filetype = "AvanteContext"
  Utils.mark_as_sidebar_buffer(bufnr)

  -- Set up highlight groups
  self:setup_highlights()

  local win_opts = vim.tbl_extend("force", {
    relative = "cursor",
    width = 40,
    height = 5,
    row = 1,
    col = 0,
    style = "minimal",
    border = Config.windows.edit.border,
    title = { { "Context", "FloatTitle" } },
    title_pos = "center",
  }, {})

  local winid = api.nvim_open_win(bufnr, true, win_opts)
  self.winid = winid

  api.nvim_set_option_value("wrap", true, { win = winid })
  api.nvim_set_option_value("cursorline", true, { win = winid })
  api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  api.nvim_buf_set_option(bufnr, "modifiable", false)

  self:bind_context_key()
  self:setup_autocmds()

  self:update_file_cache()

  self:render()
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
function Context:close()
  self:unbind_context_key()

  if api.nvim_get_mode().mode == "i" then vim.cmd([[stopinsert]]) end
  if self.winid and api.nvim_win_is_valid(self.winid) then
    api.nvim_win_close(self.winid, true)
    self.winid = nil
  end
  if self.bufnr and api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_delete(self.bufnr, { force = true })
    self.bufnr = nil
  end
  if self.augroup then
    api.nvim_del_augroup_by_id(self.augroup)
    self.augroup = nil
  end
end

---@return nil
function Context:bind_context_key()
  -- Disable mode switching keys
  vim.keymap.set("n", "i", "<NOP>", { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set("n", "I", "<NOP>", { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set("n", "a", "<NOP>", { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set("n", "A", "<NOP>", { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set("n", "o", "<NOP>", { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set("n", "O", "<NOP>", { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set("n", "R", "<NOP>", { buffer = self.bufnr, noremap = true, silent = true })

  -- Normal operations
  vim.keymap.set("n", "q", function() self:close() end, { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set("n", "<ESC>", function() self:close() end, { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set("n", "s", function() self:add_context() end, { buffer = self.bufnr, noremap = true, silent = true })
  vim.keymap.set(
    "n",
    "d",
    function() self:remove_context() end,
    { buffer = self.bufnr, noremap = true, silent = true }
  )
end

---@return nil
function Context:unbind_context_key()
  pcall(vim.keymap.del, "n", "s", { buffer = self.bufnr })
  pcall(vim.keymap.del, "n", "d", { buffer = self.bufnr })
end

---@return nil
function Context:setup_autocmds()
  local bufnr = self.bufnr
  local group = self.augroup

  local quit_id, close_unfocus

  quit_id = api.nvim_create_autocmd("QuitPre", {
    group = group,
    buffer = bufnr,
    once = true,
    nested = true,
    callback = function()
      self:close()
      if not quit_id then
        api.nvim_del_autocmd(quit_id)
        quit_id = nil
      end
    end,
  })
  close_unfocus = api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      self:close()
      if close_unfocus then
        api.nvim_del_autocmd(close_unfocus)
        close_unfocus = nil
      end
    end,
  })
end

---@return nil
function Context:setup_highlights()
  -- Define colors for different highlights
  local colors = {
    "#1a5f4c", -- Deep teal
    "#2c4f9c", -- Royal blue
    "#683a97", -- Purple
    "#9c2c4f", -- Deep rose
    "#3a974b", -- Forest green
    "#974b3a", -- Rust
    "#4b3a97", -- Deep blue-purple
    "#97683a", -- Bronze
  }

  -- Create highlight groups
  for i = 1, 8 do
    vim.api.nvim_set_hl(0, "AvanteContextFile" .. i, {
      bg = colors[i],
      default = true,
    })
  end
end

---@return nil
function Context:render()
  local display_text = ""
  local highlights = {}
  local col = 0

  for i, file in ipairs(self.context_files) do
    local filename = vim.fs.basename(file) .. " "
    display_text = display_text .. filename

    -- Only highlight the filename part, not the space
    local name_width = vim.fn.strwidth(vim.fs.basename(file))

    -- Add highlight for just the filename (excluding space)
    table.insert(highlights, {
      group = "AvanteContextFile" .. ((i - 1) % 8 + 1),
      start_col = col,
      end_col = col + name_width,
    })

    col = col + vim.fn.strwidth(filename)
  end

  -- Temporarily make buffer modifiable
  api.nvim_buf_set_option(self.bufnr, "modifiable", true)
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { display_text })

  -- Apply highlights
  local ns_id = api.nvim_create_namespace("avante_context")
  api.nvim_buf_clear_namespace(self.bufnr, ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
    api.nvim_buf_add_highlight(self.bufnr, ns_id, hl.group, 0, hl.start_col, hl.end_col)
  end

  api.nvim_buf_set_option(self.bufnr, "modifiable", false)

  if #self.context_files <= 0 then self:add_context() end
end

---@return nil
function Context:add_context()
  vim.ui.select(self.file_cache, {
    prompt = "Add context:",
    format_item = function(item) return item end,
  }, function(choice)
    if choice then
      table.insert(self.context_files, choice)
      self:open()
      -- Move cursor to the last line
      vim.cmd("normal! G")
    end
  end)
end

---@return string
function Context:get_full_string_under_cursor()
  -- Get the current line's text
  local line = api.nvim_get_current_line()
  -- Get cursor position
  local col = vim.fn.col(".") - 1

  -- Handle empty line case
  if #line == 0 then return "" end

  -- If we're on a space, look for adjacent non-space
  if line:sub(col + 1, col + 1):match("%s") then
    -- Look right first
    local right_pos = col + 1
    while right_pos <= #line and line:sub(right_pos, right_pos):match("%s") do
      right_pos = right_pos + 1
    end
    if right_pos <= #line then
      col = right_pos - 1
    else
      -- Look left
      local left_pos = col
      while left_pos > 0 and line:sub(left_pos, left_pos):match("%s") do
        left_pos = left_pos - 1
      end
      if left_pos > 0 then col = left_pos - 1 end
    end
  end

  -- Find the start of the string (look for space boundary)
  local start_pos = col + 1
  while start_pos > 0 and not line:sub(start_pos, start_pos):match("%s") do
    start_pos = start_pos - 1
  end
  start_pos = start_pos + 1

  -- Find the end of the string (look for space boundary)
  local end_pos = col + 1
  while end_pos <= #line and not line:sub(end_pos, end_pos):match("%s") do
    end_pos = end_pos + 1
  end
  end_pos = end_pos - 1

  -- Extract the full string
  return line:sub(start_pos, end_pos)
end

---@return nil
function Context:remove_context()
  local current_string = self:get_full_string_under_cursor()
  for i, file_path in ipairs(self.context_files) do
    if vim.fs.basename(file_path) == current_string then
      table.remove(self.context_files, i)
      break
    end
  end
  self:update_file_cache()
  self:render()
end

---@return table<string, string>
function Context:get_context_file_content()
  local contents = {}
  for _, file_path in ipairs(self.context_files) do
    local file = io.open(file_path, "r")
    if file then
      local content = file:read("*all")
      file:close()
      contents[file_path] = content
    end
  end
  return contents
end

---@return string
function Context:get_context_summary()
  if #self.context_files < 1 then return "" end

  local summary = "- Context files:\n"
  for _, file_path in ipairs(self.context_files) do
    summary = summary .. "  - " .. file_path .. "\n"
  end
  return summary
end

function Context:get_files()
  self:update_file_cache()

  local files = {}

  for _, file in ipairs(self.file_cache) do
    table.insert(files, { description = file, command = file })
  end

  return files
end

return Context
