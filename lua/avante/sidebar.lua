local api = vim.api
local fn = vim.fn

local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local Provider = require("avante.providers")
local Path = require("avante.path")
local Config = require("avante.config")
local Diff = require("avante.diff")
local Llm = require("avante.llm")
local Utils = require("avante.utils")
local Highlights = require("avante.highlights")
local RepoMap = require("avante.repo_map")
local FileSelector = require("avante.file_selector")

local RESULT_BUF_NAME = "AVANTE_RESULT"
local VIEW_BUFFER_UPDATED_PATTERN = "AvanteViewBufferUpdated"
local CODEBLOCK_KEYBINDING_NAMESPACE = api.nvim_create_namespace("AVANTE_CODEBLOCK_KEYBINDING")
local SELECTED_FILES_HINT_NAMESPACE = api.nvim_create_namespace("AVANTE_SELECTED_FILES_HINT")
local PRIORITY = vim.highlight.priorities.user

---@class avante.Sidebar
local Sidebar = {}

---@class avante.CodeState
---@field winid integer
---@field bufnr integer
---@field selection avante.SelectionResult | nil

---@class avante.Sidebar
---@field id integer
---@field augroup integer
---@field code avante.CodeState
---@field winids table<string, integer>
---@field result_container NuiSplit | nil
---@field selected_code_container NuiSplit | nil
---@field selected_files_container NuiSplit | nil
---@field input_container NuiSplit | nil
---@field file_selector FileSelector

---@param id integer the tabpage id retrieved from api.nvim_get_current_tabpage()
function Sidebar:new(id)
  return setmetatable({
    id = id,
    code = { bufnr = 0, winid = 0, selection = nil },
    winids = {
      result_container = 0,
      selected_files_container = 0,
      selected_code_container = 0,
      input_container = 0,
    },
    result_container = nil,
    selected_code_container = nil,
    selected_files_container = nil,
    input_container = nil,
    file_selector = FileSelector:new(id),
  }, { __index = self })
end

function Sidebar:delete_autocmds()
  if self.augroup then api.nvim_del_augroup_by_id(self.augroup) end
  self.augroup = nil
end

function Sidebar:reset()
  self:unbind_apply_key()
  self:unbind_sidebar_keys()
  self:delete_autocmds()
  self.code = { bufnr = 0, winid = 0, selection = nil }
  self.winids =
    { result_container = 0, selected_files_container = 0, selected_code_container = 0, input_container = 0 }
  self.result_container = nil
  self.selected_code_container = nil
  self.selected_files_container = nil
  self.input_container = nil
end

---@class SidebarOpenOptions: AskOptions
---@field selection? avante.SelectionResult

---@param opts SidebarOpenOptions
function Sidebar:open(opts)
  opts = opts or {}
  local in_visual_mode = Utils.in_visual_mode() and self:in_code_win()
  if not self:is_open() then
    self:reset()
    self:initialize()
    if opts.selection then self.code.selection = opts.selection end
    self:render(opts)
    self:focus()
  else
    if in_visual_mode or opts.selection then
      self:close()
      self:reset()
      self:initialize()
      if opts.selection then self.code.selection = opts.selection end
      self:render(opts)
      return self
    end
    self:focus()
  end

  if not vim.g.avante_login or vim.g.avante_login == false then
    api.nvim_exec_autocmds("User", { pattern = Provider.env.REQUEST_LOGIN_PATTERN })
    vim.g.avante_login = true
  end

  vim.cmd("wincmd =")
  return self
end

---@class SidebarCloseOptions
---@field goto_code_win? boolean

---@param opts? SidebarCloseOptions
function Sidebar:close(opts)
  opts = vim.tbl_extend("force", { goto_code_win = true }, opts or {})
  self:delete_autocmds()
  for _, comp in pairs(self) do
    if comp and type(comp) == "table" and comp.unmount then comp:unmount() end
  end
  if opts.goto_code_win and self.code and self.code.winid and api.nvim_win_is_valid(self.code.winid) then
    fn.win_gotoid(self.code.winid)
  end

  vim.cmd("wincmd =")
end

---@return boolean
function Sidebar:focus()
  if self:is_open() then
    fn.win_gotoid(self.result_container.winid)
    return true
  end
  return false
end

function Sidebar:focus_input()
  if self.input_container and self.input_container.winid and api.nvim_win_is_valid(self.input_container.winid) then
    api.nvim_set_current_win(self.input_container.winid)
    api.nvim_feedkeys("i", "n", false)
  end
end

function Sidebar:is_open()
  return self.result_container
    and self.result_container.bufnr
    and api.nvim_buf_is_valid(self.result_container.bufnr)
    and self.result_container.winid
    and api.nvim_win_is_valid(self.result_container.winid)
end

function Sidebar:in_code_win() return self.code.winid == api.nvim_get_current_win() end

---@param opts AskOptions
function Sidebar:toggle(opts)
  local in_visual_mode = Utils.in_visual_mode() and self:in_code_win()
  if self:is_open() and not in_visual_mode then
    self:close()
    return false
  else
    self:open(opts)
    return true
  end
end

---@class AvanteReplacementResult
---@field content string
---@field current_filepath string
---@field is_searching boolean
---@field is_replacing boolean
---@field is_thinking boolean
---@field last_search_tag_start_line integer
---@field last_replace_tag_start_line integer
---@field last_think_tag_start_line integer
---@field last_think_tag_end_line integer

---@param selected_files {path: string, content: string, file_type: string | nil}[]
---@param result_content string
---@param prev_filepath string
---@return AvanteReplacementResult
local function transform_result_content(selected_files, result_content, prev_filepath)
  local transformed_lines = {}

  local result_lines = vim.split(result_content, "\n")

  local is_searching = false
  local is_replacing = false
  local is_thinking = false
  local last_search_tag_start_line = 0
  local last_replace_tag_start_line = 0
  local last_think_tag_start_line = 0
  local last_think_tag_end_line = 0

  local search_start = 0

  local current_filepath

  local i = 1
  while i <= #result_lines do
    local line_content = result_lines[i]
    if line_content:match("<FILEPATH>.+</FILEPATH>") then
      local filepath = line_content:match("<FILEPATH>(.+)</FILEPATH>")
      if filepath then
        current_filepath = filepath
        table.insert(transformed_lines, string.format("Filepath: %s", filepath))
        goto continue
      end
    end
    if line_content == "<SEARCH>" then
      is_searching = true
      local prev_line = result_lines[i - 1]
      if
        prev_line
        and prev_filepath
        and not prev_line:match("Filepath:.+")
        and not prev_line:match("<FILEPATH>.+</FILEPATH>")
      then
        table.insert(transformed_lines, string.format("Filepath: %s", prev_filepath))
      end
      local next_line = result_lines[i + 1]
      if next_line and next_line:match("^%s*```%w+$") then i = i + 1 end
      search_start = i + 1
      last_search_tag_start_line = i
    elseif line_content == "</SEARCH>" then
      is_searching = false

      local search_end = i

      local prev_line = result_lines[i - 1]
      if prev_line and prev_line:match("^%s*```$") then search_end = i - 1 end

      local start_line = 0
      local end_line = 0
      local match_filetype = nil
      local filepath = current_filepath or prev_filepath or ""
      for _, file in ipairs(selected_files) do
        if not Utils.is_same_file(file.path, filepath) then goto continue1 end
        local file_content = vim.split(file.content, "\n")
        if start_line ~= 0 or end_line ~= 0 then break end
        for j = 1, #file_content - (search_end - search_start) + 1 do
          local match = true
          for k = 0, search_end - search_start - 1 do
            if
              Utils.remove_indentation(file_content[j + k]) ~= Utils.remove_indentation(result_lines[search_start + k])
            then
              match = false
              break
            end
          end
          if match then
            start_line = j
            end_line = j + (search_end - search_start) - 1
            match_filetype = file.file_type
            break
          end
        end
        ::continue1::
      end

      -- when the filetype isn't detected, fallback to matching based on filepath.
      -- can happen if the llm tries to edit or create a file outside of it's context.
      if not match_filetype then
        local snippet_file_path = current_filepath or prev_filepath
        local snippet_file_type = vim.filetype.match({ filename = snippet_file_path }) or "unknown"
        match_filetype = snippet_file_type
      end

      local search_start_tag_idx_in_transformed_lines = 0
      for j = 1, #transformed_lines do
        if transformed_lines[j] == "<SEARCH>" then
          search_start_tag_idx_in_transformed_lines = j
          break
        end
      end
      if search_start_tag_idx_in_transformed_lines > 0 then
        transformed_lines = vim.list_slice(transformed_lines, 1, search_start_tag_idx_in_transformed_lines - 1)
      end
      vim.list_extend(transformed_lines, {
        string.format("Replace lines: %d-%d", start_line, end_line),
        string.format("```%s", match_filetype),
      })
      goto continue
    elseif line_content == "<REPLACE>" then
      is_replacing = true
      local next_line = result_lines[i + 1]
      if next_line and next_line:match("^%s*```%w+$") then i = i + 1 end
      last_replace_tag_start_line = i
      goto continue
    elseif line_content == "</REPLACE>" then
      is_replacing = false
      local prev_line = result_lines[i - 1]
      if not (prev_line and prev_line:match("^%s*```$")) then table.insert(transformed_lines, "```") end
      goto continue
    elseif line_content == "<think>" then
      is_thinking = true
      last_think_tag_start_line = i
    elseif line_content == "</think>" then
      is_thinking = false
      last_think_tag_end_line = i
    end
    table.insert(transformed_lines, line_content)
    ::continue::
    i = i + 1
  end

  return {
    current_filepath = current_filepath,
    content = table.concat(transformed_lines, "\n"),
    is_searching = is_searching,
    is_replacing = is_replacing,
    is_thinking = is_thinking,
    last_search_tag_start_line = last_search_tag_start_line,
    last_replace_tag_start_line = last_replace_tag_start_line,
    last_think_tag_start_line = last_think_tag_start_line,
    last_think_tag_end_line = last_think_tag_end_line,
  }
