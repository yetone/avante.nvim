local api = vim.api
local fn = vim.fn

local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local PPath = require("plenary.path")
local Provider = require("avante.providers")
local Path = require("avante.path")
local Config = require("avante.config")
local Diff = require("avante.diff")
local Llm = require("avante.llm")
local Utils = require("avante.utils")
local Highlights = require("avante.highlights")
local RepoMap = require("avante.repo_map")
local FileSelector = require("avante.file_selector")
local LLMTools = require("avante.llm_tools")

local RESULT_BUF_NAME = "AVANTE_RESULT"
local VIEW_BUFFER_UPDATED_PATTERN = "AvanteViewBufferUpdated"
local CODEBLOCK_KEYBINDING_NAMESPACE = api.nvim_create_namespace("AVANTE_CODEBLOCK_KEYBINDING")
local USER_REQUEST_BLOCK_KEYBINDING_NAMESPACE = api.nvim_create_namespace("AVANTE_USER_REQUEST_BLOCK_KEYBINDING")
local SELECTED_FILES_HINT_NAMESPACE = api.nvim_create_namespace("AVANTE_SELECTED_FILES_HINT")
local PRIORITY = (vim.hl or vim.highlight).priorities.user

local RESP_SEPARATOR = "-------"

---@class avante.Sidebar
local Sidebar = {}
Sidebar.__index = Sidebar

---@class avante.CodeState
---@field winid integer
---@field bufnr integer
---@field selection avante.SelectionResult | nil
---@field old_winhl string | nil

---@class avante.Sidebar
---@field id integer
---@field augroup integer
---@field code avante.CodeState
---@field winids table<"result_container" | "selected_code_container" | "selected_files_container" | "input_container", integer>
---@field result_container NuiSplit | nil
---@field selected_code_container NuiSplit | nil
---@field selected_files_container NuiSplit | nil
---@field input_container NuiSplit | nil
---@field file_selector FileSelector
---@field chat_history avante.ChatHistory | nil

---@param id integer the tabpage id retrieved from api.nvim_get_current_tabpage()
function Sidebar:new(id)
  return setmetatable({
    id = id,
    code = { bufnr = 0, winid = 0, selection = nil, old_winhl = nil },
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
    is_generating = false,
    chat_history = nil,
  }, Sidebar)
end

function Sidebar:delete_autocmds()
  if self.augroup then api.nvim_del_augroup_by_id(self.augroup) end
  self.augroup = nil
end

function Sidebar:reset()
  -- clean up event handlers
  if self.augroup then
    api.nvim_del_augroup_by_id(self.augroup)
    self.augroup = nil
  end

  -- clean up keymaps
  self:unbind_apply_key()
  self:unbind_sidebar_keys()

  -- clean up file selector events
  if self.file_selector then self.file_selector:off("update") end

  if self.result_container then self.result_container:unmount() end
  if self.selected_code_container then self.selected_code_container:unmount() end
  if self.selected_files_container then self.selected_files_container:unmount() end
  if self.input_container then self.input_container:unmount() end

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

  return self
end

function Sidebar:setup_colors()
  self:set_code_winhl()
  vim.api.nvim_create_autocmd("WinNew", {
    group = self.augroup,
    callback = function()
      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if not vim.api.nvim_win_is_valid(winid) or self:is_sidebar_winid(winid) then goto continue end
        local winhl = vim.wo[winid].winhl
        if
          winhl:find(Highlights.AVANTE_SIDEBAR_WIN_SEPARATOR)
          and not Utils.should_hidden_border(self.code.winid, winid)
        then
          vim.wo[winid].winhl = self.code.old_winhl or ""
        end
        ::continue::
      end
      self:set_code_winhl()
    end,
  })
end

function Sidebar:set_code_winhl()
  if Utils.should_hidden_border(self.code.winid, self.winids.result_container) then
    Utils.debug("setting winhl")
    local old_winhl = vim.wo[self.code.winid].winhl
    if self.code.old_winhl == nil then
      self.code.old_winhl = old_winhl
    else
      old_winhl = self.code.old_winhl
    end
    local pieces = vim.split(old_winhl or "", ",")
    local new_pieces = {}
    for _, piece in ipairs(pieces) do
      if not piece:find("WinSeparator:") and piece ~= "" then table.insert(new_pieces, piece) end
    end
    table.insert(new_pieces, "WinSeparator:" .. Highlights.AVANTE_SIDEBAR_WIN_SEPARATOR)
    local new_winhl = table.concat(new_pieces, ",")
    vim.wo[self.code.winid].winhl = new_winhl
  end
end

function Sidebar:recover_code_winhl()
  if self.code.old_winhl ~= nil then
    vim.wo[self.code.winid].winhl = self.code.old_winhl
    self.code.old_winhl = nil
  end
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

  self:recover_code_winhl()
end

function Sidebar:shutdown()
  Llm.cancel_inflight_request()
  self:close()
  vim.cmd("noautocmd stopinsert")
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
  if Utils.is_valid_container(self.input_container, true) then api.nvim_set_current_win(self.input_container.winid) end
end

function Sidebar:is_open() return Utils.is_valid_container(self.result_container, true) end

function Sidebar:in_code_win() return self.code.winid == api.nvim_get_current_win() end

