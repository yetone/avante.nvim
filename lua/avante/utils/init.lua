local Path = require("plenary.path")

local api = vim.api
local fn = vim.fn
local lsp = vim.lsp

---@class avante.utils: LazyUtilCore
---@field tokens avante.utils.tokens
---@field root avante.utils.root
---@field repo_map avante.utils.repo_map
---@field file avante.utils.file
local M = {}

setmetatable(M, {
  __index = function(t, k)
    local ok, lazyutil = pcall(require, "lazy.core.util")
    if ok and lazyutil[k] then return lazyutil[k] end

    ---@diagnostic disable-next-line: no-unknown
    t[k] = require("avante.utils." .. k)
    return t[k]
  end,
})

---Check if a plugin is installed
---@param plugin string
---@return boolean
M.has = function(plugin)
  local ok, LazyConfig = pcall(require, "lazy.core.config")
  if ok then return LazyConfig.plugins[plugin] ~= nil end
  return package.loaded[plugin] ~= nil
end

M.is_win = function() return jit.os:find("Windows") ~= nil end

---@return "linux" | "darwin" | "windows"
M.get_os_name = function()
  local os_name = vim.uv.os_uname().sysname
  if os_name == "Linux" then
    return "linux"
  elseif os_name == "Darwin" then
    return "darwin"
  elseif os_name == "Windows_NT" then
    return "windows"
  else
    error("Unsupported operating system: " .. os_name)
  end
end

--- This function will run given shell command synchronously.
---@param input_cmd string
---@return vim.SystemCompleted
M.shell_run = function(input_cmd)
  local shell = vim.o.shell:lower()
  ---@type string
  local cmd

  -- powershell then we can just run the cmd
  if shell:match("powershell") or shell:match("pwsh") then
    cmd = input_cmd
  elseif fn.has("wsl") > 0 then
    -- wsl: powershell.exe -Command 'command "/path"'
    cmd = "powershell.exe -NoProfile -Command '" .. input_cmd:gsub("'", '"') .. "'"
  elseif fn.has("win32") > 0 then
    cmd = 'powershell.exe -NoProfile -Command "' .. input_cmd:gsub('"', "'") .. '"'
  else
    -- linux and macos we wil just do sh -c
    cmd = "sh -c " .. fn.shellescape(input_cmd)
  end

  local output = fn.system(cmd)
  local code = vim.v.shell_error

  return { stdout = output, code = code }
end

---@see https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/util/toggle.lua
---
---@alias _ToggleSet fun(state: boolean): nil
---@alias _ToggleGet fun(): boolean
---
---@class ToggleBind
---@field name string
---@field set _ToggleSet
---@field get _ToggleGet
---
---@class ToggleBind.wrap: ToggleBind
---@operator call:boolean

---@param toggle ToggleBind
M.toggle_wrap = function(toggle)
  return setmetatable(toggle, {
    __call = function()
      toggle.set(not toggle.get())
      local state = toggle.get()
      if state then
        M.info("enabled: " .. toggle.name)
      else
        M.warn("disabled: " .. toggle.name)
      end
      return state
    end,
  }) --[[@as ToggleBind.wrap]]
end

-- Wrapper around vim.keymap.set that will
-- not create a keymap if a lazy key handler exists.
-- It will also set `silent` to true by default.
--
---@param mode string|string[] Mode short-name, see |nvim_set_keymap()|.
---                            Can also be list of modes to create mapping on multiple modes.
---@param lhs string           Left-hand side |{lhs}| of the mapping.
---@param rhs string|function  Right-hand side |{rhs}| of the mapping, can be a Lua function.
---
---@param opts? vim.keymap.set.Opts
---@see |nvim_set_keymap()|
---@see |maparg()|
---@see |mapcheck()|
---@see |mapset()|
M.safe_keymap_set = function(mode, lhs, rhs, opts)
  ---@type boolean
  local ok
  ---@module "lazy.core.handler"
  local H

  ok, H = pcall(require, "lazy.core.handler")
  if not ok then
    M.debug("lazy.nvim is not available. Avante will use vim.keymap.set")
    vim.keymap.set(mode, lhs, rhs, opts)
    return
  end

  local Keys = H.handlers.keys
  ---@cast Keys LazyKeysHandler
  local modes = type(mode) == "string" and { mode } or mode
  ---@cast modes -string

  ---@param m string
  modes = vim.tbl_filter(function(m) return not (Keys and Keys.have and Keys:have(lhs, m)) end, modes)

  -- don't create keymap if a lazy keys handler exists
  if #modes > 0 then
    opts = opts or {}
    opts.silent = opts.silent ~= false
    if opts.remap and not vim.g.vscode then
      ---@diagnostic disable-next-line: no-unknown
      opts.remap = nil
    end
    vim.keymap.set(mode, lhs, rhs, opts)
  end