end

local spinner_chars = {
  "⡀",
  "⠄",
  "⠂",
  "⠁",
  "⠈",
  "⠐",
  "⠠",
  "⢀",
  "⣀",
  "⢄",
  "⢂",
  "⢁",
  "⢈",
  "⢐",
  "⢠",
  "⣠",
  "⢤",
  "⢢",
  "⢡",
  "⢨",
  "⢰",
  "⣰",
  "⢴",
  "⢲",
  "⢱",
  "⢸",
  "⣸",
  "⢼",
  "⢺",
  "⢹",
  "⣹",
  "⢽",
  "⢻",
  "⣻",
  "⢿",
  "⣿",
  "⣶",
  "⣤",
  "⣀",
}
local spinner_index = 1

local function get_searching_hint()
  spinner_index = (spinner_index % #spinner_chars) + 1
  local spinner = spinner_chars[spinner_index]
  return "\n" .. spinner .. " Searching..."
end

local thinking_spinner_chars = {
  "🤯",
  "🙄",
}
local thinking_spinner_index = 1

local function get_thinking_spinner()
  thinking_spinner_index = thinking_spinner_index + 1
  if thinking_spinner_index > #thinking_spinner_chars then thinking_spinner_index = 1 end
  local spinner = thinking_spinner_chars[thinking_spinner_index]
  return "\n\n" .. spinner .. " Thinking..."
end

local function get_display_content_suffix(replacement)
  if replacement.is_searching then return get_searching_hint() end
  if replacement.is_thinking then return get_thinking_spinner() end
  return ""
end

---@param replacement AvanteReplacementResult
---@return string
local function generate_display_content(replacement)
  if replacement.is_searching then
    return table.concat(
      vim.list_slice(vim.split(replacement.content, "\n"), 1, replacement.last_search_tag_start_line - 1),
      "\n"
    )
  end
  if replacement.last_think_tag_start_line > 0 then
    local lines = vim.split(replacement.content, "\n")
    local last_think_tag_end_line = replacement.last_think_tag_end_line
    if last_think_tag_end_line == 0 then last_think_tag_end_line = #lines + 1 end
    local thinking_content_lines =
      vim.list_slice(lines, replacement.last_think_tag_start_line + 2, last_think_tag_end_line - 1)
    local formatted_thinking_content_lines = vim
      .iter(thinking_content_lines)
      :map(function(line)
        if Utils.trim_spaces(line) == "" then return line end
        return string.format("  > %s", line)
      end)
      :totable()
    local result_lines =
      vim.list_extend(vim.list_slice(lines, 1, replacement.last_search_tag_start_line), { "🤔 Thought content:" })
    result_lines = vim.list_extend(result_lines, formatted_thinking_content_lines)
    result_lines = vim.list_extend(result_lines, vim.list_slice(lines, last_think_tag_end_line + 1))
    return table.concat(result_lines, "\n")
  end
  return replacement.content
end

---@class AvanteCodeSnippet
---@field range integer[]
---@field content string
---@field lang string
---@field explanation string
---@field start_line_in_response_buf integer
---@field end_line_in_response_buf integer
---@field filepath string

---@param response_content string
---@return table<string, AvanteCodeSnippet[]>
local function extract_code_snippets_map(response_content)
  local snippets = {}
  local current_snippet = {}
  local in_code_block = false
  local lang, start_line, end_line, start_line_in_response_buf
  local explanation = ""

  local lines = vim.split(response_content, "\n")

  for idx, line in ipairs(lines) do
    local _, start_line_str, end_line_str =
      line:match("^%s*(%d*)[%.%)%s]*[Aa]?n?d?%s*[Rr]eplace%s+[Ll]ines:?%s*(%d+)%-(%d+)")
    if start_line_str ~= nil and end_line_str ~= nil then
      start_line = tonumber(start_line_str)
      end_line = tonumber(end_line_str)
    else
      _, start_line_str = line:match("^%s*(%d*)[%.%)%s]*[Aa]?n?d?%s*[Rr]eplace%s+[Ll]ine:?%s*(%d+)")
      if start_line_str ~= nil then
        start_line = tonumber(start_line_str)
        end_line = tonumber(start_line_str)
      else
        start_line_str = line:match("[Aa]fter%s+[Ll]ine:?%s*(%d+)")
        if start_line_str ~= nil then
          start_line = tonumber(start_line_str) + 1
          end_line = tonumber(start_line_str) + 1
        end
      end
    end
    if line:match("^%s*```") then
      if in_code_block then
        if start_line ~= nil and end_line ~= nil then
          local filepath = lines[start_line_in_response_buf - 2]
          if filepath:match("^[Ff]ilepath:") then filepath = filepath:match("^[Ff]ilepath:%s*(.+)") end
          local snippet = {
            range = { start_line, end_line },
            content = table.concat(current_snippet, "\n"),
            lang = lang,
            explanation = explanation,
            start_line_in_response_buf = start_line_in_response_buf,
            end_line_in_response_buf = idx,
            filepath = filepath,
          }
          table.insert(snippets, snippet)
        end
        current_snippet = {}
        start_line, end_line = nil, nil
        explanation = ""
        in_code_block = false
      else
        lang = line:match("^%s*```(%w+)")
        if not lang or lang == "" then lang = "text" end
        in_code_block = true
        start_line_in_response_buf = idx
      end
    elseif in_code_block then
      table.insert(current_snippet, line)
    else
      explanation = explanation .. line .. "\n"
    end
  end

  local snippets_map = {}
  for _, snippet in ipairs(snippets) do
    snippets_map[snippet.filepath] = snippets_map[snippet.filepath] or {}
    table.insert(snippets_map[snippet.filepath], snippet)
  end

  return snippets_map
end

---@param snippets_map table<string, AvanteCodeSnippet[]>
---@return table<string, AvanteCodeSnippet[]>
local function ensure_snippets_no_overlap(snippets_map)
  local new_snippets_map = {}

  for filepath, snippets in pairs(snippets_map) do
    table.sort(snippets, function(a, b) return a.range[1] < b.range[1] end)

    local original_content = ""
    local file_exists = Utils.file.exists(filepath)
    if file_exists then original_content = Utils.file.read_content(filepath) or "" end

    local original_lines = vim.split(original_content, "\n")

    local new_snippets = {}
    local last_end_line = 0
    for _, snippet in ipairs(snippets) do
      if snippet.range[1] > last_end_line then
        table.insert(new_snippets, snippet)
        last_end_line = snippet.range[2]
      elseif not file_exists and #snippets <= 1 then
        -- if the file doesn't exist, and we only have 1 snippet, then we don't have to check for overlaps.
        table.insert(new_snippets, snippet)
        last_end_line = snippet.range[2]
      else
        local snippet_lines = vim.split(snippet.content, "\n")
        -- Trim the overlapping part
        local new_start_line = nil
        for i = snippet.range[1], math.min(snippet.range[2], last_end_line) do
          if
            Utils.remove_indentation(original_lines[i])
            == Utils.remove_indentation(snippet_lines[i - snippet.range[1] + 1])
          then
            new_start_line = i + 1
          else
            break
          end
        end
        if new_start_line ~= nil then
          snippet.content = table.concat(vim.list_slice(snippet_lines, new_start_line - snippet.range[1] + 1), "\n")
          snippet.range[1] = new_start_line
          table.insert(new_snippets, snippet)
          last_end_line = snippet.range[2]
        else
          Utils.error("Failed to ensure snippets no overlap", { once = true, title = "Avante" })
        end
      end
    end
    new_snippets_map[filepath] = new_snippets
  end

  return new_snippets_map
end

local function insert_conflict_contents(bufnr, snippets)
  -- sort snippets by start_line
  table.sort(snippets, function(a, b) return a.range[1] < b.range[1] end)

  local content = table.concat(Utils.get_buf_lines(0, -1, bufnr), "\n")

  local lines = vim.split(content, "\n")

  local offset = 0

  for _, snippet in ipairs(snippets) do
    local start_line, end_line = unpack(snippet.range)
    if start_line > end_line then
      start_line = start_line + 1
      end_line = end_line + 1
    end

    local need_prepend_indentation = false
    local start_line_indentation = ""
    local original_start_line_indentation = Utils.get_indentation(lines[start_line] or "")

    local result = {}
    table.insert(result, "<<<<<<< HEAD")
    for i = start_line, end_line do
      table.insert(result, lines[i])
    end
    table.insert(result, "=======")

    local snippet_lines = vim.split(snippet.content, "\n")

    for idx, line in ipairs(snippet_lines) do
      if idx == 1 then
        start_line_indentation = Utils.get_indentation(line)
        need_prepend_indentation = start_line_indentation ~= original_start_line_indentation
      end
      if need_prepend_indentation then
        if line:sub(1, #start_line_indentation) == start_line_indentation then
          line = line:sub(#start_line_indentation + 1)
        end
        line = original_start_line_indentation .. line
      end
      table.insert(result, line)
    end

    table.insert(result, ">>>>>>> Snippet")

    api.nvim_buf_set_lines(bufnr, offset + start_line - 1, offset + end_line, false, result)
    offset = offset + #snippet_lines + 3
  end
end

---@param codeblocks table<integer, any>
local function is_cursor_in_codeblock(codeblocks)
  local cursor_line, _ = Utils.get_cursor_pos()
  cursor_line = cursor_line - 1 -- transform to 0-indexed line number

  for _, block in ipairs(codeblocks) do
    if cursor_line >= block.start_line and cursor_line <= block.end_line then return block end
  end

  return nil
end

---@class AvanteCodeblock
---@field start_line integer
---@field end_line integer
---@field lang string

---@param buf integer
---@return AvanteCodeblock[]
local function parse_codeblocks(buf)
  local codeblocks = {}
  local in_codeblock = false
  local start_line = nil
  local lang = nil

  local lines = Utils.get_buf_lines(0, -1, buf)
  for i, line in ipairs(lines) do
    if line:match("^%s*```") then
      -- parse language
      local lang_ = line:match("^%s*```(%w+)")
      if in_codeblock and not lang_ then
        table.insert(codeblocks, { start_line = start_line, end_line = i - 1, lang = lang })
        in_codeblock = false
      elseif lang_ and lines[i - 1]:match("^%s*(%d*)[%.%)%s]*[Aa]?n?d?%s*[Rr]eplace%s+[Ll]ines:?%s*(%d+)%-(%d+)") then
        lang = lang_
        start_line = i - 1
        in_codeblock = true
      end
    end
  end

  return codeblocks
end

---@param original_lines string[]
---@param snippet AvanteCodeSnippet
---@return AvanteCodeSnippet[]
local function minimize_snippet(original_lines, snippet)
  local start_line = snippet.range[1]
  local end_line = snippet.range[2]
  local original_snippet_lines = vim.list_slice(original_lines, start_line, end_line)
  local original_snippet_content = table.concat(original_snippet_lines, "\n")
  local snippet_content = snippet.content
  local snippet_lines = vim.split(snippet_content, "\n")
  ---@diagnostic disable-next-line: assign-type-mismatch
  local patch = vim.diff( ---@type integer[][]
    original_snippet_content,
    snippet_content,
    ---@diagnostic disable-next-line: missing-fields
    { algorithm = "histogram", result_type = "indices", ctxlen = vim.o.scrolloff }
  )
  ---@type AvanteCodeSnippet[]
  local new_snippets = {}
  for _, hunk in ipairs(patch) do
    local start_a, count_a, start_b, count_b = unpack(hunk)
    ---@type AvanteCodeSnippet
    local new_snippet = {
      range = { start_line + start_a - 1, start_line + start_a + count_a - 2 },
      content = table.concat(vim.list_slice(snippet_lines, start_b, start_b + count_b - 1), "\n"),
      lang = snippet.lang,
      explanation = snippet.explanation,
      start_line_in_response_buf = snippet.start_line_in_response_buf,
      end_line_in_response_buf = snippet.end_line_in_response_buf,
      filepath = snippet.filepath,
    }
    table.insert(new_snippets, new_snippet)
  end
  return new_snippets
end

---@param snippets_map table<string, AvanteCodeSnippet[]>
---@return table<string, AvanteCodeSnippet[]>
function Sidebar:minimize_snippets(snippets_map)
  local original_lines = api.nvim_buf_get_lines(self.code.bufnr, 0, -1, false)
  local results = {}

  for filepath, snippets in pairs(snippets_map) do
    for _, snippet in ipairs(snippets) do
      local new_snippets = minimize_snippet(original_lines, snippet)
      if new_snippets then
        results[filepath] = results[filepath] or {}
        for _, new_snippet in ipairs(new_snippets) do
          table.insert(results[filepath], new_snippet)
        end
      end
    end
  end

  return results
end

---@param current_cursor boolean
function Sidebar:apply(current_cursor)
  local response, response_start_line = self:get_content_between_separators()
  local all_snippets_map = extract_code_snippets_map(response)
  all_snippets_map = ensure_snippets_no_overlap(all_snippets_map)
  local selected_snippets_map = {}
  if current_cursor then
    if self.result_container and self.result_container.winid then
      local cursor_line = Utils.get_cursor_pos(self.result_container.winid)
      for filepath, snippets in pairs(all_snippets_map) do
        for _, snippet in ipairs(snippets) do
          if
            cursor_line >= snippet.start_line_in_response_buf + response_start_line - 1
            and cursor_line <= snippet.end_line_in_response_buf + response_start_line - 1
          then
            selected_snippets_map[filepath] = { snippet }
            break
          end
        end
      end
    end
  else
    selected_snippets_map = all_snippets_map
  end

  if Config.behaviour.minimize_diff then selected_snippets_map = self:minimize_snippets(selected_snippets_map) end

  vim.defer_fn(function()
    api.nvim_set_current_win(self.code.winid)
    for filepath, snippets in pairs(selected_snippets_map) do
      local bufnr = Utils.get_or_create_buffer_with_filepath(filepath)
      insert_conflict_contents(bufnr, snippets)
      local process = function(winid)
        api.nvim_set_current_win(winid)
        api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
        Diff.add_visited_buffer(bufnr)
        Diff.process(bufnr)
        api.nvim_win_set_cursor(winid, { 1, 0 })
        vim.defer_fn(function()
          Diff.find_next(Config.windows.ask.focus_on_apply)
          vim.cmd("normal! zz")
        end, 100)
      end
      local winid = Utils.get_winid(bufnr)
      if winid then
        process(winid)
      else
        api.nvim_create_autocmd("BufWinEnter", {
          buffer = bufnr,
          once = true,
          callback = function()
            local winid_ = Utils.get_winid(bufnr)
            if winid_ then process(winid_) end
          end,
        })
      end
    end
  end, 10)
end

local buf_options = {
  modifiable = false,
  swapfile = false,
  buftype = "nofile",
}

local base_win_options = {
  winfixbuf = true,
  spell = false,
  signcolumn = "no",
  foldcolumn = "0",
  number = false,
  relativenumber = false,
  winfixwidth = true,
  list = false,
  winhl = "",
  linebreak = true,
  breakindent = true,
  wrap = false,
  cursorline = false,
  fillchars = "eob: ",
  winhighlight = "CursorLine:Normal,CursorColumn:Normal",
  winbar = "",
  statusline = "",
}

function Sidebar:render_header(winid, bufnr, header_text, hl, reverse_hl)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then return end

  if not Config.windows.sidebar_header.enabled then return end

  if not Config.windows.sidebar_header.rounded then header_text = " " .. header_text .. " " end

  local winbar_text = "%#Normal#"

  if Config.windows.sidebar_header.align == "center" then
    winbar_text = winbar_text .. "%="
  elseif Config.windows.sidebar_header.align == "right" then
    winbar_text = winbar_text .. "%="
  end

  if Config.windows.sidebar_header.rounded then
    winbar_text = winbar_text .. "%#" .. reverse_hl .. "#" .. "" .. "%#" .. hl .. "#"
  else
    winbar_text = winbar_text .. "%#" .. hl .. "#"
  end
  winbar_text = winbar_text .. header_text
  if Config.windows.sidebar_header.rounded then winbar_text = winbar_text .. "%#" .. reverse_hl .. "#" end
  winbar_text = winbar_text .. "%#Normal#"
  if Config.windows.sidebar_header.align == "center" then winbar_text = winbar_text .. "%=" end
  api.nvim_set_option_value("winbar", winbar_text, { win = winid })
end

function Sidebar:render_result()
  if
    not self.result_container
    or not self.result_container.bufnr
    or not api.nvim_buf_is_valid(self.result_container.bufnr)
  then
    return
  end
  local header_text = "󰭻 Avante"
  self:render_header(
    self.result_container.winid,
    self.result_container.bufnr,
    header_text,
    Highlights.TITLE,
    Highlights.REVERSED_TITLE
  )
end

---@param ask? boolean
function Sidebar:render_input(ask)
  if ask == nil then ask = true end
  if
    not self.input_container
    or not self.input_container.bufnr
    or not api.nvim_buf_is_valid(self.input_container.bufnr)
  then
    return
  end

  local header_text = string.format(
    "󱜸 %s (" .. Config.mappings.sidebar.switch_windows .. ": switch focus)",
    ask and "Ask" or "Chat with"
  )

  if self.code.selection ~= nil then
    header_text = string.format(
      "󱜸 %s (%d:%d) (<Tab>: switch focus)",
      ask and "Ask" or "Chat with",
      self.code.selection.range.start.lnum,
      self.code.selection.range.finish.lnum
    )
  end

  self:render_header(
    self.input_container.winid,
    self.input_container.bufnr,
    header_text,
    Highlights.THIRD_TITLE,
    Highlights.REVERSED_THIRD_TITLE
  )
end

function Sidebar:render_selected_code()
  if
    not self.selected_code_container
    or not self.selected_code_container.bufnr
    or not api.nvim_buf_is_valid(self.selected_code_container.bufnr)
  then
    return
  end

  local selected_code_lines_count = 0
  local selected_code_max_lines_count = 12

  if self.code.selection ~= nil then
    local selected_code_lines = vim.split(self.code.selection.content, "\n")
    selected_code_lines_count = #selected_code_lines
  end

  local header_text = " Selected Code"
    .. (
      selected_code_lines_count > selected_code_max_lines_count
        and " (Show only the first " .. tostring(selected_code_max_lines_count) .. " lines)"
      or ""
    )

  self:render_header(
    self.selected_code_container.winid,
    self.selected_code_container.bufnr,
    header_text,
    Highlights.SUBTITLE,
    Highlights.REVERSED_SUBTITLE
  )
end

function Sidebar:bind_apply_key()
  if self.result_container then
    vim.keymap.set(
      "n",
      Config.mappings.sidebar.apply_cursor,
      function() self:apply(true) end,
      { buffer = self.result_container.bufnr, noremap = true, silent = true }
    )
  end
end

function Sidebar:unbind_apply_key()
  if self.result_container then
    pcall(vim.keymap.del, "n", Config.mappings.sidebar.apply_cursor, { buffer = self.result_container.bufnr })
  end
end

function Sidebar:bind_sidebar_keys(codeblocks)
  ---@param direction "next" | "prev"
  local function jump_to_codeblock(direction)
    local cursor_line = api.nvim_win_get_cursor(self.result_container.winid)[1]
    ---@type AvanteCodeblock
    local target_block

    if direction == "next" then
      for _, block in ipairs(codeblocks) do
        if block.start_line > cursor_line then
          target_block = block
          break
        end
      end
      if not target_block and #codeblocks > 0 then target_block = codeblocks[1] end
    elseif direction == "prev" then
      for i = #codeblocks, 1, -1 do
        if codeblocks[i].end_line < cursor_line then
          target_block = codeblocks[i]
          break
        end
      end
      if not target_block and #codeblocks > 0 then target_block = codeblocks[#codeblocks] end
    end

    if target_block then
      api.nvim_win_set_cursor(self.result_container.winid, { target_block.start_line + 1, 0 })
      vim.cmd("normal! zz")
    end
  end

  vim.keymap.set(
    "n",
    Config.mappings.sidebar.apply_all,
    function() self:apply(false) end,
    { buffer = self.result_container.bufnr, noremap = true, silent = true }
  )
  vim.keymap.set(
    "n",
    Config.mappings.jump.next,
    function() jump_to_codeblock("next") end,
    { buffer = self.result_container.bufnr, noremap = true, silent = true }
  )
  vim.keymap.set(
    "n",
    Config.mappings.jump.prev,
    function() jump_to_codeblock("prev") end,
    { buffer = self.result_container.bufnr, noremap = true, silent = true }
  )
end

function Sidebar:unbind_sidebar_keys()
  if self.result_container and self.result_container.bufnr and api.nvim_buf_is_valid(self.result_container.bufnr) then
    pcall(vim.keymap.del, "n", Config.mappings.sidebar.apply_all, { buffer = self.result_container.bufnr })
    pcall(vim.keymap.del, "n", Config.mappings.jump.next, { buffer = self.result_container.bufnr })
    pcall(vim.keymap.del, "n", Config.mappings.jump.prev, { buffer = self.result_container.bufnr })
  end
end

---@param opts AskOptions
function Sidebar:on_mount(opts)
  self:refresh_winids()

  -- Add keymap to add current buffer while sidebar is open
  if Config.mappings.files and Config.mappings.files.add_current then
    vim.keymap.set("n", Config.mappings.files.add_current, function()
      if self:is_open() and self.file_selector:add_current_buffer() then
        vim.notify("Added current buffer to file selector", vim.log.levels.DEBUG, { title = "Avante" })
      else
        vim.notify("Failed to add current buffer", vim.log.levels.WARN, { title = "Avante" })
      end
    end, {
      desc = "avante: add current buffer to file selector",
      noremap = true,
      silent = true,
    })
  end

  api.nvim_set_option_value("wrap", Config.windows.wrap, { win = self.result_container.winid })

  local current_apply_extmark_id = nil

  local function show_apply_button(block)
    if current_apply_extmark_id then
      api.nvim_buf_del_extmark(self.result_container.bufnr, CODEBLOCK_KEYBINDING_NAMESPACE, current_apply_extmark_id)
    end

    current_apply_extmark_id =
      api.nvim_buf_set_extmark(self.result_container.bufnr, CODEBLOCK_KEYBINDING_NAMESPACE, block.start_line, -1, {
        virt_text = {
          {
            string.format(
              " [<%s>: apply this, <%s>: apply all] ",
              Config.mappings.sidebar.apply_cursor,
              Config.mappings.sidebar.apply_all
            ),
            "AvanteInlineHint",
          },
        },
        virt_text_pos = "right_align",
        hl_group = "AvanteInlineHint",
        priority = PRIORITY,
      })
  end

  ---@type AvanteCodeblock[]
  local codeblocks = {}

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = self.result_container.bufnr,
    callback = function(ev)
      local block = is_cursor_in_codeblock(codeblocks)

      if block then
        show_apply_button(block)
        self:bind_apply_key()
      else
        api.nvim_buf_clear_namespace(ev.buf, CODEBLOCK_KEYBINDING_NAMESPACE, 0, -1)
        self:unbind_apply_key()
      end
    end,
  })

  api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    buffer = self.result_container.bufnr,
    callback = function(ev)
      codeblocks = parse_codeblocks(ev.buf)
      self:bind_sidebar_keys(codeblocks)
    end,
  })

  api.nvim_create_autocmd("User", {
    pattern = VIEW_BUFFER_UPDATED_PATTERN,
    callback = function()
      if
        not self.result_container
        or not self.result_container.bufnr
        or not api.nvim_buf_is_valid(self.result_container.bufnr)
      then
        return
      end
      codeblocks = parse_codeblocks(self.result_container.bufnr)
      self:bind_sidebar_keys(codeblocks)
    end,
  })

  api.nvim_create_autocmd("BufLeave", {
    buffer = self.result_container.bufnr,
    callback = function() self:unbind_sidebar_keys() end,
  })

  self:render_result()
  self:render_input(opts.ask)
  self:render_selected_code()

  local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })

  if self.selected_code_container ~= nil then
    local selected_code_buf = self.selected_code_container.bufnr
    if selected_code_buf ~= nil then
      if self.code.selection ~= nil then
        Utils.unlock_buf(selected_code_buf)
        local lines = vim.split(self.code.selection.content, "\n")
        api.nvim_buf_set_lines(selected_code_buf, 0, -1, false, lines)
        Utils.lock_buf(selected_code_buf)
      end
      api.nvim_set_option_value("filetype", filetype, { buf = selected_code_buf })
    end
  end

  api.nvim_create_autocmd("BufEnter", {
    group = self.augroup,
    buffer = self.result_container.bufnr,
    callback = function()
      if Config.behaviour.auto_focus_sidebar then
        self:focus()
        if
          self.input_container
          and self.input_container.winid
          and api.nvim_win_is_valid(self.input_container.winid)
        then
          api.nvim_set_current_win(self.input_container.winid)
          vim.defer_fn(function()
            if Config.windows.ask.start_insert then
              Utils.debug("starting insert")
              vim.cmd("startinsert")
            end
          end, 300)
        end
      end
      return true
    end,
  })

  api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    callback = function(args)
      local closed_winid = tonumber(args.match)
      if not self:is_focused_on(closed_winid) then return end
      self:close()
    end,
  })

  for _, comp in pairs(self) do
    if comp and type(comp) == "table" and comp.mount and comp.bufnr and api.nvim_buf_is_valid(comp.bufnr) then
      Utils.mark_as_sidebar_buffer(comp.bufnr)
    end
  end