---@param opts AskOptions
function Sidebar:toggle(opts)
  local in_visual_mode = Utils.in_visual_mode() and self:in_code_win()
  if self:is_open() and not in_visual_mode then
    self:close()
    return false
  else
    ---@cast opts SidebarOpenOptions
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
---@field waiting_for_breakline boolean
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

  local waiting_for_breakline = false
  local i = 1
  while true do
    if i > #result_lines then break end
    local line_content = result_lines[i]
    local matched_filepath =
      line_content:match("<[Ff][Ii][Ll][Ee][Pp][Aa][Tt][Hh]>(.+)</[Ff][Ii][Ll][Ee][Pp][Aa][Tt][Hh]>")
    if matched_filepath then
      if i > 1 then
        local prev_line = result_lines[i - 1]
        if prev_line and prev_line:match("^%s*```%w+$") then
          transformed_lines = vim.list_slice(transformed_lines, 1, #transformed_lines - 1)
        end
      end
      current_filepath = matched_filepath
      table.insert(transformed_lines, string.format("Filepath: %s", matched_filepath))
      goto continue
    end
    if line_content:match("^%s*<[Ss][Ee][Aa][Rr][Cc][Hh]>") then
      is_searching = true

      if not line_content:match("^%s*<[Ss][Ee][Aa][Rr][Cc][Hh]>%s*$") then
        local search_start_line = line_content:match("<[Ss][Ee][Aa][Rr][Cc][Hh]>(.+)$")
        line_content = "<SEARCH>"
        result_lines[i] = line_content
        if search_start_line and search_start_line ~= "" then table.insert(result_lines, i + 1, search_start_line) end
      end
      line_content = "<SEARCH>"

      local prev_line = result_lines[i - 1]
      if
        prev_line
        and prev_filepath
        and not prev_line:match("Filepath:.+")
        and not prev_line:match("<[Ff][Ii][Ll][Ee][Pp][Aa][Tt][Hh]>.+</[Ff][Ii][Ll][Ee][Pp][Aa][Tt][Hh]>")
      then
        table.insert(transformed_lines, string.format("Filepath: %s", prev_filepath))
      end
      local next_line = result_lines[i + 1]
      if next_line and next_line:match("^%s*```%w+$") then i = i + 1 end
      search_start = i + 1
      last_search_tag_start_line = i
    elseif line_content:match("</[Ss][Ee][Aa][Rr][Cc][Hh]>%s*$") then
      if is_replacing then
        result_lines[i] = line_content:gsub("</[Ss][Ee][Aa][Rr][Cc][Hh]>", "</REPLACE>")
        goto continue_without_increment
      end

      -- Handle case where </SEARCH> is a suffix
      if not line_content:match("^%s*</[Ss][Ee][Aa][Rr][Cc][Hh]>%s*$") then
        local search_end_line = line_content:match("^(.+)</[Ss][Ee][Aa][Rr][Cc][Hh]>")
        line_content = "</SEARCH>"
        result_lines[i] = line_content
        if search_end_line and search_end_line ~= "" then
          table.insert(result_lines, i, search_end_line)
          goto continue_without_increment
        end
      end

      is_searching = false

      local search_end = i

      local prev_line = result_lines[i - 1]
      if prev_line and prev_line:match("^%s*```$") then search_end = i - 1 end

      local start_line = 0
      local end_line = 0
      local match_filetype = nil
      local filepath = current_filepath or prev_filepath or ""
      ---@type {path: string, content: string, file_type: string | nil} | nil
      local the_matched_file = nil
      for _, file in ipairs(selected_files) do
        if Utils.is_same_file(file.path, filepath) then
          the_matched_file = file
          break
        end
      end

      if not the_matched_file then
        if not PPath:new(filepath):exists() then
          the_matched_file = {
            filepath = filepath,
            content = "",
            file_type = nil,
          }
        else
          if not PPath:new(filepath):is_file() then
            Utils.warn("Not a file: " .. filepath)
            goto continue
          end
          local lines = Utils.read_file_from_buf_or_disk(filepath)
          if lines == nil then
            Utils.warn("Failed to read file: " .. filepath)
            goto continue
          end
          local content = table.concat(lines, "\n")
          the_matched_file = {
            filepath = filepath,
            content = content,
            file_type = nil,
          }
        end
      end

      local file_content = vim.split(the_matched_file.content, "\n")
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
          match_filetype = the_matched_file.file_type
          break
        end
      end

      -- when the filetype isn't detected, fallback to matching based on filepath.
      -- can happen if the llm tries to edit or create a file outside of it's context.
      if not match_filetype then
        local snippet_file_path = current_filepath or prev_filepath
        match_filetype = Utils.get_filetype(snippet_file_path)
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
      waiting_for_breakline = true
      vim.list_extend(transformed_lines, {
        string.format("Replace lines: %d-%d", start_line, end_line),
        string.format("```%s", match_filetype),
      })
      goto continue
    elseif line_content:match("^%s*<[Rr][Ee][Pp][Ll][Aa][Cc][Ee]>") then
      is_replacing = true
      if not line_content:match("^%s*<[Rr][Ee][Pp][Ll][Aa][Cc][Ee]>%s*$") then
        local replace_first_line = line_content:match("<[Rr][Ee][Pp][Ll][Aa][Cc][Ee]>(.+)$")
        line_content = "<REPLACE>"
        result_lines[i] = line_content
        if replace_first_line and replace_first_line ~= "" then
          table.insert(result_lines, i + 1, replace_first_line)
        end
      end
      local next_line = result_lines[i + 1]
      if next_line and next_line:match("^%s*```%w+$") then i = i + 1 end
      last_replace_tag_start_line = i
      goto continue
    elseif line_content:match("</[Rr][Ee][Pp][Ll][Aa][Cc][Ee]>%s*$") then
      -- Handle case where </REPLACE> is a suffix
      if not line_content:match("^%s*</[Rr][Ee][Pp][Ll][Aa][Cc][Ee]>%s*$") then
        local replace_end_line = line_content:match("^(.+)</[Rr][Ee][Pp][Ll][Aa][Cc][Ee]>")
        line_content = "</REPLACE>"
        result_lines[i] = line_content
        if replace_end_line and replace_end_line ~= "" then
          table.insert(result_lines, i, replace_end_line)
          goto continue_without_increment
        end
      end
      is_replacing = false
      local prev_line = result_lines[i - 1]
      if not (prev_line and prev_line:match("^%s*```$")) then table.insert(transformed_lines, "```") end
      local next_line = result_lines[i + 1]
      if next_line and next_line:match("^%s*```%s*$") then i = i + 1 end
      goto continue
    elseif line_content == "<think>" then
      is_thinking = true
      last_think_tag_start_line = i
      last_think_tag_end_line = 0
    elseif line_content == "</think>" then
      is_thinking = false
      last_think_tag_end_line = i
    elseif line_content:match("^%s*```%s*$") then
      local prev_line = result_lines[i - 1]
      if prev_line and prev_line:match("^%s*```$") then goto continue end
    end
    waiting_for_breakline = false
    table.insert(transformed_lines, line_content)
    ::continue::
    i = i + 1
    ::continue_without_increment::
  end

  return {
    current_filepath = current_filepath,
    content = table.concat(transformed_lines, "\n"),
    waiting_for_breakline = waiting_for_breakline,
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
  Utils.icon("🤯", "?"),
  Utils.icon("🙄", "¿"),
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
    local result_lines = vim.list_extend(
      vim.list_slice(lines, 1, replacement.last_search_tag_start_line),
      { Utils.icon("🤔 ") .. "Thought content:" }
    )
    result_lines = vim.list_extend(result_lines, formatted_thinking_content_lines)
    result_lines = vim.list_extend(result_lines, vim.list_slice(lines, last_think_tag_end_line + 1))
    return table.concat(result_lines, "\n")
  end
  return replacement.content
end

---@return string | nil filepath
---@return boolean skip_next_line
local function obtain_filepath_from_codeblock(lines, line_number)
  local line = lines[line_number]
  local filepath = line:match("^%s*```%w+:(.+)$")
  if not filepath then
    local next_line = lines[line_number + 1]
    if next_line then
      local filepath2 = next_line:match("[Ff][Ii][Ll][Ee][Pp][Aa][Tt][Hh]:%s*(.+)%s*")
      if filepath2 then return filepath2, true end
      local filepath3 = next_line:match("[Ff][Ii][Ll][Ee]:%s*(.+)%s*")
      if filepath3 then return filepath3, true end
    end
    for i = line_number - 1, line_number - 2, -1 do
      if i < 1 then break end
      local line_ = lines[i]
      local filepath4 = line_:match("[Ff][Ii][Ll][Ee][Pp][Aa][Tt][Hh]:%s*`?(.-)`?%s*$")
      if filepath4 then return filepath4, false end
      local filepath5 = line_:match("[Ff][Ii][Ll][Ee]:%s*`?(.-)`?%s*$")
      if filepath5 then return filepath5, false end
    end
  end
  return filepath, false
end

---@class AvanteCodeSnippet
---@field range integer[]
---@field content string
---@field lang string
---@field explanation string
---@field start_line_in_response_buf integer
---@field end_line_in_response_buf integer
---@field filepath string

---@param source string|integer
---@return TSNode[]
local function tree_sitter_markdown_parse_code_blocks(source)
  local query = require("vim.treesitter.query")
  local parser
  if type(source) == "string" then
    parser = vim.treesitter.get_string_parser(source, "markdown")
  else
    parser = vim.treesitter.get_parser(source, "markdown")
  end
  if parser == nil then
    Utils.warn("Failed to get markdown parser")
    return {}
  end
  local tree = parser:parse()[1]
  local root = tree:root()
  local code_block_query = query.parse(
    "markdown",
    [[ (fenced_code_block
      (info_string
        (language) @language)?
      (block_continuation) @code_start
      (fenced_code_block_delimiter) @code_end) ]]
  )
  local nodes = {}
  for _, node in code_block_query:iter_captures(root, source) do
    table.insert(nodes, node)
  end
  return nodes
end

---@param response_content string
---@return table<string, AvanteCodeSnippet[]>
local function extract_cursor_planning_code_snippets_map(response_content, current_filepath, current_filetype)
  local snippets = {}
  local lines = vim.split(response_content, "\n")
  local cumulated_content = ""

  -- use tree-sitter-markdown to parse all code blocks in response_content
  local lang = "unknown"
  local start_line
  for _, node in ipairs(tree_sitter_markdown_parse_code_blocks(response_content)) do
    if node:type() == "language" then
      lang = vim.treesitter.get_node_text(node, response_content)
      lang = vim.split(lang, ":")[1]
    elseif node:type() == "block_continuation" then
      start_line, _ = node:start()
    elseif node:type() == "fenced_code_block_delimiter" and start_line ~= nil and node:start() >= start_line then
      local end_line, _ = node:start()
      local filepath, skip_next_line = obtain_filepath_from_codeblock(lines, start_line)
      if filepath == nil or filepath == "" then
        if lang == current_filetype then
          filepath = current_filepath
        else
          Utils.warn(
            string.format(
              "Failed to parse filepath from code block, and current_filetype `%s` is not the same as the filetype `%s` of the current code block, so ignore this code block",
              current_filetype,
              lang
            )
          )
          lang = "unknown"
          goto continue
        end
      end
      if skip_next_line then start_line = start_line + 1 end
      local this_content = table.concat(vim.list_slice(lines, start_line + 1, end_line), "\n")
      cumulated_content = cumulated_content .. "\n" .. this_content
      table.insert(snippets, {
        range = { 0, 0 },
        content = cumulated_content,
        lang = lang,
        filepath = filepath,
        start_line_in_response_buf = start_line,
        end_line_in_response_buf = end_line + 1,
      })
    end
    ::continue::
  end

  local snippets_map = {}
  for _, snippet in ipairs(snippets) do
    if snippet.filepath == "" then goto continue end
    snippets_map[snippet.filepath] = snippets_map[snippet.filepath] or {}
    table.insert(snippets_map[snippet.filepath], snippet)
    ::continue::
  end

  return snippets_map
end

---@param response_content string
---@return table<string, AvanteCodeSnippet[]>
local function extract_code_snippets_map(response_content)
  local snippets = {}
  local lines = vim.split(response_content, "\n")

  -- use tree-sitter-markdown to parse all code blocks in response_content
  local lang = "text"
  local start_line, end_line
  local start_line_in_response_buf, end_line_in_response_buf
  local explanation_start_line = 0
  for _, node in ipairs(tree_sitter_markdown_parse_code_blocks(response_content)) do
    if node:type() == "language" then
      lang = vim.treesitter.get_node_text(node, response_content)
    elseif node:type() == "block_continuation" and node:start() > 1 then
      start_line_in_response_buf = node:start()
      local number_line = lines[start_line_in_response_buf - 1]

      local _, start_line_str, end_line_str =
        number_line:match("^%s*(%d*)[%.%)%s]*[Aa]?n?d?%s*[Rr]eplace%s+[Ll]ines:?%s*(%d+)%-(%d+)")
      if start_line_str ~= nil and end_line_str ~= nil then
        start_line = tonumber(start_line_str)
        end_line = tonumber(end_line_str)
      else
        _, start_line_str = number_line:match("^%s*(%d*)[%.%)%s]*[Aa]?n?d?%s*[Rr]eplace%s+[Ll]ine:?%s*(%d+)")
        if start_line_str ~= nil then
          start_line = tonumber(start_line_str)
          end_line = tonumber(start_line_str)
        else
          start_line_str = number_line:match("[Aa]fter%s+[Ll]ine:?%s*(%d+)")
          if start_line_str ~= nil then
            start_line = tonumber(start_line_str) + 1
            end_line = tonumber(start_line_str) + 1
          end
        end
      end
    elseif
      node:type() == "fenced_code_block_delimiter"
      and start_line_in_response_buf ~= nil
      and node:start() >= start_line_in_response_buf
    then
      end_line_in_response_buf, _ = node:start()
      if start_line ~= nil and end_line ~= nil then
        local filepath = lines[start_line_in_response_buf - 2]
        if filepath:match("^[Ff]ilepath:") then filepath = filepath:match("^[Ff]ilepath:%s*(.+)") end
        local content =
          table.concat(vim.list_slice(lines, start_line_in_response_buf + 1, end_line_in_response_buf), "\n")
        local explanation = ""
        if start_line_in_response_buf > explanation_start_line + 2 then
          explanation =
            table.concat(vim.list_slice(lines, explanation_start_line, start_line_in_response_buf - 3), "\n")
        end
        local snippet = {
          range = { start_line, end_line },
          content = content,
          lang = lang,
          explanation = explanation,
          start_line_in_response_buf = start_line_in_response_buf,
          end_line_in_response_buf = end_line_in_response_buf + 1,
          filepath = filepath,
        }
        table.insert(snippets, snippet)
      end
      lang = "text"
      explanation_start_line = end_line_in_response_buf + 2
    end
  end

  local snippets_map = {}
  for _, snippet in ipairs(snippets) do
    if snippet.filepath == "" then goto continue end
    snippets_map[snippet.filepath] = snippets_map[snippet.filepath] or {}
    table.insert(snippets_map[snippet.filepath], snippet)
    ::continue::
  end

  return snippets_map
end

---@param snippets_map table<string, AvanteCodeSnippet[]>
---@return table<string, AvanteCodeSnippet[]>
local function ensure_snippets_no_overlap(snippets_map)
  local new_snippets_map = {}

  for filepath, snippets in pairs(snippets_map) do
    table.sort(snippets, function(a, b) return a.range[1] < b.range[1] end)

    local original_lines = {}
    local file_exists = Utils.file.exists(filepath)
    if file_exists then
      local original_lines_ = Utils.read_file_from_buf_or_disk(filepath)
      if original_lines_ then original_lines = original_lines_ end
    end

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

  local lines = Utils.get_buf_lines(0, -1, bufnr)

  local offset = 0

  for _, snippet in ipairs(snippets) do
    local start_line, end_line = unpack(snippet.range)

    local result = {}
    table.insert(result, "<<<<<<< HEAD")
    for i = start_line, end_line do
      table.insert(result, lines[i])
    end
    table.insert(result, "=======")

    local snippet_lines = vim.split(snippet.content, "\n")

    vim.list_extend(result, snippet_lines)

    table.insert(result, ">>>>>>> Snippet")

    api.nvim_buf_set_lines(bufnr, offset + start_line - 1, offset + end_line, false, result)
    offset = offset + #snippet_lines + 3
  end
end

---@param codeblocks table<integer, any>
local function is_cursor_in_codeblock(codeblocks)
  local cursor_line, _ = Utils.get_cursor_pos()

  for _, block in ipairs(codeblocks) do
    if cursor_line >= block.start_line and cursor_line <= block.end_line then return block end
  end

  return nil
end

---@class AvanteRespUserRequestBlock
---@field start_line number 1-indexed
---@field end_line number 1-indexed
---@field content string

---@return AvanteRespUserRequestBlock | nil
function Sidebar:get_current_user_request_block()
  local current_resp_content, current_resp_start_line = self:get_content_between_separators()
  if current_resp_content == nil then return nil end
  if current_resp_content == "" then return nil end
  local lines = vim.split(current_resp_content, "\n")
  local start_line = nil
  local end_line = nil
  local content_lines = {}
  for i = 1, #lines do
    local line = lines[i]
    local m = line:match("^>%s+(.+)$")
    if m then
      if start_line == nil then start_line = i end
      table.insert(content_lines, m)
      end_line = i
    elseif line ~= "" then
      if start_line ~= nil then
        end_line = i - 2
        break
      end
    else
      if start_line ~= nil then table.insert(content_lines, line) end
    end
  end
  if start_line == nil then return nil end
  content_lines = vim.list_slice(content_lines, 1, #content_lines - 1)
  local content = table.concat(content_lines, "\n")
  return {
    start_line = current_resp_start_line + start_line - 1,
    end_line = current_resp_start_line + end_line - 1,
    content = content,
  }
end

function Sidebar:is_cursor_in_user_request_block()
  local block = self:get_current_user_request_block()
  if block == nil then return false end
  local cursor_line = api.nvim_win_get_cursor(self.result_container.winid)[1]
  return cursor_line >= block.start_line and cursor_line <= block.end_line
end

---@class AvanteCodeblock
---@field start_line integer 1-indexed
---@field end_line integer 1-indexed
---@field lang string

---@param buf integer
---@return AvanteCodeblock[]
local function parse_codeblocks(buf, current_filepath, current_filetype)
  local codeblocks = {}
  local lines = Utils.get_buf_lines(0, -1, buf)
  local lang, start_line, valid
  for _, node in ipairs(tree_sitter_markdown_parse_code_blocks(buf)) do
    if node:type() == "language" then
      lang = vim.treesitter.get_node_text(node, buf)
    elseif node:type() == "block_continuation" then
      start_line, _ = node:start()
    elseif node:type() == "fenced_code_block_delimiter" and start_line ~= nil and node:start() >= start_line then
      local end_line, _ = node:start()
      if Config.behaviour.enable_cursor_planning_mode then
        local filepath = obtain_filepath_from_codeblock(lines, start_line)
        if not filepath and lang == current_filetype then filepath = current_filepath end
        valid = filepath ~= nil
      else
        valid = lines[start_line - 1]:match("^%s*(%d*)[%.%)%s]*[Aa]?n?d?%s*[Rr]eplace%s+[Ll]ines:?%s*(%d+)%-(%d+)")
          ~= nil
      end
      if valid then table.insert(codeblocks, { start_line = start_line, end_line = end_line + 1, lang = lang }) end
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
      range = {
        count_a > 0 and start_line + start_a - 1 or start_line + start_a,
        start_line + start_a + math.max(count_a, 1) - 2,
      },
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

---@param filepath string
---@param snippets AvanteCodeSnippet[]
---@return table<string, AvanteCodeSnippet[]>
function Sidebar:minimize_snippets(filepath, snippets)
  local original_lines = {}

  local original_lines_ = Utils.read_file_from_buf_or_disk(filepath)
  if original_lines_ then original_lines = original_lines_ end

  local results = {}

  for _, snippet in ipairs(snippets) do
    local new_snippets = minimize_snippet(original_lines, snippet)
    if new_snippets then
      for _, new_snippet in ipairs(new_snippets) do
        table.insert(results, new_snippet)
      end
    end
  end

  return results
end

function Sidebar:retry_user_request()
  local block = self:get_current_user_request_block()
  if not block then return end
  self.handle_submit(block.content)
end

function Sidebar:edit_user_request()
  local block = self:get_current_user_request_block()
  if not block then return end

  if Utils.is_valid_container(self.input_container) then
    local lines = vim.split(block.content, "\n")
    api.nvim_buf_set_lines(self.input_container.bufnr, 0, -1, false, lines)
    api.nvim_set_current_win(self.input_container.winid)
    api.nvim_win_set_cursor(self.input_container.winid, { 1, #lines > 0 and #lines[1] or 0 })
  end
end

---@param current_cursor boolean
function Sidebar:apply(current_cursor)
  local buf_path = api.nvim_buf_get_name(self.code.bufnr)
  local current_filepath = Utils.file.is_in_cwd(buf_path) and Utils.relative_path(buf_path) or buf_path
  local current_filetype = Utils.get_filetype(current_filepath)

  local response, response_start_line = self:get_content_between_separators()
  local all_snippets_map = Config.behaviour.enable_cursor_planning_mode
      and extract_cursor_planning_code_snippets_map(response, current_filepath, current_filetype)
    or extract_code_snippets_map(response)
  if not Config.behaviour.enable_cursor_planning_mode then
    all_snippets_map = ensure_snippets_no_overlap(all_snippets_map)
  end
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

  if Config.behaviour.enable_cursor_planning_mode then
    for filepath, snippets in pairs(selected_snippets_map) do
      local original_code_lines = Utils.read_file_from_buf_or_disk(filepath)
      if not original_code_lines then
        Utils.error("Failed to read file: " .. filepath)
        return
      end
      local formated_snippets = vim.iter(snippets):map(function(snippet) return snippet.content end):totable()
      local original_code = table.concat(original_code_lines, "\n")
      local resp_content = ""
      local filetype = Utils.get_filetype(filepath)
      local cursor_applying_provider_name = Config.cursor_applying_provider or Config.provider
      Utils.debug(string.format("Use %s for cursor applying", cursor_applying_provider_name))
      local cursor_applying_provider = Provider[cursor_applying_provider_name]
      if not cursor_applying_provider then
        Utils.error("Failed to find cursor_applying_provider provider: " .. cursor_applying_provider_name, {
          once = true,
          title = "Avante",
        })
      end
      if self.code.winid ~= nil and api.nvim_win_is_valid(self.code.winid) then
        api.nvim_set_current_win(self.code.winid)
      end
      local bufnr = Utils.get_or_create_buffer_with_filepath(filepath)
      local path_ = PPath:new(filepath)
      path_:parent():mkdir({ parents = true, exists_ok = true })

      local ns_id = api.nvim_create_namespace("avante_live_diff")

      local function clear_highlights() api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) end

      -- Create loading indicator float window
      local loading_buf = nil
      local loading_win = nil
      local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
      local spinner_idx = 1
      local loading_timer = nil

      local function update_loading_indicator()
        if not loading_win or not loading_buf or not api.nvim_win_is_valid(loading_win) then return end
        spinner_idx = (spinner_idx % #spinner_frames) + 1
        local text = spinner_frames[spinner_idx] .. " Applying changes..."
        api.nvim_buf_set_lines(loading_buf, 0, -1, false, { text })
      end

      local function create_loading_window()
        local winid = self.input_container.winid
        local win_height = api.nvim_win_get_height(winid)
        local win_width = api.nvim_win_get_width(winid)

        -- Calculate position for center of window
        local width = 30
        local height = 1
        local row = win_height - height - 1
        local col = win_width - width

        local opts = {
          relative = "win",
          win = winid,
          width = width,
          height = height,
          row = row,
          col = col,
          anchor = "NW",
          style = "minimal",
          border = "none",
          focusable = false,
          zindex = 101,
        }

        loading_buf = api.nvim_create_buf(false, true)
        loading_win = api.nvim_open_win(loading_buf, false, opts)

        -- Start timer to update spinner
        loading_timer = vim.loop.new_timer()
        if loading_timer then loading_timer:start(0, 100, vim.schedule_wrap(update_loading_indicator)) end
      end

      local function close_loading_window()
        if loading_timer then
          loading_timer:stop()
          loading_timer:close()
          loading_timer = nil
        end
        if loading_win and api.nvim_win_is_valid(loading_win) then
          api.nvim_win_close(loading_win, true)
          loading_win = nil
        end

        if loading_buf then
          api.nvim_buf_delete(loading_buf, { force = true })
          loading_buf = nil
        end
      end

      clear_highlights()
      create_loading_window()

      local last_processed_line = 0
      local last_orig_diff_end_line = 1
      local last_resp_diff_end_line = 1
      local cleaned = false
      local prev_patch = {}

      local function get_stable_patch(patch)
        local new_patch = {}
        for _, hunk in ipairs(patch) do
          local start_a, count_a, start_b, count_b = unpack(hunk)
          start_a = start_a + last_orig_diff_end_line - 1
          start_b = start_b + last_resp_diff_end_line - 1
          local has = vim.iter(prev_patch):find(function(hunk_)
            local start_a_, count_a_, start_b_, count_b_ = unpack(hunk_)
            return start_a == start_a_ and start_b == start_b_ and count_a == count_a_ and count_b == count_b_
          end)
          if has ~= nil then table.insert(new_patch, hunk) end
        end
        return new_patch
      end

      local extmark_id_map = {}
      local virt_lines_map = {}

      Llm.stream({
        ask = true,
        provider = cursor_applying_provider,
        code_lang = filetype,
        mode = "cursor-applying",
        original_code = original_code,
        update_snippets = formated_snippets,
        on_start = function(_) end,
        on_chunk = function(chunk)
          if not chunk then return end

          resp_content = resp_content .. chunk

          if not cleaned then
            resp_content = resp_content:gsub("<updated%-code>\n*", ""):gsub("</updated%-code>\n*", "")
            resp_content = resp_content:gsub(".*```%w+\n", ""):gsub("\n```\n.*", "")
          end

          local resp_lines = vim.split(resp_content, "\n")

          local complete_lines_count = #resp_lines - 1
          if complete_lines_count > 2 then cleaned = true end

          if complete_lines_count <= last_processed_line then return end

          local original_lines_to_process =
            vim.list_slice(original_code_lines, last_orig_diff_end_line, complete_lines_count)
          local resp_lines_to_process = vim.list_slice(resp_lines, last_resp_diff_end_line, complete_lines_count)

          local resp_lines_content = table.concat(resp_lines_to_process, "\n")
          local original_lines_content = table.concat(original_lines_to_process, "\n")

          ---@diagnostic disable-next-line: assign-type-mismatch, missing-fields
          local patch = vim.diff(original_lines_content, resp_lines_content, { ---@type integer[][]
            algorithm = "histogram",
            result_type = "indices",
            ctxlen = vim.o.scrolloff,
          })

          local stable_patch = get_stable_patch(patch)

          for _, hunk in ipairs(stable_patch) do
            local start_a, count_a, start_b, count_b = unpack(hunk)

            start_a = last_orig_diff_end_line + start_a - 1

            if count_a > 0 then
              api.nvim_buf_set_extmark(bufnr, ns_id, start_a - 1, 0, {
                hl_group = Highlights.TO_BE_DELETED_WITHOUT_STRIKETHROUGH,
                hl_eol = true,
                hl_mode = "combine",
                end_row = start_a + count_a - 1,
              })
            end

            if count_b == 0 then goto continue end

            local new_lines = vim.list_slice(resp_lines_to_process, start_b, start_b + count_b - 1)
            local max_col = vim.o.columns
            local virt_lines = vim
              .iter(new_lines)
              :map(function(line)
                --- append spaces to the end of the line
                local line_ = line .. string.rep(" ", max_col - #line)
                return { { line_, Highlights.INCOMING } }
              end)
              :totable()
            local extmark_line
            if count_a > 0 then
              extmark_line = math.max(0, start_a + count_a - 2)
            else
              extmark_line = math.max(0, start_a + count_a - 1)
            end
            local old_extmark_id = extmark_id_map[extmark_line]
            if old_extmark_id ~= nil then
              local old_virt_lines = virt_lines_map[old_extmark_id] or {}
              virt_lines = vim.list_extend(old_virt_lines, virt_lines)
              api.nvim_buf_del_extmark(bufnr, ns_id, old_extmark_id)
            end
            local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, extmark_line, 0, {
              virt_lines = virt_lines,
              hl_eol = true,
              hl_mode = "combine",
            })
            extmark_id_map[extmark_line] = extmark_id
            virt_lines_map[extmark_id] = virt_lines
            ::continue::
          end

          prev_patch = vim
            .iter(patch)
            :map(function(hunk)
              local start_a, count_a, start_b, count_b = unpack(hunk)
              return { last_orig_diff_end_line + start_a - 1, count_a, last_resp_diff_end_line + start_b - 1, count_b }
            end)
            :totable()

          if #stable_patch > 0 then
            local start_a, count_a, start_b, count_b = unpack(stable_patch[#stable_patch])
            last_orig_diff_end_line = last_orig_diff_end_line + start_a + math.max(count_a, 1) - 1
            last_resp_diff_end_line = last_resp_diff_end_line + start_b + math.max(count_b, 1) - 1
          end

          if #patch == 0 then
            last_orig_diff_end_line = complete_lines_count + 1
            last_resp_diff_end_line = complete_lines_count + 1
          end

          last_processed_line = complete_lines_count

          local winid = Utils.get_winid(bufnr)

          if winid == nil then return end

          --- goto window winid
          api.nvim_set_current_win(winid)
          --- goto the last line
          pcall(function() api.nvim_win_set_cursor(winid, { complete_lines_count, 0 }) end)
          vim.cmd("normal! zz")
        end,
        on_stop = function(stop_opts)
          clear_highlights()
          close_loading_window()

          if stop_opts.error ~= nil then
            Utils.error(string.format("applying failed: %s", vim.inspect(stop_opts.error)))
            return
          end

          resp_content = resp_content:gsub("<updated%-code>\n*", ""):gsub("</updated%-code>\n*", "")

          resp_content = resp_content:gsub(".*```%w+\n", ""):gsub("\n```\n.*", ""):gsub("\n```$", "")

          local resp_lines = vim.split(resp_content, "\n")

          if #resp_lines > 0 and resp_lines[#resp_lines] == "" then
            resp_lines = vim.list_slice(resp_lines, 0, #resp_lines - 1)
            resp_content = table.concat(resp_lines, "\n")
          end

          if require("avante.config").debug then
            local resp_content_file = fn.tempname() .. ".txt"
            fn.writefile(vim.split(resp_content, "\n"), resp_content_file)
            Utils.debug("cursor applying response content written to: " .. resp_content_file)
          end

          if resp_content == original_code then return end

          ---@diagnostic disable-next-line: assign-type-mismatch, missing-fields
          local patch = vim.diff(original_code, resp_content, { ---@type integer[][]
            algorithm = "histogram",
            result_type = "indices",
            ctxlen = vim.o.scrolloff,
          })

          local new_lines = {}
          local prev_start_a = 1
          for _, hunk in ipairs(patch) do
            local start_a, count_a, start_b, count_b = unpack(hunk)
            if count_a > 0 then
              vim.list_extend(new_lines, vim.list_slice(original_code_lines, prev_start_a, start_a - 1))
            else
              vim.list_extend(new_lines, vim.list_slice(original_code_lines, prev_start_a, start_a))
            end
            prev_start_a = start_a + count_a
            if count_a == 0 then prev_start_a = prev_start_a + 1 end
            table.insert(new_lines, "<<<<<<< HEAD")
            if count_a > 0 then
              vim.list_extend(new_lines, vim.list_slice(original_code_lines, start_a, start_a + count_a - 1))
            end
            table.insert(new_lines, "=======")
            if count_b > 0 then
              vim.list_extend(new_lines, vim.list_slice(resp_lines, start_b, start_b + count_b - 1))
            end
            table.insert(new_lines, ">>>>>>> Snippet")
          end

          local remaining_lines = vim.list_slice(original_code_lines, prev_start_a, #original_code_lines)
          new_lines = vim.list_extend(new_lines, remaining_lines)

          api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

          local function process(winid)
            api.nvim_set_current_win(winid)
            vim.cmd("noautocmd stopinsert")
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
              group = self.augroup,
              buffer = bufnr,
              once = true,
              callback = function()
                local winid_ = Utils.get_winid(bufnr)
                if winid_ then process(winid_) end
              end,
            })
          end
        end,
      })
    end
    return
  end

  vim.defer_fn(function()
    api.nvim_set_current_win(self.code.winid)
    for filepath, snippets in pairs(selected_snippets_map) do
      if Config.behaviour.minimize_diff then snippets = self:minimize_snippets(filepath, snippets) end
      local bufnr = Utils.get_or_create_buffer_with_filepath(filepath)
      local path_ = PPath:new(Utils.is_win() and filepath:gsub("/", "\\") or filepath)
      path_:parent():mkdir({ parents = true, exists_ok = true })
      insert_conflict_contents(bufnr, snippets)
      local function process(winid)
        api.nvim_set_current_win(winid)
        vim.cmd("noautocmd stopinsert")
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
          group = self.augroup,
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
  linebreak = true,
  breakindent = true,
  wrap = false,
  cursorline = false,
  fillchars = "eob: ",
  winhighlight = "CursorLine:Normal,CursorColumn:Normal,WinSeparator:"
    .. Highlights.AVANTE_SIDEBAR_WIN_SEPARATOR
    .. ",Normal:"
    .. Highlights.AVANTE_SIDEBAR_NORMAL,
  winbar = "",
  statusline = "",
}

function Sidebar:render_header(winid, bufnr, header_text, hl, reverse_hl)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then return end

  local is_result_win = self.winids.result_container == winid

  local separator_char = is_result_win and " " or "-"

  if not Config.windows.sidebar_header.enabled then return end

  if not Config.windows.sidebar_header.rounded then header_text = " " .. header_text .. " " end

  local win_width = vim.api.nvim_win_get_width(winid)

  local padding = math.floor((win_width - #header_text) / 2)
  if Config.windows.sidebar_header.align ~= "center" then padding = win_width - #header_text end

  local winbar_text = "%#" .. Highlights.AVANTE_SIDEBAR_WIN_HORIZONTAL_SEPARATOR .. "#"

  if Config.windows.sidebar_header.align ~= "left" then
    if not Config.windows.sidebar_header.rounded then winbar_text = winbar_text .. " " end
    winbar_text = winbar_text .. string.rep(separator_char, padding)
  end

  -- if Config.windows.sidebar_header.align == "center" then
  --   winbar_text = winbar_text .. "%="
  -- elseif Config.windows.sidebar_header.align == "right" then
  --   winbar_text = winbar_text .. "%="
  -- end

  if Config.windows.sidebar_header.rounded then
    winbar_text = winbar_text .. "%#" .. reverse_hl .. "#" .. Utils.icon("", "『") .. "%#" .. hl .. "#"
  else
    winbar_text = winbar_text .. "%#" .. hl .. "#"
  end
  winbar_text = winbar_text .. header_text
  if Config.windows.sidebar_header.rounded then
    winbar_text = winbar_text .. "%#" .. reverse_hl .. "#" .. Utils.icon("", "』")
  end
  -- if Config.windows.sidebar_header.align == "center" then winbar_text = winbar_text .. "%=" end

  winbar_text = winbar_text .. "%#" .. Highlights.AVANTE_SIDEBAR_WIN_HORIZONTAL_SEPARATOR .. "#"
  if Config.windows.sidebar_header.align ~= "right" then
    winbar_text = winbar_text .. string.rep(separator_char, padding)
  end

  api.nvim_set_option_value("winbar", winbar_text, { win = winid })
end

function Sidebar:render_result()
  if not Utils.is_valid_container(self.result_container) then return end
  local header_text = Utils.icon("󰭻 ") .. "Avante"
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
  if not Utils.is_valid_container(self.input_container) then return end

  local header_text = string.format(
    "%s%s (" .. Config.mappings.sidebar.switch_windows .. ": switch focus)",
    Utils.icon("󱜸 "),
    ask and "Ask" or "Chat with"
  )

  if self.code.selection ~= nil then
    header_text = string.format(
      "%s%s (%d:%d) (<Tab>: switch focus)",
      Utils.icon("󱜸 "),
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
  if not Utils.is_valid_container(self.selected_code_container) then return end

  local selected_code_lines_count = 0
  local selected_code_max_lines_count = 12

  if self.code.selection ~= nil then
    local selected_code_lines = vim.split(self.code.selection.content, "\n")
    selected_code_lines_count = #selected_code_lines
  end

  local header_text = Utils.icon(" ")
    .. "Selected Code"
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

function Sidebar:bind_retry_user_request_key()
  if self.result_container then
    vim.keymap.set(
      "n",
      Config.mappings.sidebar.retry_user_request,
      function() self:retry_user_request() end,
      { buffer = self.result_container.bufnr, noremap = true, silent = true }
    )
  end
end

function Sidebar:unbind_retry_user_request_key()
  if self.result_container then
    pcall(vim.keymap.del, "n", Config.mappings.sidebar.retry_user_request, { buffer = self.result_container.bufnr })
  end
end

function Sidebar:bind_edit_user_request_key()
  if self.result_container then
    vim.keymap.set(
      "n",
      Config.mappings.sidebar.edit_user_request,
      function() self:edit_user_request() end,
      { buffer = self.result_container.bufnr, noremap = true, silent = true }
    )
  end
end

function Sidebar:unbind_edit_user_request_key()
  if self.result_container then
    pcall(vim.keymap.del, "n", Config.mappings.sidebar.edit_user_request, { buffer = self.result_container.bufnr })
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
      api.nvim_win_set_cursor(self.result_container.winid, { target_block.start_line, 0 })
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
  if Utils.is_valid_container(self.result_container) then
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

  ---@param block AvanteCodeblock
  local function show_apply_button(block)
    if current_apply_extmark_id then
      api.nvim_buf_del_extmark(self.result_container.bufnr, CODEBLOCK_KEYBINDING_NAMESPACE, current_apply_extmark_id)
    end

    current_apply_extmark_id =
      api.nvim_buf_set_extmark(self.result_container.bufnr, CODEBLOCK_KEYBINDING_NAMESPACE, block.start_line - 1, -1, {
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

  local current_user_request_block_extmark_id = nil

  local function show_user_request_block_control_buttons()
    if current_user_request_block_extmark_id then
      api.nvim_buf_del_extmark(
        self.result_container.bufnr,
        USER_REQUEST_BLOCK_KEYBINDING_NAMESPACE,
        current_user_request_block_extmark_id
      )
    end

    local block = self:get_current_user_request_block()
    if not block then return end

    current_user_request_block_extmark_id = api.nvim_buf_set_extmark(
      self.result_container.bufnr,
      USER_REQUEST_BLOCK_KEYBINDING_NAMESPACE,
      block.start_line - 1,
      -1,
      {
        virt_text = {
          {
            string.format(
              " [<%s>: retry, <%s>: edit] ",
              Config.mappings.sidebar.retry_user_request,
              Config.mappings.sidebar.edit_user_request
            ),
            "AvanteInlineHint",
          },
        },
        virt_text_pos = "right_align",
        hl_group = "AvanteInlineHint",
        priority = PRIORITY,
      }
    )
  end

  ---@type AvanteCodeblock[]
  local codeblocks = {}

  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = self.augroup,
    buffer = self.result_container.bufnr,
    callback = function(ev)
      local in_codeblock = is_cursor_in_codeblock(codeblocks)

      if in_codeblock then
        show_apply_button(in_codeblock)
        self:bind_apply_key()
      else
        api.nvim_buf_clear_namespace(ev.buf, CODEBLOCK_KEYBINDING_NAMESPACE, 0, -1)
        self:unbind_apply_key()
      end

      local in_user_request_block = self:is_cursor_in_user_request_block()
      if in_user_request_block then
        show_user_request_block_control_buttons()
        self:bind_retry_user_request_key()
        self:bind_edit_user_request_key()
      else
        api.nvim_buf_clear_namespace(ev.buf, USER_REQUEST_BLOCK_KEYBINDING_NAMESPACE, 0, -1)
        self:unbind_retry_user_request_key()
        self:unbind_edit_user_request_key()
      end
    end,
  })

  local buf_path = api.nvim_buf_get_name(self.code.bufnr)
  local current_filepath = Utils.file.is_in_cwd(buf_path) and Utils.relative_path(buf_path) or buf_path
  local current_filetype = Utils.get_filetype(current_filepath)

  api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = self.augroup,
    buffer = self.result_container.bufnr,
    callback = function(ev)
      codeblocks = parse_codeblocks(ev.buf, current_filepath, current_filetype)
      self:bind_sidebar_keys(codeblocks)
    end,
  })

  api.nvim_create_autocmd("User", {
    group = self.augroup,
    pattern = VIEW_BUFFER_UPDATED_PATTERN,
    callback = function()
      if not Utils.is_valid_container(self.result_container) then return end
      codeblocks = parse_codeblocks(self.result_container.bufnr, current_filepath, current_filetype)
      self:bind_sidebar_keys(codeblocks)
    end,
  })

  api.nvim_create_autocmd("BufLeave", {
    group = self.augroup,
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
        if Utils.is_valid_container(self.input_container, true) then
          api.nvim_set_current_win(self.input_container.winid)
          vim.defer_fn(function()
            if Config.windows.ask.start_insert then vim.cmd("noautocmd startinsert!") end
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
      if closed_winid == self.winids.selected_files_container then return end
      if not self:is_sidebar_winid(closed_winid) then return end
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
    winids = vim.iter(winids):filter(function(winid) return api.nvim_win_is_valid(winid) end):totable()
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
    winids = vim.iter(winids):filter(function(winid) return api.nvim_win_is_valid(winid) end):totable()
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
  local filepath = Utils.file.is_in_cwd(buf_path) and Utils.relative_path(buf_path) or buf_path
  Utils.debug("Sidebar:initialize adding buffer to file selector", buf_path)

  self.file_selector:reset()
  self.file_selector:add_selected_file(filepath)

  self:reload_chat_history()

  return self
end

function Sidebar:is_focused()
  if not self:is_open() then return false end

  local current_winid = api.nvim_get_current_win()
  if self.winids.result_container and self.winids.result_container == current_winid then return true end
  if self.winids.selected_files_container and self.winids.selected_files_container == current_winid then
    return true
  end
  if self.winids.selected_code_container and self.winids.selected_code_container == current_winid then return true end
  if self.winids.input_container and self.winids.input_container == current_winid then return true end

  return false
end

function Sidebar:is_focused_on_result()
  return self:is_open() and self.result_container and self.result_container.winid == api.nvim_get_current_win()
end

function Sidebar:is_sidebar_winid(winid)
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
    content = self.render_history_content(chat_history) .. "-------\n\n" .. content
  end
  if opts.stream then
    local function scroll_to_bottom()
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
      if not Utils.is_valid_container(self.result_container) then return end
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
      if not Utils.is_valid_container(self.result_container) then return end
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
---@param selected_code AvanteSelectedCode?
---@return string
local function render_chat_record_prefix(timestamp, provider, model, request, selected_filepaths, selected_code)
  provider = provider or "unknown"
  model = model or "unknown"
  local res = "- Datetime: " .. timestamp .. "\n\n" .. "- Model: " .. provider .. "/" .. model
  if selected_filepaths ~= nil and #selected_filepaths > 0 then
    res = res .. "\n\n- Selected files:"
    for _, path in ipairs(selected_filepaths) do
      res = res .. "\n  - " .. path
    end
  end
  if selected_code ~= nil then
    res = res
      .. "\n\n- Selected code: "
      .. "\n\n```"
      .. (selected_code.file_type or "")
      .. (selected_code.path and ":" .. selected_code.path or "")
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

---@param history avante.ChatHistory
---@return string
function Sidebar.render_history_content(history)
  local added_breakline = false
  local content = ""
  for idx, entry in ipairs(history.entries) do
    if entry.visible == false then goto continue end
    if entry.reset_memory then
      content = content .. "***MEMORY RESET***\n\n"
      if idx < #history.entries and not added_breakline then
        added_breakline = true
        content = content .. "-------\n\n"
      end
      goto continue
    end
    local selected_filepaths = entry.selected_filepaths
    if not selected_filepaths and entry.selected_file ~= nil then
      selected_filepaths = { entry.selected_file.filepath }
    end
    if entry.request and entry.request ~= "" then
      if idx ~= 1 and not added_breakline then
        added_breakline = true
        content = content .. "-------\n\n"
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
    end
    if entry.response and entry.response ~= "" then
      content = content .. entry.response .. "\n\n"
      if idx < #history.entries then
        added_breakline = true
        content = content .. "-------\n\n"
      end
    else
      added_breakline = false
    end
    ::continue::
  end
  return content
end

function Sidebar:update_content_with_history()
  self:reload_chat_history()
  local content = self.render_history_content(self.chat_history)
  self:update_content(content, { ignore_history = true })
end

---@return string, integer
function Sidebar:get_content_between_separators()
  local separator = RESP_SEPARATOR
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
    chat_history.entries = {}
    Path.history.save(self.code.bufnr, chat_history)
    self:update_content(
      "Chat history cleared",
      { ignore_history = true, focus = false, scroll = false, callback = function() self:focus_input() end }
    )
    if cb then cb(args) end
  else
    self:update_content(
      "Chat history is already empty",
      { focus = false, scroll = false, callback = function() self:focus_input() end }
    )
  end
end

function Sidebar:new_chat(args, cb)
  local history = Path.history.new(self.code.bufnr)
  Path.history.save(self.code.bufnr, history)
  self:reload_chat_history()
  self:update_content(
    "New chat",
    { ignore_history = true, focus = false, scroll = false, callback = function() self:focus_input() end }
  )
  if cb then cb(args) end
end

---@param messages AvanteLLMMessage | AvanteLLMMessage[]
---@param options {visible?: boolean}
function Sidebar:add_chat_history(messages, options)
  options = options or {}
  local timestamp = get_timestamp()
  messages = vim.islist(messages) and messages or { messages }
  self:reload_chat_history()
  for _, message in ipairs(messages) do
    local content = message.content
    if message.role == "system" and type(content) == "string" then
      ---@cast content string
      self.chat_history.system_prompt = content
      goto continue
    end
    table.insert(self.chat_history.entries, {
      timestamp = timestamp,
      provider = Config.provider,
      model = Config.get_provider_config(Config.provider).model,
      request = message.role == "user" and message.content or "",
      response = message.role == "assistant" and message.content or "",
      original_response = message.role == "assistant" and message.content or "",
      selected_filepaths = nil,
      selected_code = nil,
      reset_memory = false,
      visible = options.visible,
    })
    ::continue::
  end
  Path.history.save(self.code.bufnr, self.chat_history)
  if options.visible then self:update_content_with_history() end
  if self.chat_history.title == "untitled" and #messages > 0 then
    Llm.summarize_chat_thread_title(messages[1].content, function(title)
      self:reload_chat_history()
      if title then self.chat_history.title = title end
      Path.history.save(self.code.bufnr, self.chat_history)
    end)
  end
end

function Sidebar:reset_memory(args, cb)
  local chat_history = Path.history.load(self.code.bufnr)
  if next(chat_history) ~= nil then
    table.insert(chat_history, {
      timestamp = get_timestamp(),
      provider = Config.provider,
      model = Config.get_provider_config(Config.provider).model,
      request = "",
      response = "",
      original_response = "",
      selected_file = nil,
      selected_code = nil,
      reset_memory = true,
    })
    Path.history.save(self.code.bufnr, chat_history)
    self:reload_chat_history()
    local history_content = self.render_history_content(chat_history)
    self:update_content(history_content, {
      focus = false,
      scroll = true,
      callback = function() self:focus_input() end,
    })
    if cb then cb(args) end
  else
    self:reload_chat_history()
    self:update_content(
      "Chat history is already empty",
      { focus = false, scroll = false, callback = function() self:focus_input() end }
    )
  end
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
      win_options = {
        winhighlight = base_win_options.winhighlight,
      },
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
    self:adjust_result_container_layout()
    self:adjust_selected_files_container_layout()
  end
end

local generating_text = "**Generating response ...**\n"

local hint_window = nil

function Sidebar:reload_chat_history()
  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then return end
  self.chat_history = Path.history.load(self.code.bufnr)
end

---@param opts AskOptions
function Sidebar:create_input_container(opts)
  if self.input_container then self.input_container:unmount() end

  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then return end

  if self.chat_history == nil then self:reload_chat_history() end

  ---@param request string
  ---@param summarize_memory boolean
  ---@param cb fun(opts: AvanteGeneratePromptsOptions): nil
  local function get_generate_prompts_options(request, summarize_memory, cb)
    local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })
    local file_ext = nil

    -- Get file extension safely
    local buf_name = api.nvim_buf_get_name(self.code.bufnr)
    if buf_name and buf_name ~= "" then file_ext = vim.fn.fnamemodify(buf_name, ":e") end

    ---@type AvanteSelectedCode | nil
    local selected_code = nil
    if self.code.selection ~= nil then
      selected_code = {
        path = self.code.selection.filepath,
        file_type = self.code.selection.filetype,
        content = self.code.selection.content,
      }
    end

    local mentions = Utils.extract_mentions(request)
    request = mentions.new_content

    local project_context = mentions.enable_project_context and file_ext and RepoMap.get_repo_map(file_ext) or nil

    local diagnostics = nil
    if mentions.enable_diagnostics then
      if self.code ~= nil and self.code.bufnr ~= nil and self.code.selection ~= nil then
        diagnostics = Utils.get_current_selection_diagnostics(self.code.bufnr, self.code.selection)
      else
        diagnostics = Utils.get_diagnostics(self.code.bufnr)
      end
    end

    local entries = Utils.history.filter_active_entries(self.chat_history.entries)

    if self.chat_history.memory then
      entries = vim
        .iter(entries)
        :filter(function(entry) return entry.timestamp > self.chat_history.memory.last_summarized_timestamp end)
        :totable()
    end

    local history_messages = Utils.history.entries_to_llm_messages(entries)

    local tools = vim.deepcopy(LLMTools.get_tools(request, history_messages))
    table.insert(tools, {
      name = "add_file_to_context",
      description = "Add a file to the context",
      ---@type AvanteLLMToolFunc<{ rel_path: string }>
      func = function(input)
        self.file_selector:add_selected_file(input.rel_path)
        return "Added file to context", nil
      end,
      param = {
        type = "table",
        fields = { { name = "rel_path", description = "Relative path to the file", type = "string" } },
      },
      returns = {},
    })

    table.insert(tools, {
      name = "remove_file_from_context",
      description = "Remove a file from the context",
      ---@type AvanteLLMToolFunc<{ rel_path: string }>
      func = function(input)
        self.file_selector:remove_selected_file(input.rel_path)
        return "Removed file from context", nil
      end,
      param = {
        type = "table",
        fields = { { name = "rel_path", description = "Relative path to the file", type = "string" } },
      },
      returns = {},
    })

    local mode = "planning"
    if Config.behaviour.enable_cursor_planning_mode then mode = "cursor-planning" end

    if Config.behaviour.enable_claude_text_editor_tool_mode then mode = "claude-text-editor-tool" end

    local selected_filepaths = self.file_selector.selected_filepaths or {}

    ---@type AvanteGeneratePromptsOptions
    local prompts_opts = {
      ask = (opts.ask==nil) and true or opts.ask,
      project_context = vim.json.encode(project_context),
      selected_filepaths = selected_filepaths,
      recently_viewed_files = Utils.get_recent_filepaths(),
      diagnostics = vim.json.encode(diagnostics),
      history_messages = history_messages,
      code_lang = filetype,
      selected_code = selected_code,
      instructions = request,
      mode = mode,
      tools = tools,
    }

    if self.chat_history.system_prompt then
      prompts_opts.prompt_opts = {
        system_prompt = self.chat_history.system_prompt,
        messages = {},
      }
    end

    if self.chat_history.memory then prompts_opts.memory = self.chat_history.memory.content end

    if not summarize_memory or #history_messages < 8 then
      cb(prompts_opts)
      return
    end

    prompts_opts.history_messages = vim.list_slice(prompts_opts.history_messages, 5)

    Llm.summarize_memory(self.code.bufnr, self.chat_history, nil, function(memory)
      if memory then prompts_opts.memory = memory.content end
      cb(prompts_opts)
    end)
  end

  ---@param request string
  local function handle_submit(request)
    if request:match("@codebase") and not vim.fn.expand("%:e") then
      self:update_content("Please open a file first before using @codebase", { focus = false, scroll = false })
      return
    end

    if request:sub(1, 1) == "/" then
      local command, args = request:match("^/(%S+)%s*(.*)")
      if command == nil then
        self:update_content("Invalid command", { focus = false, scroll = false })
        return
      end
      local cmds = Utils.get_commands()
      ---@type AvanteSlashCommand
      local cmd = vim.iter(cmds):filter(function(cmd) return cmd.name == command end):totable()[1]
      if cmd then
        if command == "lines" then
          cmd.callback(self, args, function(args_)
            local _, _, question = args_:match("(%d+)-(%d+)%s+(.*)")
            request = question
          end)
        elseif command == "commit" then
          cmd.callback(self, args, function(question) request = question end)
        else
          cmd.callback(self, args)
          return
        end
      else
        self:update_content("Unknown command: " .. command, { focus = false, scroll = false })
        return
      end
    end

    local model = Config.has_provider(Config.provider) and Config.get_provider_config(Config.provider).model
      or "default"

    local timestamp = get_timestamp()

    local selected_filepaths = self.file_selector:get_selected_filepaths()

    ---@type AvanteSelectedCode | nil
    local selected_code = nil
    if self.code.selection ~= nil then
      selected_code = {
        path = self.code.selection.filepath,
        file_type = self.code.selection.filetype,
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

    local original_response = ""
    local waiting_for_breakline = false
    local transformed_response = ""
    local displayed_response = ""
    local current_path = ""

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

    ---@type AvanteLLMStartCallback
    local function on_start(_) end

    ---@type AvanteLLMChunkCallback
    local function on_chunk(chunk)
      self.is_generating = true

      local remove_line = [[\033[1A\033[K]]
      if chunk:sub(1, #remove_line) == remove_line then
        chunk = chunk:sub(#remove_line + 1)
        local lines = vim.split(transformed_response, "\n")
        local idx = #lines
        while idx > 0 and lines[idx] == "" do
          idx = idx - 1
        end
        if idx == 1 then
          lines = {}
        else
          lines = vim.list_slice(lines, 1, idx - 1)
        end
        transformed_response = table.concat(lines, "\n")
      else
        original_response = original_response .. chunk
      end

      local selected_files = self.file_selector:get_selected_files_contents()

      local transformed_response_
      if waiting_for_breakline and chunk and chunk:sub(1, 1) ~= "\n" then
        transformed_response_ = transformed_response .. "\n" .. chunk
      else
        transformed_response_ = transformed_response .. chunk
      end

      local transformed = transform_result_content(selected_files, transformed_response_, current_path)
      waiting_for_breakline = transformed.waiting_for_breakline
      transformed_response = transformed.content
      if transformed.current_filepath and transformed.current_filepath ~= "" then
        current_path = transformed.current_filepath
      end
      local cur_displayed_response = generate_display_content(transformed)
      if is_first_chunk then
        is_first_chunk = false
        self:update_content(content_prefix .. chunk, { scroll = scroll })
        displayed_response = cur_displayed_response
        return
      end
      local suffix = get_display_content_suffix(transformed)
      self:update_content(content_prefix .. cur_displayed_response .. suffix, { scroll = scroll })
      vim.schedule(function() vim.cmd("redraw") end)
      displayed_response = cur_displayed_response
    end

    local tool_use_log_history = {}

    ---@param tool_id string
    ---@param tool_name string
    ---@param log string
    ---@param state AvanteLLMToolUseState
    local function on_tool_log(tool_id, tool_name, log, state)
      if state == "generating" then
        if tool_use_log_history[tool_id] then return end
        tool_use_log_history[tool_id] = true
      end
      if transformed_response:sub(-1) ~= "\n" then transformed_response = transformed_response .. "\n" end
      transformed_response = transformed_response .. "[" .. tool_name .. "]: " .. log .. "\n"
      local breakline = ""
      if displayed_response:sub(-1) ~= "\n" then breakline = "\n" end
      displayed_response = displayed_response .. breakline .. "[" .. tool_name .. "]: " .. log .. "\n"
      self:update_content(content_prefix .. displayed_response, {
        scroll = scroll,
      })
    end

    ---@param tool_use AvantePartialLLMToolUse
    local function on_partial_tool_use(tool_use)
      if not tool_use.name then return end
      if not tool_use.id then return end
      on_tool_log(tool_use.id, tool_use.name, "calling...", tool_use.state)
    end

    ---@type AvanteLLMStopCallback
    local function on_stop(stop_opts)
      self.is_generating = false

      pcall(function()
        ---remove keymaps
        vim.keymap.del("n", "j", { buffer = self.result_container.bufnr })
        vim.keymap.del("n", "k", { buffer = self.result_container.bufnr })
        vim.keymap.del("n", "G", { buffer = self.result_container.bufnr })
      end)

      if stop_opts.error ~= nil then
        self:update_content(
          content_prefix .. displayed_response .. "\n\nError: " .. vim.inspect(stop_opts.error),
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
        if Utils.is_valid_container(self.result_container, true) and Config.behaviour.jump_result_buffer_on_finish then
          api.nvim_set_current_win(self.result_container.winid)
        end
        if Config.behaviour.auto_apply_diff_after_generation then self:apply(false) end
      end, 0)

      -- Save chat history
      self.chat_history.entries = self.chat_history.entries or {}
      table.insert(self.chat_history.entries, {
        timestamp = timestamp,
        provider = Config.provider,
        model = model,
        request = request,
        response = displayed_response,
        original_response = original_response,
        selected_filepaths = selected_filepaths,
        selected_code = selected_code,
        tool_histories = stop_opts.tool_histories,
      })
      if self.chat_history.title == "untitled" then
        Llm.summarize_chat_thread_title(request, function(title)
          if title then self.chat_history.title = title end
          Path.history.save(self.code.bufnr, self.chat_history)
        end)
      else
        Path.history.save(self.code.bufnr, self.chat_history)
      end
    end

    get_generate_prompts_options(request, true, function(generate_prompts_options)
      ---@type AvanteLLMStreamOptions
      ---@diagnostic disable-next-line: assign-type-mismatch
      local stream_options = vim.tbl_deep_extend("force", generate_prompts_options, {
        on_start = on_start,
        on_chunk = on_chunk,
        on_stop = on_stop,
        on_tool_log = on_tool_log,
        on_partial_tool_use = on_partial_tool_use,
        session_ctx = {},
      })

      local function on_memory_summarize(dropped_history_messages)
        local entries = Utils.history.filter_active_entries(self.chat_history.entries)

        if self.chat_history.memory then
          entries = vim
            .iter(entries)
            :filter(function(entry) return entry.timestamp > self.chat_history.memory.last_summarized_timestamp end)
            :totable()
        end

        entries = vim.list_slice(entries, 1, #dropped_history_messages)

        Llm.summarize_memory(self.code.bufnr, self.chat_history, entries, function(memory)
          if memory then stream_options.memory = memory.content end
          stream_options.history_messages =
            vim.list_slice(stream_options.history_messages, #dropped_history_messages + 1)
          Llm.stream(stream_options)
        end)
      end

      stream_options.on_memory_summarize = on_memory_summarize

      Llm.stream(stream_options)
    end)
  end

  local function get_position()
    if self:get_layout() == "vertical" then return "bottom" end
    return "right"
  end

  local function get_size()
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
    if not Utils.is_valid_container(self.input_container) then return end
    local lines = api.nvim_buf_get_lines(self.input_container.bufnr, 0, -1, false)
    local request = table.concat(lines, "\n")
    if request == "" then return end
    api.nvim_buf_set_lines(self.input_container.bufnr, 0, -1, false, {})
    api.nvim_win_set_cursor(self.input_container.winid, { 1, 0 })
    handle_submit(request)
  end

  self.handle_submit = handle_submit

  self.input_container:mount()

  local function place_sign_at_first_line(bufnr)
    local group = "avante_input_prompt_group"

    fn.sign_unplace(group, { buffer = bufnr })

    fn.sign_place(0, group, "AvanteInputPromptSign", bufnr, { lnum = 1 })
  end

  place_sign_at_first_line(self.input_container.bufnr)

  if Utils.in_visual_mode() then
    -- Exit visual mode
    vim.cmd("noautocmd stopinsert")
  end

  self.input_container:map("n", Config.mappings.submit.normal, on_submit)
  self.input_container:map("i", Config.mappings.submit.insert, on_submit)

  if Config.mappings.sidebar.close_from_input ~= nil then
    if Config.mappings.sidebar.close_from_input.normal ~= nil then
      self.input_container:map("n", Config.mappings.sidebar.close_from_input.normal, function() self:shutdown() end)
    end
    if Config.mappings.sidebar.close_from_input.insert ~= nil then
      self.input_container:map("i", Config.mappings.sidebar.close_from_input.insert, function() self:shutdown() end)
    end
  end

  api.nvim_set_option_value("filetype", "AvanteInput", { buf = self.input_container.bufnr })

  -- Setup completion
  api.nvim_create_autocmd("InsertEnter", {
    group = self.augroup,
    buffer = self.input_container.bufnr,
    once = true,
    desc = "Setup the completion of helpers in the input buffer",
    callback = function() end,
  })

  local hint_ns_id = api.nvim_create_namespace("avante_hint")

  -- Close the floating window
  local function close_hint()
    if hint_window and api.nvim_win_is_valid(hint_window) then
      local buf = api.nvim_win_get_buf(hint_window)
      if hint_ns_id then api.nvim_buf_clear_namespace(buf, hint_ns_id, 0, -1) end
      api.nvim_win_close(hint_window, true)
      api.nvim_buf_delete(buf, { force = true })
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

    local hint_text = (fn.mode() ~= "i" and Config.mappings.submit.normal or Config.mappings.submit.insert)
      .. ": submit"

    local function show()
      local buf = api.nvim_create_buf(false, true)
      api.nvim_buf_set_lines(buf, 0, -1, false, { hint_text })
      api.nvim_buf_set_extmark(buf, hint_ns_id, 0, 0, { hl_group = "AvantePopupHint", end_col = #hint_text })

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

    if Config.behaviour.enable_token_counting then
      local input_value = table.concat(api.nvim_buf_get_lines(self.input_container.bufnr, 0, -1, false), "\n")
      get_generate_prompts_options(input_value, false, function(generate_prompts_options)
        local tokens = Llm.calculate_tokens(generate_prompts_options)
        hint_text = "Tokens: " .. tostring(tokens) .. "; " .. hint_text
        show()
      end)
    else
      show()
    end
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

  api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    callback = function(args)
      local closed_winid = tonumber(args.match)
      if closed_winid == self.input_container.winid then close_hint() end
    end,
  })

  api.nvim_create_autocmd("BufEnter", {
    group = self.augroup,
    buffer = self.input_container.bufnr,
    callback = function()
      if Config.windows.ask.start_insert then vim.cmd("noautocmd startinsert!") end
    end,
  })

  api.nvim_create_autocmd("BufLeave", {
    group = self.augroup,
    buffer = self.input_container.bufnr,
    callback = function() vim.cmd("noautocmd stopinsert") end,
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
    group = self.augroup,
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

---@param value string
function Sidebar:set_input_value(value)
  if not self.input_container then return end
  if not value then return end
  api.nvim_buf_set_lines(self.input_container.bufnr, 0, -1, false, vim.split(value, "\n"))
end

---@return string
function Sidebar:get_input_value()
  if not self.input_container then return "" end
  local lines = api.nvim_buf_get_lines(self.input_container.bufnr, 0, -1, false)
  return table.concat(lines, "\n")
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

function Sidebar:get_selected_files_size()
  if not self.file_selector then return 0 end

  local selected_files_max_lines_count = 10

  local selected_files = self.file_selector:get_selected_filepaths()
  local selected_files_size = #selected_files
  selected_files_size = math.min(selected_files_size, selected_files_max_lines_count)

  return selected_files_size
end

function Sidebar:get_result_container_height()
  local selected_code_size = self:get_selected_code_size()
  local selected_files_size = self:get_selected_files_size()

  if self:get_layout() == "horizontal" then return math.floor(Config.windows.height / 100 * vim.o.lines) end

  return math.max(1, api.nvim_win_get_height(self.code.winid) - selected_files_size - selected_code_size - 3 - 8)
end

function Sidebar:get_result_container_width()
  if self:get_layout() == "vertical" then return math.floor(Config.windows.width / 100 * vim.o.columns) end

  return math.max(1, api.nvim_win_get_width(self.code.winid))
end

function Sidebar:adjust_result_container_layout()
  local height = self:get_result_container_height()

  api.nvim_win_set_height(self.result_container.winid, height)
end

---@param opts AskOptions
function Sidebar:render(opts)
  local function get_position()
    return (opts and opts.win and opts.win.position) and opts.win.position or calculate_config_window_position()
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
      fillchars = Config.windows.fillchars,
    }),
    size = {
      width = self:get_result_container_width(),
      height = self:get_result_container_height(),
    },
  })

  self.result_container:mount()

  self.augroup = api.nvim_create_augroup("avante_sidebar_" .. self.id .. self.result_container.winid, { clear = true })

  self.result_container:on(event.BufWinEnter, function()
    xpcall(function() api.nvim_buf_set_name(self.result_container.bufnr, RESULT_BUF_NAME) end, function(_) end)
  end)

  self.result_container:map("n", Config.mappings.sidebar.close, function() self:shutdown() end)

  self:create_input_container(opts)

  self:create_selected_files_container()

  self:update_content_with_history()

  -- reset states when buffer is closed
  api.nvim_buf_attach(self.code.bufnr, false, {
    on_detach = function(_, _)
      vim.schedule(function()
        local bufnr = api.nvim_win_get_buf(self.code.winid)
        self.code.bufnr = bufnr
        self:reload_chat_history()
      end)
    end,
  })

  self:create_selected_code_container()

  self:on_mount(opts)

  self:setup_colors()

  return self
end

function Sidebar:get_selected_files_container_height()
  local selected_filepaths_ = self.file_selector:get_selected_filepaths()
  return math.min(vim.o.lines - 2, #selected_filepaths_ + 1)
end

function Sidebar:adjust_selected_files_container_layout()
  if not Utils.is_valid_container(self.selected_files_container, true) then return end

  local win_height = self:get_selected_files_container_height()
  api.nvim_win_set_height(self.selected_files_container.winid, win_height)
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
      fillchars = Config.windows.fillchars,
    }),
    position = "top",
    size = {
      width = "40%",
      height = 2,
    },
  })

  self.selected_files_container:mount()

  local function render()
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
    local win_height = self:get_selected_files_container_height()
    api.nvim_win_set_height(self.selected_files_container.winid, win_height)
    self:render_header(
      self.selected_files_container.winid,
      selected_files_buf,
      Utils.icon(" ") .. "Selected Files",
      Highlights.SUBTITLE,
      Highlights.REVERSED_SUBTITLE
    )
    self:adjust_result_container_layout()
  end

  self.file_selector:on("update", render)

  local function remove_file(line_number) self.file_selector:remove_selected_filepaths_with_index(line_number) end

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