end

---@param str string
---@param opts? {suffix?: string, prefix?: string}
function M.trim(str, opts)
  if not opts then return str end
  local res = str
  if opts.suffix then
    res = str:sub(#str - #opts.suffix + 1) == opts.suffix and str:sub(1, #str - #opts.suffix) or str
  end
  if opts.prefix then res = str:sub(1, #opts.prefix) == opts.prefix and str:sub(#opts.prefix + 1) or str end
  return res
end

function M.in_visual_mode()
  local current_mode = fn.mode()
  return current_mode == "v" or current_mode == "V" or current_mode == ""
end

---Get the selected content and range in Visual mode
---@return avante.SelectionResult | nil Selected content and range
function M.get_visual_selection_and_range()
  if not M.in_visual_mode() then return nil end

  local Range = require("avante.range")
  local SelectionResult = require("avante.selection_result")

  -- Get the start and end positions of Visual mode
  local start_pos = fn.getpos("v")
  local end_pos = fn.getpos(".")

  -- Get the start and end line and column numbers
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]
  -- If the start point is after the end point, swap them
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end
  local content = "" -- luacheck: ignore
  local range = Range:new({ lnum = start_line, col = start_col }, { lnum = end_line, col = end_col })
  -- Check if it's a single-line selection
  if start_line == end_line then
    -- Get partial content of a single line
    local line = fn.getline(start_line)
    -- content = string.sub(line, start_col, end_col)
    content = line
  else
    -- Multi-line selection: Get all lines in the selection
    local lines = fn.getline(start_line, end_line)
    -- Extract partial content of the first line
    -- lines[1] = string.sub(lines[1], start_col)
    -- Extract partial content of the last line
    -- lines[#lines] = string.sub(lines[#lines], 1, end_col)
    -- Concatenate all lines in the selection into a string
    if type(lines) == "table" then
      content = table.concat(lines, "\n")
    else
      content = lines
    end
  end
  if not content then return nil end
  -- Return the selected content and range
  return SelectionResult:new(content, range)
end

---Wrapper around `api.nvim_buf_get_lines` which defaults to the current buffer
---@param start integer
---@param end_ integer
---@param buf integer?
---@return string[]
function M.get_buf_lines(start, end_, buf) return api.nvim_buf_get_lines(buf or 0, start, end_, false) end

---Get cursor row and column as (1, 0) based
---@param win_id integer?
---@return integer, integer
function M.get_cursor_pos(win_id) return unpack(api.nvim_win_get_cursor(win_id or 0)) end

---Check if the buffer is likely to have actionable conflict markers
---@param bufnr integer?
---@return boolean
function M.is_valid_buf(bufnr)
  bufnr = bufnr or 0
  return #vim.bo[bufnr].buftype == 0 and vim.bo[bufnr].modifiable
end

---@param name string?
---@return table<string, string>
function M.get_hl(name)
  if not name then return {} end
  return api.nvim_get_hl(0, { name = name })
end

M.lsp = {}

---@alias vim.lsp.Client.filter {id?: number, bufnr?: number, name?: string, method?: string, filter?:fun(client: vim.lsp.Client):boolean}

---@param opts? vim.lsp.Client.filter
---@return vim.lsp.Client[]
M.lsp.get_clients = function(opts)
  ---@type vim.lsp.Client[]
  local ret = vim.lsp.get_clients(opts)
  return (opts and opts.filter) and vim.tbl_filter(opts.filter, ret) or ret
end

--- vendor from lazy.nvim for early access and override

---@param path string
---@return string
function M.norm(path)
  if path:sub(1, 1) == "~" then
    local home = vim.uv.os_homedir()
    if home:sub(-1) == "\\" or home:sub(-1) == "/" then home = home:sub(1, -2) end
    path = home .. path:sub(2)
  end
  path = path:gsub("\\", "/"):gsub("/+", "/")
  return path:sub(-1) == "/" and path:sub(1, -2) or path
end

---@param msg string|string[]
---@param opts? LazyNotifyOpts
function M.notify(msg, opts)
  if vim.in_fast_event() then
    return vim.schedule(function() M.notify(msg, opts) end)
  end

  opts = opts or {}
  if type(msg) == "table" then
    ---@diagnostic disable-next-line: no-unknown
    msg = table.concat(vim.tbl_filter(function(line) return line or false end, msg), "\n")
  end
  ---@diagnostic disable-next-line: undefined-field
  if opts.stacktrace then
    ---@diagnostic disable-next-line: undefined-field
    msg = msg .. M.pretty_trace({ level = opts.stacklevel or 2 })
  end
  local lang = opts.lang or "markdown"
  ---@diagnostic disable-next-line: undefined-field
  local n = opts.once and vim.notify_once or vim.notify
  n(msg, opts.level or vim.log.levels.INFO, {
    on_open = function(win)
      local ok = pcall(function() vim.treesitter.language.add("markdown") end)
      if not ok then pcall(require, "nvim-treesitter") end
      vim.wo[win].conceallevel = 3
      vim.wo[win].concealcursor = ""
      vim.wo[win].spell = false
      local buf = api.nvim_win_get_buf(win)
      if not pcall(vim.treesitter.start, buf, lang) then
        vim.bo[buf].filetype = lang
        vim.bo[buf].syntax = lang
      end
    end,
    title = opts.title or "Avante",
  })
end

---@param msg string|string[]
---@param opts? LazyNotifyOpts
function M.error(msg, opts)
  opts = opts or {}
  opts.level = vim.log.levels.ERROR
  M.notify(msg, opts)
end

---@param msg string|string[]
---@param opts? LazyNotifyOpts
function M.info(msg, opts)
  opts = opts or {}
  opts.level = vim.log.levels.INFO
  M.notify(msg, opts)
end

---@param msg string|string[]
---@param opts? LazyNotifyOpts
function M.warn(msg, opts)
  opts = opts or {}
  opts.level = vim.log.levels.WARN
  M.notify(msg, opts)
end

function M.debug(...)
  if not require("avante.config").options.debug then return end

  local args = { ... }
  if #args == 0 then return end
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local formated_args = { "[" .. timestamp .. "] [AVANTE] [DEBUG]" }
  for _, arg in ipairs(args) do
    if type(arg) == "string" then
      table.insert(formated_args, arg)
    else
      table.insert(formated_args, vim.inspect(arg))
    end
  end
  print(unpack(formated_args))
end

function M.tbl_indexof(tbl, value)
  for i, v in ipairs(tbl) do
    if v == value then return i end
  end
  return nil
end

function M.update_win_options(winid, opt_name, key, value)
  local cur_opt_value = api.nvim_get_option_value(opt_name, { win = winid })

  if cur_opt_value:find(key .. ":") then
    cur_opt_value = cur_opt_value:gsub(key .. ":[^,]*", key .. ":" .. value)
  else
    if #cur_opt_value > 0 then cur_opt_value = cur_opt_value .. "," end
    cur_opt_value = cur_opt_value .. key .. ":" .. value
  end

  api.nvim_set_option_value(opt_name, cur_opt_value, { win = winid })
end

function M.get_win_options(winid, opt_name, key)
  local cur_opt_value = api.nvim_get_option_value(opt_name, { win = winid })
  if not cur_opt_value then return end
  local pieces = vim.split(cur_opt_value, ",")
  for _, piece in ipairs(pieces) do
    local kv_pair = vim.split(piece, ":")
    if kv_pair[1] == key then return kv_pair[2] end
  end
end

function M.get_winid(bufnr)
  for _, winid in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(winid) == bufnr then return winid end
  end
end

function M.unlock_buf(bufnr)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = true
end

function M.lock_buf(bufnr)
  vim.cmd("stopinsert")
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

---@param winnr? number
---@return nil
M.scroll_to_end = function(winnr)
  winnr = winnr or 0
  local bufnr = api.nvim_win_get_buf(winnr)
  local lnum = api.nvim_buf_line_count(bufnr)
  local last_line = api.nvim_buf_get_lines(bufnr, -2, -1, true)[1]
  api.nvim_win_set_cursor(winnr, { lnum, api.nvim_strwidth(last_line) })
end

---@param bufnr nil|integer
---@return nil
M.buf_scroll_to_end = function(bufnr)
  for _, winnr in ipairs(M.buf_list_wins(bufnr or 0)) do
    M.scroll_to_end(winnr)
  end
end

---@param bufnr nil|integer
---@return integer[]
M.buf_list_wins = function(bufnr)
  local wins = {}

  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end

  for _, winnr in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(winnr) and api.nvim_win_get_buf(winnr) == bufnr then table.insert(wins, winnr) end
  end

  return wins
end

local sidebar_buffer_var_name = "is_avante_sidebar_buffer"

function M.mark_as_sidebar_buffer(bufnr) api.nvim_buf_set_var(bufnr, sidebar_buffer_var_name, true) end

function M.is_sidebar_buffer(bufnr)
  local ok, v = pcall(api.nvim_buf_get_var, bufnr, sidebar_buffer_var_name)
  if not ok then return false end
  return v == true
end

function M.trim_spaces(s) return s:match("^%s*(.-)%s*$") end

function M.fallback(v, default_value) return type(v) == "nil" and default_value or v end

---Join URL parts together, handling slashes correctly
---@param ... string URL parts to join
---@return string Joined URL
function M.url_join(...)
  local parts = { ... }
  local result = parts[1] or ""

  for i = 2, #parts do
    local part = parts[i]
    if not part or part == "" then goto continue end

    -- Remove trailing slash from result if present
    if result:sub(-1) == "/" then result = result:sub(1, -2) end

    -- Remove leading slash from part if present
    if part:sub(1, 1) == "/" then part = part:sub(2) end

    -- Join with slash
    result = result .. "/" .. part

    ::continue::
  end

  return result
end

-- luacheck: push no max comment line length
---@param type_name "'nil'" | "'number'" | "'string'" | "'boolean'" | "'table'" | "'function'" | "'thread'" | "'userdata'" | "'list'" | '"map"'
---@return boolean
function M.is_type(type_name, v)
  ---@diagnostic disable-next-line: deprecated
  local islist = vim.islist or vim.tbl_islist
  if type_name == "list" then return islist(v) end

  if type_name == "map" then return type(v) == "table" and not islist(v) end

  return type(v) == type_name
end
-- luacheck: pop

---@param code string
---@return string
function M.get_indentation(code)
  if not code then return "" end
  return code:match("^%s*") or ""
end

--- remove indentation from code: spaces or tabs
function M.remove_indentation(code)
  if not code then return code end
  return code:gsub("^%s*", "")
end

function M.relative_path(absolute)
  local relative = fn.fnamemodify(absolute, ":.")
  if string.sub(relative, 0, 1) == "/" then return fn.fnamemodify(absolute, ":t") end
  return relative
end

function M.get_doc()
  local absolute = api.nvim_buf_get_name(0)
  local params = lsp.util.make_position_params(0, "utf-8")

  local position = {
    row = params.position.line + 1,
    col = params.position.character,
  }

  local doc = {
    uri = params.textDocument.uri,
    version = api.nvim_buf_get_var(0, "changedtick"),
    relativePath = M.relative_path(absolute),
    insertSpaces = vim.o.expandtab,
    tabSize = fn.shiftwidth(),
    indentSize = fn.shiftwidth(),
    position = position,
  }

  return doc
end

function M.prepend_line_number(content, start_line)
  start_line = start_line or 1
  local lines = vim.split(content, "\n")
  local result = {}
  for i, line in ipairs(lines) do
    i = i + start_line - 1
    table.insert(result, "L" .. i .. ": " .. line)
  end
  return table.concat(result, "\n")
end

function M.trim_line_number(line) return line:gsub("^L%d+: ", "") end

function M.trim_all_line_numbers(content)
  return vim
    .iter(vim.split(content, "\n"))
    :map(function(line)
      local new_line = M.trim_line_number(line)
      return new_line
    end)
    :join("\n")
end

function M.debounce(func, delay)
  local timer_id = nil

  return function(...)
    local args = { ... }

    if timer_id then fn.timer_stop(timer_id) end

    timer_id = fn.timer_start(delay, function()
      func(unpack(args))
      timer_id = nil
    end)

    return timer_id
  end
end

function M.winline(winid)
  local current_win = api.nvim_get_current_win()
  api.nvim_set_current_win(winid)
  local line = fn.winline()
  api.nvim_set_current_win(current_win)
  return line
end

function M.get_project_root() return M.root.get() end

function M.is_same_file_ext(target_ext, filepath)
  local ext = fn.fnamemodify(filepath, ":e")
  if (target_ext == "tsx" and ext == "ts") or (target_ext == "ts" and ext == "tsx") then return true end
  if (target_ext == "jsx" and ext == "js") or (target_ext == "js" and ext == "jsx") then return true end
  return ext == target_ext
end

-- Get recent filepaths in the same project and same file ext
function M.get_recent_filepaths(limit, filenames)
  local project_root = M.get_project_root()
  local current_ext = fn.expand("%:e")
  local oldfiles = vim.v.oldfiles
  local recent_files = {}

  for _, file in ipairs(oldfiles) do
    if vim.startswith(file, project_root) and M.is_same_file_ext(current_ext, file) then
      if filenames and #filenames > 0 then
        for _, filename in ipairs(filenames) do
          if file:find(filename) then table.insert(recent_files, file) end
        end
      else
        table.insert(recent_files, file)
      end
      if #recent_files >= (limit or 10) then break end
    end
  end

  return recent_files
end

local function pattern_to_lua(pattern)
  local lua_pattern = pattern:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
  lua_pattern = lua_pattern:gsub("%*%*/", ".-/")
  lua_pattern = lua_pattern:gsub("%*", "[^/]*")
  lua_pattern = lua_pattern:gsub("%?", ".")
  if lua_pattern:sub(-1) == "/" then lua_pattern = lua_pattern .. ".*" end
  return lua_pattern
end

function M.parse_gitignore(gitignore_path)
  local ignore_patterns = {}
  local negate_patterns = {}
  local file = io.open(gitignore_path, "r")
  if not file then return ignore_patterns, negate_patterns end

  for line in file:lines() do
    if line:match("%S") and not line:match("^#") then
      local trimmed_line = line:match("^%s*(.-)%s*$")
      if trimmed_line:sub(1, 1) == "!" then
        table.insert(negate_patterns, pattern_to_lua(trimmed_line:sub(2)))
      else
        table.insert(ignore_patterns, pattern_to_lua(trimmed_line))
      end
    end
  end

  file:close()
  return ignore_patterns, negate_patterns
end

function M.is_ignored(file, ignore_patterns, negate_patterns)
  for _, pattern in ipairs(negate_patterns) do
    if file:match(pattern) then return false end
  end
  for _, pattern in ipairs(ignore_patterns) do
    if file:match(pattern) then return true end
  end
  return false
end

function M.scan_directory(directory, ignore_patterns, negate_patterns)
  local files = {}
  local handle = vim.loop.fs_scandir(directory)

  if not handle then return files end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then break end

    local full_path = directory .. "/" .. name
    if type == "directory" then
      vim.list_extend(files, M.scan_directory(full_path, ignore_patterns, negate_patterns))
    elseif type == "file" then
      if not M.is_ignored(full_path, ignore_patterns, negate_patterns) then table.insert(files, full_path) end
    end
  end

  return files
end

function M.is_first_letter_uppercase(str) return string.match(str, "^[A-Z]") ~= nil end

---@param content string
---@return { new_content: string, enable_project_context: boolean, enable_diagnostics: boolean }
function M.extract_mentions(content)
  -- if content contains @codebase, enable project context and remove @codebase
  local new_content = content
  local enable_project_context = false
  local enable_diagnostics = false
  if content:match("@codebase") then
    enable_project_context = true
    new_content = content:gsub("@codebase", "")
  end
  if content:match("@diagnostics") then enable_diagnostics = true end
  return {
    new_content = new_content,
    enable_project_context = enable_project_context,
    enable_diagnostics = enable_diagnostics,
  }
end

---@alias AvanteMentions "codebase" | "diagnostics"
---@alias AvanteMentionCallback fun(args: string, cb?: fun(args: string): nil): nil
---@alias AvanteMention {description: string, command: AvanteMentions, details: string, shorthelp?: string, callback?: AvanteMentionCallback}
---@return AvanteMention[]
function M.get_mentions()
  return {
    {
      description = "codebase",
      command = "codebase",
      details = "repo map",
    },
    {
      description = "diagnostics",
      command = "diagnostics",
      details = "diagnostics",
    },
  }
end

local function get_opened_buffer_by_filepath(filepath)
  local absolute_path = Path:new(filepath):absolute()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if Path:new(fn.bufname(buf)):absolute() == absolute_path then return buf end
  end
  return nil
end

function M.get_or_create_buffer_with_filepath(filepath)
  -- Check if a buffer with this filepath already exists
  local existing_buf = get_opened_buffer_by_filepath(filepath)
  if existing_buf then return existing_buf end

  -- Create a new buffer without setting its name
  local buf = api.nvim_create_buf(true, false)

  -- Set the buffer options
  api.nvim_set_option_value("buftype", "", { buf = buf })

  -- Set the current buffer to the new buffer
  api.nvim_set_current_buf(buf)

  -- Use the edit command to load the file content and set the buffer name
  vim.cmd("edit " .. fn.fnameescape(filepath))

  return buf
end

---@param bufnr integer
---@param new_lines string[]
---@return { start_line: integer, end_line: integer, content: string[] }[]
local function get_buffer_content_diffs(bufnr, new_lines)
  local old_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local diffs = {}
  local prev_diff_idx = nil
  for i, line in ipairs(new_lines) do
    if line ~= old_lines[i] then
      if prev_diff_idx == nil then prev_diff_idx = i end
    else
      if prev_diff_idx ~= nil then
        local content = vim.list_slice(new_lines, prev_diff_idx, i - 1)
        table.insert(diffs, { start_line = prev_diff_idx, end_line = i, content = content })
        prev_diff_idx = nil
      end
    end
  end
  if prev_diff_idx ~= nil then
    table.insert(
      diffs,
      { start_line = prev_diff_idx, end_line = #new_lines + 1, content = vim.list_slice(new_lines, prev_diff_idx) }
    )
  end
  if #new_lines < #old_lines then
    table.insert(diffs, { start_line = #new_lines + 1, end_line = #old_lines + 1, content = {} })
  end
  table.sort(diffs, function(a, b) return a.start_line > b.start_line end)
  return diffs
end

--- Update the buffer content more efficiently by only updating the changed lines
---@param bufnr integer
---@param new_lines string[]
function M.update_buffer_content(bufnr, new_lines)
  local diffs = get_buffer_content_diffs(bufnr, new_lines)
  if #diffs == 0 then return end
  for _, diff in ipairs(diffs) do
    api.nvim_buf_set_lines(bufnr, diff.start_line - 1, diff.end_line - 1, false, diff.content)
  end
end

local severity = {
  [1] = "ERROR",
  [2] = "WARNING",
  [3] = "INFORMATION",
  [4] = "HINT",
}

---@class AvanteDiagnostic
---@field content string
---@field start_line number
---@field end_line number
---@field severity string
---@field source string

---@param bufnr integer
---@return AvanteDiagnostic[]
function M.get_diagnostics(bufnr)
  if bufnr == nil then bufnr = api.nvim_get_current_buf() end
  local diagnositcs = ---@type vim.Diagnostic[]
    vim.diagnostic.get(
      bufnr,
      { severity = { vim.diagnostic.severity.ERROR, vim.diagnostic.severity.WARN, vim.diagnostic.severity.HINT } }
    )
  return vim
    .iter(diagnositcs)
    :map(function(diagnostic)
      local d = {
        content = diagnostic.message,
        start_line = diagnostic.lnum + 1,
        end_line = diagnostic.end_lnum and diagnostic.end_lnum + 1 or diagnostic.lnum + 1,
        severity = severity[diagnostic.severity],
        source = diagnostic.source,
      }
      return d
    end)
    :totable()
end

---@param bufnr integer
---@param selection avante.SelectionResult
function M.get_current_selection_diagnostics(bufnr, selection)
  local diagnostics = M.get_diagnostics(bufnr)
  local selection_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics) do
    if selection.range.start.lnum <= diagnostic.start_line and selection.range.finish.lnum >= diagnostic.end_line then
      table.insert(selection_diagnostics, diagnostic)
    end
  end
  return selection_diagnostics
end

function M.uniform_path(path)
  local project_root = M.get_project_root()
  local abs_path = Path:new(project_root):joinpath(path):absolute()
  local relative_path = Path:new(abs_path):make_relative(project_root)
  return relative_path
end

function M.is_same_file(filepath_a, filepath_b) return M.uniform_path(filepath_a) == M.uniform_path(filepath_b) end

return M