end

function Sidebar:refresh_winids()
  self.winids = {}
  for key, comp in pairs(self) do
    if comp and type(comp) == "table" and comp.winid and api.nvim_win_is_valid(comp.winid) then
      self.winids[key] = comp.winid
    end
  end

  local winids = {}
  if self.winids.result_container then table.insert(winids, self.winids.result_container) end
  if self.winids.selected_files_container then table.insert(winids, self.winids.selected_files_container) end
  if self.winids.selected_code_container then table.insert(winids, self.winids.selected_code_container) end
  if self.winids.input_container then table.insert(winids, self.winids.input_container) end

  local function switch_windows()
    local current_winid = api.nvim_get_current_win()
    local current_idx = Utils.tbl_indexof(winids, current_winid) or 1
    if current_idx == #winids then
      current_idx = 1
    else
      current_idx = current_idx + 1
    end
    local winid = winids[current_idx]
    if winid and api.nvim_win_is_valid(winid) then pcall(api.nvim_set_current_win, winid) end
  end

  local function reverse_switch_windows()
    local current_winid = api.nvim_get_current_win()
    local current_idx = Utils.tbl_indexof(winids, current_winid) or 1
    if current_idx == 1 then
      current_idx = #winids
    else
      current_idx = current_idx - 1
    end
    local winid = winids[current_idx]
    if winid and api.nvim_win_is_valid(winid) then api.nvim_set_current_win(winid) end
  end

  for _, winid in ipairs(winids) do
    local buf = api.nvim_win_get_buf(winid)
    Utils.safe_keymap_set(
      { "n", "i" },
      Config.mappings.sidebar.switch_windows,
      function() switch_windows() end,
      { buffer = buf, noremap = true, silent = true, nowait = true }
    )
    Utils.safe_keymap_set(
      { "n", "i" },
      Config.mappings.sidebar.reverse_switch_windows,
      function() reverse_switch_windows() end,
      { buffer = buf, noremap = true, silent = true, nowait = true }
    )
  end
end

function Sidebar:resize()
  for _, comp in pairs(self) do
    if comp and type(comp) == "table" and comp.winid and api.nvim_win_is_valid(comp.winid) then
      api.nvim_win_set_width(comp.winid, Config.get_window_width())
    end
  end
  self:render_result()
  self:render_input()
  self:render_selected_code()
  vim.defer_fn(function() vim.cmd("AvanteRefresh") end, 200)
end

--- Initialize the sidebar instance.
--- @return avante.Sidebar The Sidebar instance.
function Sidebar:initialize()
  self.code.winid = api.nvim_get_current_win()
  self.code.bufnr = api.nvim_get_current_buf()
  self.code.selection = Utils.get_visual_selection_and_range()

  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then return self end

  local buf_path = api.nvim_buf_get_name(self.code.bufnr)
  -- if the filepath is outside of the current working directory then we want the absolute path
  local file_path = Utils.file.is_in_cwd(buf_path) and Utils.relative_path(buf_path) or buf_path
  Utils.debug("Sidebar:initialize adding buffer to file selector", buf_path)

  self.file_selector:reset()
  self.file_selector:add_selected_file(file_path)

  return self
end

function Sidebar:is_focused_on_result()
  return self:is_open() and self.result_container and self.result_container.winid == api.nvim_get_current_win()
end

function Sidebar:is_focused_on(winid)
  for _, stored_winid in pairs(self.winids) do
    if stored_winid == winid then return true end
  end
  return false
end

local function delete_last_n_chars(bufnr, n)
  bufnr = bufnr or api.nvim_get_current_buf()

  local line_count = api.nvim_buf_line_count(bufnr)

  while n > 0 and line_count > 0 do
    local last_line = api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]

    local total_chars_in_line = #last_line + 1

    if total_chars_in_line > n then
      local chars_to_keep = total_chars_in_line - n - 1 - 1
      local new_last_line = last_line:sub(1, chars_to_keep)
      if new_last_line == "" then
        api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, {})
        line_count = line_count - 1
      else
        api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { new_last_line })
      end
      n = 0
    else
      n = n - total_chars_in_line
      api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, {})
      line_count = line_count - 1
    end
  end
end

---@param content string concatenated content of the buffer
---@param opts? {focus?: boolean, scroll?: boolean, backspace?: integer, ignore_history?: boolean, callback?: fun(): nil} whether to focus the result view
function Sidebar:update_content(content, opts)
  if not self.result_container or not self.result_container.bufnr then return end
  opts = vim.tbl_deep_extend("force", { focus = false, scroll = true, stream = false, callback = nil }, opts or {})
  if not opts.ignore_history then
    local chat_history = Path.history.load(self.code.bufnr)
    content = self:render_history_content(chat_history) .. "---\n\n" .. content
  end
  if opts.stream then
    local scroll_to_bottom = function()
      local last_line = api.nvim_buf_line_count(self.result_container.bufnr)

      local current_lines = Utils.get_buf_lines(last_line - 1, last_line, self.result_container.bufnr)

      if #current_lines > 0 then
        local last_line_content = current_lines[1]
        local last_col = #last_line_content
        xpcall(
          function() api.nvim_win_set_cursor(self.result_container.winid, { last_line, last_col }) end,
          function(err) return err end
        )
      end
    end

    vim.schedule(function()
      if
        not self.result_container
        or not self.result_container.bufnr
        or not api.nvim_buf_is_valid(self.result_container.bufnr)
      then
        return
      end
      Utils.unlock_buf(self.result_container.bufnr)
      if opts.backspace ~= nil and opts.backspace > 0 then
        delete_last_n_chars(self.result_container.bufnr, opts.backspace)
      end
      scroll_to_bottom()
      local lines = vim.split(content, "\n")
      api.nvim_buf_call(self.result_container.bufnr, function() api.nvim_put(lines, "c", true, true) end)
      Utils.lock_buf(self.result_container.bufnr)
      api.nvim_set_option_value("filetype", "Avante", { buf = self.result_container.bufnr })
      if opts.scroll then scroll_to_bottom() end
      if opts.callback ~= nil then opts.callback() end
    end)
  else
    vim.defer_fn(function()
      if
        not self.result_container
        or not self.result_container.bufnr
        or not api.nvim_buf_is_valid(self.result_container.bufnr)
      then
        return
      end
      local lines = vim.split(content, "\n")
      Utils.unlock_buf(self.result_container.bufnr)
      Utils.update_buffer_content(self.result_container.bufnr, lines)
      Utils.lock_buf(self.result_container.bufnr)
      api.nvim_set_option_value("filetype", "Avante", { buf = self.result_container.bufnr })
      if opts.focus and not self:is_focused_on_result() then
        --- set cursor to bottom of result view
        xpcall(function() api.nvim_set_current_win(self.result_container.winid) end, function(err) return err end)
      end

      if opts.scroll then Utils.buf_scroll_to_end(self.result_container.bufnr) end

      if opts.callback ~= nil then opts.callback() end
    end, 0)
  end
  return self
end

-- Function to get current timestamp
local function get_timestamp() return os.date("%Y-%m-%d %H:%M:%S") end

---@param timestamp string|osdate
---@param provider string
---@param model string
---@param request string
---@param selected_filepaths string[]
---@param selected_code {filetype: string, content: string}?
---@return string
local function render_chat_record_prefix(timestamp, provider, model, request, selected_filepaths, selected_code)
  provider = provider or "unknown"
  model = model or "unknown"
  local res = "- Datetime: " .. timestamp .. "\n\n" .. "- Model: " .. provider .. "/" .. model
  if selected_filepaths ~= nil then
    res = res .. "\n\n- Selected files:"
    for _, path in ipairs(selected_filepaths) do
      res = res .. "\n  - " .. path
    end
  end
  if selected_code ~= nil then
    res = res
      .. "\n\n- Selected code: "
      .. "\n\n```"
      .. selected_code.filetype
      .. "\n"
      .. selected_code.content
      .. "\n```"
  end

  return res .. "\n\n> " .. request:gsub("\n", "\n> "):gsub("([%w-_]+)%b[]", "`%0`") .. "\n\n"
end

local function calculate_config_window_position()
  local position = Config.windows.position
  if position == "smart" then
    -- get editor width
    local editor_width = vim.o.columns
    -- get editor height
    local editor_height = vim.o.lines * 3

    if editor_width > editor_height then
      position = "right"
    else
      position = "bottom"
    end
  end

  return position
end

function Sidebar:get_layout()
  return vim.tbl_contains({ "left", "right" }, calculate_config_window_position()) and "vertical" or "horizontal"
end

---@param history avante.ChatHistoryEntry[]
---@return string
function Sidebar:render_history_content(history)
  local content = ""
  for idx, entry in ipairs(history) do
    if entry.reset_memory then
      content = content .. "***MEMORY RESET***\n\n"
      if idx < #history then content = content .. "---\n\n" end
      goto continue
    end
    local selected_filepaths = entry.selected_filepaths
    if not selected_filepaths and entry.selected_file ~= nil then
      selected_filepaths = { entry.selected_file.filepath }
    end
    local prefix = render_chat_record_prefix(
      entry.timestamp,
      entry.provider,
      entry.model,
      entry.request or "",
      selected_filepaths or {},
      entry.selected_code
    )
    content = content .. prefix
    content = content .. entry.response .. "\n\n"
    if idx < #history then content = content .. "---\n\n" end
    ::continue::
  end
  return content
end

function Sidebar:update_content_with_history(history)
  local content = self:render_history_content(history)
  self:update_content(content, { ignore_history = true })
end

---@return string, integer
function Sidebar:get_content_between_separators()
  local separator = "---"
  local cursor_line, _ = Utils.get_cursor_pos()
  local lines = Utils.get_buf_lines(0, -1, self.result_container.bufnr)
  local start_line, end_line

  for i = cursor_line, 1, -1 do
    if lines[i] == separator then
      start_line = i + 1
      break
    end
  end
  start_line = start_line or 1

  for i = cursor_line, #lines do
    if lines[i] == separator then
      end_line = i - 1
      break
    end
  end
  end_line = end_line or #lines

  if lines[cursor_line] == separator then
    if cursor_line > 1 and lines[cursor_line - 1] ~= separator then
      end_line = cursor_line - 1
    elseif cursor_line < #lines and lines[cursor_line + 1] ~= separator then
      start_line = cursor_line + 1
    end
  end

  local content = table.concat(vim.list_slice(lines, start_line, end_line), "\n")
  return content, start_line
end

function Sidebar:clear_history(args, cb)
  local chat_history = Path.history.load(self.code.bufnr)
  if next(chat_history) ~= nil then
    chat_history = {}
    Path.history.save(self.code.bufnr, chat_history)
    self:update_content(
      "Chat history cleared",
      { focus = false, scroll = false, callback = function() self:focus_input() end }
    )
    if cb then cb(args) end
  else
    self:update_content(
      "Chat history is already empty",
      { focus = false, scroll = false, callback = function() self:focus_input() end }
    )
  end
end

function Sidebar:reset_memory(args, cb)
  local chat_history = Path.history.load(self.code.bufnr)
  if next(chat_history) ~= nil then
    table.insert(chat_history, {
      timestamp = get_timestamp(),
      provider = Config.provider,
      model = Config.get_provider(Config.provider).model,
      request = "",
      response = "",
      original_response = "",
      selected_file = nil,
      selected_code = nil,
      reset_memory = true,
    })
    Path.history.save(self.code.bufnr, chat_history)
    local history_content = self:render_history_content(chat_history)
    self:update_content(history_content, {
      focus = false,
      scroll = true,
      callback = function() self:focus_input() end,
    })
    if cb then cb(args) end
  else
    self:update_content(
      "Chat history is already empty",
      { focus = false, scroll = false, callback = function() self:focus_input() end }
    )
  end
end

---@alias AvanteSlashCommandType "clear" | "help" | "lines" | "reset"
---@alias AvanteSlashCommandCallback fun(args: string, cb?: fun(args: string): nil): nil
---@alias AvanteSlashCommand {description: string, command: AvanteSlashCommandType, details: string, shorthelp?: string, callback?: AvanteSlashCommandCallback}
---@return AvanteSlashCommand[]
function Sidebar:get_commands()
  ---@param items_ {command: string, description: string, shorthelp?: string}[]
  ---@return string
  local function get_help_text(items_)
    local help_text = ""
    for _, item in ipairs(items_) do
      help_text = help_text .. "- " .. item.command .. ": " .. (item.shorthelp or item.description) .. "\n"
    end
    return help_text
  end

  ---@type AvanteSlashCommand[]
  local items = {
    { description = "Show help message", command = "help" },
    { description = "Clear chat history", command = "clear" },
    { description = "Reset memory", command = "reset" },
    {
      shorthelp = "Ask a question about specific lines",
      description = "/lines <start>-<end> <question>",
      command = "lines",
    },
  }

  ---@type {[AvanteSlashCommandType]: AvanteSlashCommandCallback}
  local cbs = {
    help = function(args, cb)
      local help_text = get_help_text(items)
      self:update_content(help_text, { focus = false, scroll = false })
      if cb then cb(args) end
    end,
    clear = function(args, cb) self:clear_history(args, cb) end,
    reset = function(args, cb) self:reset_memory(args, cb) end,
    lines = function(args, cb)
      if cb then cb(args) end
    end,
  }

  return vim
    .iter(items)
    :map(
      ---@param item AvanteSlashCommand
      function(item)
        return {
          command = item.command,
          description = item.description,
          callback = cbs[item.command],
          details = item.shorthelp and table.concat({ item.shorthelp, item.description }, "\n") or item.description,
        }
      end
    )
    :totable()
end

function Sidebar:create_selected_code_container()
  if self.selected_code_container ~= nil then
    self.selected_code_container:unmount()
    self.selected_code_container = nil
  end

  local selected_code_size = self:get_selected_code_size()

  if self.code.selection ~= nil then
    self.selected_code_container = Split({
      enter = false,
      relative = {
        type = "win",
        winid = self.input_container.winid,
      },
      buf_options = buf_options,
      size = {
        height = selected_code_size + 3,
      },
      position = "top",
    })
    self.selected_code_container:mount()
    if self:get_layout() == "horizontal" then
      api.nvim_win_set_height(
        self.result_container.winid,
        api.nvim_win_get_height(self.result_container.winid) - selected_code_size - 3
      )
    end
  end
end

local generating_text = "**Generating response ...**\n"

local hint_window = nil

---@param opts AskOptions
function Sidebar:create_input_container(opts)
  if self.input_container then self.input_container:unmount() end

  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then return end

  local chat_history = Path.history.load(self.code.bufnr)

  ---@param request string
  ---@return GeneratePromptsOptions
  local function get_generate_prompts_options(request)
    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })

    local selected_code_content = nil
    if self.code.selection ~= nil then selected_code_content = self.code.selection.content end

    local mentions = Utils.extract_mentions(request)
    request = mentions.new_content

    local file_ext = api.nvim_buf_get_name(self.code.bufnr):match("^.+%.(.+)$")

    local project_context = mentions.enable_project_context and RepoMap.get_repo_map(file_ext) or nil

    local selected_files_contents = self.file_selector:get_selected_files_contents()

    local diagnostics = nil
    if mentions.enable_diagnostics then
      if self.code ~= nil and self.code.bufnr ~= nil and self.code.selection ~= nil then
        diagnostics = Utils.get_current_selection_diagnostics(self.code.bufnr, self.code.selection)
      else
        diagnostics = Utils.get_diagnostics(self.code.bufnr)
      end
    end

    local history_messages = {}
    for i = #chat_history, 1, -1 do
      local entry = chat_history[i]
      if entry.reset_memory then break end
      if
        entry.request == nil
        or entry.original_response == nil
        or entry.request == ""
        or entry.original_response == ""
      then
        break
      end
      table.insert(history_messages, 1, { role = "assistant", content = entry.original_response })
      local user_content = ""
      if entry.selected_file ~= nil then
        user_content = user_content .. "SELECTED FILE: " .. entry.selected_file.filepath .. "\n\n"
      end
      if entry.selected_code ~= nil then
        user_content = user_content
          .. "SELECTED CODE:\n\n```"
          .. entry.selected_code.filetype
          .. "\n"
          .. entry.selected_code.content
          .. "\n```\n\n"
      end
      user_content = user_content .. "USER PROMPT:\n\n" .. entry.request
      table.insert(history_messages, 1, { role = "user", content = user_content })
    end

    return {
      ask = opts.ask or true,
      project_context = vim.json.encode(project_context),
      selected_files = selected_files_contents,
      diagnostics = vim.json.encode(diagnostics),
      history_messages = history_messages,
      code_lang = filetype,
      selected_code = selected_code_content,
      instructions = request,
      mode = "planning",
    }
  end

  ---@param request string
  local function handle_submit(request)
    local model = Config.has_provider(Config.provider) and Config.get_provider(Config.provider).model or "default"

    local timestamp = get_timestamp()

    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })

    local selected_filepaths = self.file_selector:get_selected_filepaths()

    local selected_code = nil
    if self.code.selection ~= nil then
      selected_code = {
        filetype = filetype,
        content = self.code.selection.content,
      }
    end

    local content_prefix =
      render_chat_record_prefix(timestamp, Config.provider, model, request, selected_filepaths, selected_code)

    --- HACK: we need to set focus to true and scroll to false to
    --- prevent the cursor from jumping to the bottom of the
    --- buffer at the beginning
    self:update_content("", { focus = true, scroll = false })
    self:update_content(content_prefix .. generating_text)

    if request:sub(1, 1) == "/" then
      local command, args = request:match("^/(%S+)%s*(.*)")
      if command == nil then
        self:update_content("Invalid command", { focus = false, scroll = false })
        return
      end
      local cmds = self:get_commands()
      ---@type AvanteSlashCommand
      local cmd = vim.iter(cmds):filter(function(_) return _.command == command end):totable()[1]
      if cmd then
        if command == "lines" then
          cmd.callback(args, function(args_)
            local _, _, question = args_:match("(%d+)-(%d+)%s+(.*)")
            request = question
          end)
        else
          cmd.callback(args)
          return
        end
      else
        self:update_content("Unknown command: " .. command, { focus = false, scroll = false })
        return
      end
    end

    local original_response = ""
    local transformed_response = ""
    local displayed_response = ""
    local current_path = ""
    local prev_is_thinking = false

    local is_first_chunk = true
    local scroll = true

    ---stop scroll when user presses j/k keys
    local function on_j()
      scroll = false
      ---perform scroll
      vim.cmd("normal! j")
    end

    local function on_k()
      scroll = false
      ---perform scroll
      vim.cmd("normal! k")
    end

    local function on_G()
      scroll = true
      ---perform scroll
      vim.cmd("normal! G")
    end

    vim.keymap.set("n", "j", on_j, { buffer = self.result_container.bufnr })
    vim.keymap.set("n", "k", on_k, { buffer = self.result_container.bufnr })
    vim.keymap.set("n", "G", on_G, { buffer = self.result_container.bufnr })

    ---@type AvanteChunkParser
    local on_chunk = function(chunk)
      original_response = original_response .. chunk

      local selected_files = self.file_selector:get_selected_files_contents()

      local transformed =
        transform_result_content(selected_files, transformed_response .. chunk, current_path, prev_is_thinking)
      transformed_response = transformed.content
      prev_is_thinking = transformed.is_thinking
      if transformed.current_filepath and transformed.current_filepath ~= "" then
        current_path = transformed.current_filepath
      end
      local cur_displayed_response = generate_display_content(transformed)
      if is_first_chunk then
        is_first_chunk = false
        self:update_content(content_prefix .. chunk, { scroll = scroll })
        return
      end
      local suffix = get_display_content_suffix(transformed)
      self:update_content(content_prefix .. cur_displayed_response .. suffix, { scroll = scroll })
      vim.schedule(function() vim.cmd("redraw") end)
      displayed_response = cur_displayed_response
    end

    ---@type AvanteCompleteParser
    local on_complete = function(err)
      pcall(function()
        ---remove keymaps
        vim.keymap.del("n", "j", { buffer = self.result_container.bufnr })
        vim.keymap.del("n", "k", { buffer = self.result_container.bufnr })
        vim.keymap.del("n", "G", { buffer = self.result_container.bufnr })
      end)

      if err ~= nil then
        self:update_content(
          content_prefix .. displayed_response .. "\n\nError: " .. vim.inspect(err),
          { scroll = scroll }
        )
        return
      end

      self:update_content(
        content_prefix
          .. displayed_response
          .. "\n\n**Generation complete!** Please review the code suggestions above.\n",
        {
          scroll = scroll,
          callback = function() api.nvim_exec_autocmds("User", { pattern = VIEW_BUFFER_UPDATED_PATTERN }) end,
        }
      )

      vim.defer_fn(function()
        if
          self.result_container
          and self.result_container.winid
          and api.nvim_win_is_valid(self.result_container.winid)
          and Config.behaviour.jump_result_buffer_on_finish
        then
          api.nvim_set_current_win(self.result_container.winid)
        end
        if Config.behaviour.auto_apply_diff_after_generation then self:apply(false) end
      end, 0)

      -- Save chat history
      table.insert(chat_history or {}, {
        timestamp = timestamp,
        provider = Config.provider,
        model = model,
        request = request,
        response = displayed_response,
        original_response = original_response,
        selected_filepaths = selected_filepaths,
        selected_code = selected_code,
      })
      Path.history.save(self.code.bufnr, chat_history)
    end

    local generate_prompts_options = get_generate_prompts_options(request)
    ---@type StreamOptions
    ---@diagnostic disable-next-line: assign-type-mismatch
    local stream_options = vim.tbl_deep_extend("force", generate_prompts_options, {
      on_chunk = on_chunk,
      on_complete = on_complete,
    })

    Llm.stream(stream_options)
  end

  local get_position = function()
    if self:get_layout() == "vertical" then return "bottom" end
    return "right"
  end

  local get_size = function()
    if self:get_layout() == "vertical" then return {
      height = Config.windows.input.height,
    } end

    local selected_code_size = self:get_selected_code_size()

    return {
      width = "40%",
      height = math.max(1, api.nvim_win_get_height(self.result_container.winid) - selected_code_size),
    }
  end

  self.input_container = Split({
    enter = false,
    relative = {
      type = "win",
      winid = self.result_container.winid,
    },
    buf_options = {
      swapfile = false,
      buftype = "nofile",
    },
    win_options = vim.tbl_deep_extend("force", base_win_options, { signcolumn = "yes", wrap = Config.windows.wrap }),
    position = get_position(),
    size = get_size(),
  })

  local function on_submit()
    if not vim.g.avante_login then
      Utils.warn("Sending message to fast!, API key is not yet set", { title = "Avante" })
      return
    end
    if
      not self.input_container
      or not self.input_container.bufnr
      or not api.nvim_buf_is_valid(self.input_container.bufnr)
    then
      return
    end
    local lines = api.nvim_buf_get_lines(self.input_container.bufnr, 0, -1, false)
    local request = table.concat(lines, "\n")
    if request == "" then return end
    api.nvim_buf_set_lines(self.input_container.bufnr, 0, -1, false, {})
    handle_submit(request)
  end

  self.input_container:mount()

  local function place_sign_at_first_line(bufnr)
    local group = "avante_input_prompt_group"

    fn.sign_unplace(group, { buffer = bufnr })

    fn.sign_place(0, group, "AvanteInputPromptSign", bufnr, { lnum = 1 })
  end

  place_sign_at_first_line(self.input_container.bufnr)

  if Utils.in_visual_mode() then
    -- Exit visual mode
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
  end

  self.input_container:map("n", Config.mappings.submit.normal, on_submit)
  self.input_container:map("i", Config.mappings.submit.insert, on_submit)

  api.nvim_set_option_value("filetype", "AvanteInput", { buf = self.input_container.bufnr })

  -- Setup completion
  api.nvim_create_autocmd("InsertEnter", {
    group = self.augroup,
    buffer = self.input_container.bufnr,
    once = true,
    desc = "Setup the completion of helpers in the input buffer",
    callback = function()
      local has_cmp, cmp = pcall(require, "cmp")
      if has_cmp then
        local mentions = Utils.get_mentions()

        table.insert(mentions, {
          description = "file",
          command = "file",
          details = "add files...",
          callback = function() self.file_selector:open() end,
        })

        table.insert(mentions, {
          description = "quickfix",
          command = "quickfix",
          details = "add files in quickfix list to chat context",
          callback = function() self.file_selector:add_quickfix_files() end,
        })

        cmp.register_source(
          "avante_commands",
          require("cmp_avante.commands"):new(self:get_commands(), self.input_container.bufnr)
        )
        cmp.register_source(
          "avante_mentions",
          require("cmp_avante.mentions"):new(mentions, self.input_container.bufnr)
        )

        cmp.setup.buffer({
          enabled = true,
          sources = {
            { name = "avante_commands" },
            { name = "avante_mentions" },
            { name = "avante_files" },
          },
        })
      end
    end,
  })

  -- Close the floating window
  local function close_hint()
    if hint_window and api.nvim_win_is_valid(hint_window) then
      api.nvim_win_close(hint_window, true)
      hint_window = nil
    end
  end

  local function get_float_window_row()
    local win_height = api.nvim_win_get_height(self.input_container.winid)
    local winline = Utils.winline(self.input_container.winid)
    if winline >= win_height - 1 then return 0 end
    return winline
  end

  -- Create a floating window as a hint
  local function show_hint()
    close_hint() -- Close the existing hint window

    local input_value = table.concat(api.nvim_buf_get_lines(self.input_container.bufnr, 0, -1, false), "\n")

    local generate_prompts_options = get_generate_prompts_options(input_value)
    local tokens = Llm.calculate_tokens(generate_prompts_options)

    local hint_text = "Tokens: "
      .. tostring(tokens)
      .. "; "
      .. (fn.mode() ~= "i" and Config.mappings.submit.normal or Config.mappings.submit.insert)
      .. ": submit"

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, { hint_text })
    api.nvim_buf_add_highlight(buf, 0, "AvantePopupHint", 0, 0, -1)

    -- Get the current window size
    local win_width = api.nvim_win_get_width(self.input_container.winid)
    local width = #hint_text

    -- Set the floating window options
    local win_opts = {
      relative = "win",
      win = self.input_container.winid,
      width = width,
      height = 1,
      row = get_float_window_row(),
      col = math.max(win_width - width, 0), -- Display in the bottom right corner
      style = "minimal",
      border = "none",
      focusable = false,
      zindex = 100,
    }

    -- Create the floating window
    hint_window = api.nvim_open_win(buf, false, win_opts)
  end

  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "VimResized" }, {
    group = self.augroup,
    buffer = self.input_container.bufnr,
    callback = function()
      show_hint()
      place_sign_at_first_line(self.input_container.bufnr)
    end,
  })

  api.nvim_create_autocmd("QuitPre", {
    group = self.augroup,
    buffer = self.input_container.bufnr,
    callback = function() close_hint() end,
  })

  -- Show hint in insert mode
  api.nvim_create_autocmd("ModeChanged", {
    group = self.augroup,
    pattern = "*:i",
    callback = function()
      local cur_buf = api.nvim_get_current_buf()
      if self.input_container and cur_buf == self.input_container.bufnr then show_hint() end
    end,
  })

  -- Close hint when exiting insert mode
  api.nvim_create_autocmd("ModeChanged", {
    group = self.augroup,
    pattern = "i:*",
    callback = function()
      local cur_buf = api.nvim_get_current_buf()
      if self.input_container and cur_buf == self.input_container.bufnr then show_hint() end
    end,
  })

  api.nvim_create_autocmd("WinEnter", {
    callback = function()
      local cur_win = api.nvim_get_current_win()
      if self.input_container and cur_win == self.input_container.winid then
        show_hint()
      else
        close_hint()
      end
    end,
  })

  api.nvim_create_autocmd("User", {
    group = self.augroup,
    pattern = "AvanteInputSubmitted",
    callback = function(ev)
      if ev.data and ev.data.request then handle_submit(ev.data.request) end
    end,
  })

  self:refresh_winids()
end

function Sidebar:get_selected_code_size()
  local selected_code_max_lines_count = 10

  local selected_code_size = 0

  if self.code.selection ~= nil then
    local selected_code_lines = vim.split(self.code.selection.content, "\n")
    local selected_code_lines_count = #selected_code_lines
    selected_code_size = math.min(selected_code_lines_count, selected_code_max_lines_count)
  end

  return selected_code_size
end

---@param opts AskOptions
function Sidebar:render(opts)
  local chat_history = Path.history.load(self.code.bufnr)

  local get_position = function()
    return (opts and opts.win and opts.win.position) and opts.win.position or calculate_config_window_position()
  end

  local get_height = function()
    local selected_code_size = self:get_selected_code_size()

    if self:get_layout() == "horizontal" then return math.floor(Config.windows.height / 100 * vim.o.lines) end

    return math.max(1, api.nvim_win_get_height(self.code.winid) - selected_code_size - 3 - 8)
  end

  local get_width = function()
    if self:get_layout() == "vertical" then return math.floor(Config.windows.width / 100 * vim.o.columns) end

    return math.max(1, api.nvim_win_get_width(self.code.winid))
  end

  self.result_container = Split({
    enter = false,
    relative = "editor",
    position = get_position(),
    buf_options = vim.tbl_deep_extend("force", buf_options, {
      modifiable = false,
      swapfile = false,
      buftype = "nofile",
      bufhidden = "wipe",
      filetype = "Avante",
    }),
    win_options = vim.tbl_deep_extend("force", base_win_options, {
      wrap = Config.windows.wrap,
    }),
    size = {
      width = get_width(),
      height = get_height(),
    },
  })

  self.result_container:mount()

  self.augroup = api.nvim_create_augroup("avante_sidebar_" .. self.id .. self.result_container.winid, { clear = true })

  self.result_container:on(event.BufWinEnter, function()
    xpcall(function() api.nvim_buf_set_name(self.result_container.bufnr, RESULT_BUF_NAME) end, function(_) end)
  end)

  self.result_container:map("n", Config.mappings.sidebar.close, function()
    Llm.cancel_inflight_request()
    self:close()
  end)

  self:create_input_container(opts)

  self:create_selected_files_container()

  self:update_content_with_history(chat_history)

  -- reset states when buffer is closed
  api.nvim_buf_attach(self.code.bufnr, false, {
    on_detach = function(_, _)
      if self and self.reset then self:reset() end
    end,
  })

  self:create_selected_code_container()

  self:on_mount(opts)

  return self
end

function Sidebar:create_selected_files_container()
  if self.selected_files_container then self.selected_files_container:unmount() end

  local selected_filepaths = self.file_selector:get_selected_filepaths()
  if #selected_filepaths == 0 then
    self.file_selector:off("update")
    self.file_selector:on("update", function() self:create_selected_files_container() end)
    return
  end

  self.selected_files_container = Split({
    enter = false,
    relative = {
      type = "win",
      winid = self.input_container.winid,
    },
    buf_options = vim.tbl_deep_extend("force", buf_options, {
      modifiable = false,
      swapfile = false,
      buftype = "nofile",
      bufhidden = "wipe",
      filetype = "AvanteSelectedFiles",
    }),
    win_options = vim.tbl_deep_extend("force", base_win_options, {
      wrap = Config.windows.wrap,
    }),
    position = "top",
    size = {
      width = "40%",
      height = 2,
    },
  })

  self.selected_files_container:mount()

  local render = function()
    local selected_filepaths_ = self.file_selector:get_selected_filepaths()

    if #selected_filepaths_ == 0 then
      self.selected_files_container:unmount()
      return
    end

    local selected_filepaths_with_icon = {}
    for _, filepath in ipairs(selected_filepaths_) do
      local icon = Utils.file.get_file_icon(filepath)
      table.insert(selected_filepaths_with_icon, string.format("%s %s", icon, filepath))
    end

    local selected_files_buf = api.nvim_win_get_buf(self.selected_files_container.winid)
    Utils.unlock_buf(selected_files_buf)
    api.nvim_buf_set_lines(selected_files_buf, 0, -1, true, selected_filepaths_with_icon)
    Utils.lock_buf(selected_files_buf)
    local win_height = math.min(vim.o.lines - 2, #selected_filepaths_ + 1)
    api.nvim_win_set_height(self.selected_files_container.winid, win_height)
    self:render_header(
      self.selected_files_container.winid,
      selected_files_buf,
      " Selected Files",
      Highlights.SUBTITLE,
      Highlights.REVERSED_SUBTITLE
    )
  end

  self.file_selector:on("update", render)

  local remove_file = function(line_number)
    if self.file_selector:remove_selected_filepaths(line_number) then render() end
  end

  -- Function to show hint
  local function show_hint()
    local cursor_pos = api.nvim_win_get_cursor(self.selected_files_container.winid)
    local line_number = cursor_pos[1]
    local col_number = cursor_pos[2]

    local selected_filepaths_ = self.file_selector:get_selected_filepaths()
    local hint
    if #selected_filepaths_ == 0 then
      hint = string.format(" [%s: add] ", Config.mappings.sidebar.add_file)
    else
      hint =
        string.format(" [%s: delete, %s: add] ", Config.mappings.sidebar.remove_file, Config.mappings.sidebar.add_file)
    end

    api.nvim_buf_clear_namespace(self.selected_files_container.bufnr, SELECTED_FILES_HINT_NAMESPACE, 0, -1)

    api.nvim_buf_set_extmark(
      self.selected_files_container.bufnr,
      SELECTED_FILES_HINT_NAMESPACE,
      line_number - 1,
      col_number,
      {
        virt_text = { { hint, "AvanteInlineHint" } },
        virt_text_pos = "right_align",
        hl_group = "AvanteInlineHint",
        priority = PRIORITY,
      }
    )
  end

  -- Set up keybinding to remove files
  self.selected_files_container:map("n", Config.mappings.sidebar.remove_file, function()
    local line_number = api.nvim_win_get_cursor(self.selected_files_container.winid)[1]
    remove_file(line_number)
  end, { noremap = true, silent = true })

  self.selected_files_container:map(
    "n",
    Config.mappings.sidebar.add_file,
    function() self.file_selector:open() end,
    { noremap = true, silent = true }
  )

  -- Set up autocmd to show hint on cursor move
  self.selected_files_container:on({ event.CursorMoved }, show_hint, {})

  -- Clear hint when leaving the window
  self.selected_files_container:on(
    event.BufLeave,
    function() api.nvim_buf_clear_namespace(self.selected_files_container.bufnr, SELECTED_FILES_HINT_NAMESPACE, 0, -1) end,
    {}
  )

  render()
end

return Sidebar
