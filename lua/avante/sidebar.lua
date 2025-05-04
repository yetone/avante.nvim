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
local HistoryMessage = require("avante.history_message")
local Line = require("avante.ui.line")

local RESULT_BUF_NAME = "AVANTE_RESULT"
local VIEW_BUFFER_UPDATED_PATTERN = "AvanteViewBufferUpdated"
local CODEBLOCK_KEYBINDING_NAMESPACE = api.nvim_create_namespace("AVANTE_CODEBLOCK_KEYBINDING")
local USER_REQUEST_BLOCK_KEYBINDING_NAMESPACE = api.nvim_create_namespace("AVANTE_USER_REQUEST_BLOCK_KEYBINDING")
local SELECTED_FILES_HINT_NAMESPACE = api.nvim_create_namespace("AVANTE_SELECTED_FILES_HINT")
local SELECTED_FILES_ICON_NAMESPACE = api.nvim_create_namespace("AVANTE_SELECTED_FILES_ICON")
local INPUT_HINT_NAMESPACE = api.nvim_create_namespace("AVANTE_INPUT_HINT")
local STATE_NAMESPACE = api.nvim_create_namespace("AVANTE_STATE")
local RESULT_BUF_HL_NAMESPACE = api.nvim_create_namespace("AVANTE_RESULT_BUF_HL")

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
---@field current_state avante.GenerateState | nil
---@field state_timer table | nil
---@field state_spinner_chars string[]
---@field state_spinner_idx integer
---@field state_extmark_id integer | nil
---@field scroll boolean
---@field input_hint_window integer | nil
---@field ask_opts AskOptions
---@field old_result_lines avante.ui.Line[]

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
    current_state = nil,
    state_timer = nil,
    state_spinner_chars = { "·", "✢", "✳", "∗", "✻", "✽" },
    state_spinner_idx = 1,
    state_extmark_id = nil,
    scroll = true,
    input_hint_window = nil,
    ask_opts = {},
    old_result_lines = {},
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
  self.scroll = true
  self.old_result_lines = {}
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
  if not self.code.winid or not api.nvim_win_is_valid(self.code.winid) then return end

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

---@param result_content string
---@param prev_filepath string
---@return AvanteReplacementResult
local function transform_result_content(result_content, prev_filepath)
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

      if filepath == "" then goto continue end

      local file_content = Utils.read_file_from_buf_or_disk(filepath) or {}
      local file_type = Utils.get_filetype(filepath)
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
          match_filetype = file_type
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
local function parse_codeblocks(buf)
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
      valid = lines[start_line - 1]:match("^%s*(%d*)[%.%)%s]*[Aa]?n?d?%s*[Rr]eplace%s+[Ll]ines:?%s*(%d+)%-(%d+)")
        ~= nil
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

  if self.code.bufnr and api.nvim_buf_is_valid(self.code.bufnr) then
    api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
      group = self.augroup,
      buffer = self.result_container.bufnr,
      callback = function(ev)
        codeblocks = parse_codeblocks(ev.buf)
        self:bind_sidebar_keys(codeblocks)
      end,
    })

    api.nvim_create_autocmd("User", {
      group = self.augroup,
      pattern = VIEW_BUFFER_UPDATED_PATTERN,
      callback = function()
        if not Utils.is_valid_container(self.result_container) then return end
        codeblocks = parse_codeblocks(self.result_container.bufnr)
        self:bind_sidebar_keys(codeblocks)
      end,
    })
  end

  api.nvim_create_autocmd("BufLeave", {
    group = self.augroup,
    buffer = self.result_container.bufnr,
    callback = function() self:unbind_sidebar_keys() end,
  })

  self:render_result()
  self:render_input(opts.ask)
  self:render_selected_code()

  if self.selected_code_container ~= nil then
    local selected_code_buf = self.selected_code_container.bufnr
    if selected_code_buf ~= nil then
      if self.code.selection ~= nil then
        Utils.unlock_buf(selected_code_buf)
        local lines = vim.split(self.code.selection.content, "\n")
        api.nvim_buf_set_lines(selected_code_buf, 0, -1, false, lines)
        Utils.lock_buf(selected_code_buf)
      end
      if self.code.bufnr and api.nvim_buf_is_valid(self.code.bufnr) then
        local filetype = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })
        api.nvim_set_option_value("filetype", filetype, { buf = selected_code_buf })
      end
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

  -- check if the filetype of self.code.bufnr is disabled
  local buf_ft = api.nvim_get_option_value("filetype", { buf = self.code.bufnr })
  if vim.list_contains(Config.selector.exclude_auto_select, buf_ft) then return self end

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

---@param content string concatenated content of the buffer
---@param opts? {focus?: boolean, scroll?: boolean, backspace?: integer, callback?: fun(): nil} whether to focus the result view
function Sidebar:update_content(content, opts)
  if not self.result_container or not self.result_container.bufnr then return end
  opts = vim.tbl_deep_extend("force", { focus = false, scroll = self.scroll, callback = nil }, opts or {})
  local history_lines = self.get_history_lines(self.chat_history)
  if content ~= nil and content ~= "" then
    table.insert(history_lines, Line:new({ { "" } }))
    local content_lines = vim.split(content, "\n")
    for _, line in ipairs(content_lines) do
      table.insert(history_lines, Line:new({ { line } }))
    end
  end
  vim.defer_fn(function()
    self:clear_state()
    local f = function()
      if not Utils.is_valid_container(self.result_container) then return end
      Utils.unlock_buf(self.result_container.bufnr)
      Utils.update_buffer_lines(
        RESULT_BUF_HL_NAMESPACE,
        self.result_container.bufnr,
        self.old_result_lines,
        history_lines
      )
      Utils.lock_buf(self.result_container.bufnr)
      self.old_result_lines = history_lines
      api.nvim_set_option_value("filetype", "Avante", { buf = self.result_container.bufnr })
      vim.schedule(function() vim.cmd("redraw") end)
      if opts.focus and not self:is_focused_on_result() then
        --- set cursor to bottom of result view
        xpcall(function() api.nvim_set_current_win(self.result_container.winid) end, function(err) return err end)
      end

      if opts.scroll then Utils.buf_scroll_to_end(self.result_container.bufnr) end

      if opts.callback ~= nil then opts.callback() end
    end
    f()
    self:render_state()
  end, 0)
  return self
end

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
      .. (selected_code.path and " " .. selected_code.path or "")
      .. "\n"
      .. selected_code.content
      .. "\n```"
  end

  return res .. "\n\n> " .. request:gsub("\n", "\n> "):gsub("([%w-_]+)%b[]", "`%0`")
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

---@param message avante.HistoryMessage
---@param messages avante.HistoryMessage[]
---@param ctx table
---@return avante.ui.Line[]
local function get_message_lines(message, messages, ctx)
  if message.visible == false then return {} end
  local lines = Utils.message_to_lines(message, messages)
  if message.is_user_submission then
    ctx.selected_filepaths = message.selected_filepaths
    local text = table.concat(vim.tbl_map(function(line) return tostring(line) end, lines), "\n")
    local prefix = render_chat_record_prefix(
      message.timestamp,
      message.provider,
      message.model,
      text,
      message.selected_filepaths,
      message.selected_code
    )
    local res = {}
    for _, line_ in ipairs(vim.split(prefix, "\n")) do
      table.insert(res, Line:new({ { line_ } }))
    end
    return res
  end
  if message.message.role == "user" then
    local res = {}
    for _, line_ in ipairs(lines) do
      local sections = { { "> " } }
      sections = vim.list_extend(sections, line_.sections)
      table.insert(res, Line:new(sections))
    end
    return res
  end
  if message.message.role == "assistant" then
    local content = message.message.content
    if type(content) == "table" and content[1].type == "tool_use" then return lines end
    local text = table.concat(vim.tbl_map(function(line) return tostring(line) end, lines), "\n")
    local transformed = transform_result_content(text, ctx.prev_filepath)
    ctx.prev_filepath = transformed.current_filepath
    local displayed_content = generate_display_content(transformed)
    local res = {}
    for _, line_ in ipairs(vim.split(displayed_content, "\n")) do
      table.insert(res, Line:new({ { line_ } }))
    end
    return res
  end
  return lines
end

---@param history avante.ChatHistory
---@return avante.ui.Line[]
function Sidebar.get_history_lines(history)
  local history_messages = Utils.get_history_messages(history)
  local ctx = {}
  ---@type avante.ui.Line[][]
  local group = {}
  for _, message in ipairs(history_messages) do
    local lines = get_message_lines(message, history_messages, ctx)
    if #lines == 0 then goto continue end
    if message.is_user_submission then table.insert(group, {}) end
    local last_item = group[#group]
    if last_item == nil then
      table.insert(group, {})
      last_item = group[#group]
    end
    if message.message.role == "assistant" and not message.just_for_display and tostring(lines[1]) ~= "" then
      table.insert(lines, 1, Line:new({ { "" } }))
      table.insert(lines, 1, Line:new({ { "" } }))
    end
    last_item = vim.list_extend(last_item, lines)
    group[#group] = last_item
    ::continue::
  end
  local res = {}
  for idx, item in ipairs(group) do
    if idx ~= 1 then
      res = vim.list_extend(res, { Line:new({ { "" } }), Line:new({ { RESP_SEPARATOR } }), Line:new({ { "" } }) })
    end
    res = vim.list_extend(res, item)
  end
  table.insert(res, Line:new({ { "" } }))
  return res
end

---@param message avante.HistoryMessage
---@param messages avante.HistoryMessage[]
---@param ctx table
---@return string | nil
local function render_message(message, messages, ctx)
  if message.visible == false then return nil end
  local text = Utils.message_to_text(message, messages)
  if text == "" then return nil end
  if message.is_user_submission then
    ctx.selected_filepaths = message.selected_filepaths
    local prefix = render_chat_record_prefix(
      message.timestamp,
      message.provider,
      message.model,
      text,
      message.selected_filepaths,
      message.selected_code
    )
    return prefix
  end
  if message.message.role == "user" then
    local lines = vim.split(text, "\n")
    lines = vim.iter(lines):map(function(line) return "> " .. line end):totable()
    text = table.concat(lines, "\n")
    return text
  end
  if message.message.role == "assistant" then
    local transformed = transform_result_content(text, ctx.prev_filepath)
    ctx.prev_filepath = transformed.current_filepath
    local displayed_content = generate_display_content(transformed)
    return displayed_content
  end
  return ""
end

---@param history avante.ChatHistory
---@return string
function Sidebar.render_history_content(history)
  local history_messages = Utils.get_history_messages(history)
  local ctx = {}
  local group = {}
  for _, message in ipairs(history_messages) do
    local text = render_message(message, history_messages, ctx)
    if text == nil then goto continue end
    if message.is_user_submission then table.insert(group, {}) end
    local last_item = group[#group]
    if last_item == nil then
      table.insert(group, {})
      last_item = group[#group]
    end
    if message.message.role == "assistant" and not message.just_for_display and text:sub(1, 2) ~= "\n\n" then
      text = "\n\n" .. text
    end
    table.insert(last_item, text)
    ::continue::
  end
  local pieces = {}
  for _, item in ipairs(group) do
    table.insert(pieces, table.concat(item, ""))
  end
  return table.concat(pieces, "\n\n" .. RESP_SEPARATOR .. "\n\n") .. "\n\n"
end

function Sidebar:update_content_with_history()
  self:reload_chat_history()
  self:update_content("")
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
  self.current_state = nil
  local chat_history = Path.history.load(self.code.bufnr)
  if next(chat_history) ~= nil then
    chat_history.messages = {}
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

function Sidebar:clear_state()
  if self.state_extmark_id then
    pcall(api.nvim_buf_del_extmark, self.result_container.bufnr, STATE_NAMESPACE, self.state_extmark_id)
  end
  self.state_extmark_id = nil
  self.state_spinner_idx = 1
  if self.state_timer then self.state_timer:stop() end
end

function Sidebar:render_state()
  if not Utils.is_valid_container(self.result_container) then return end
  if not self.current_state then return end
  local lines = vim.api.nvim_buf_get_lines(self.result_container.bufnr, 0, -1, false)
  if self.state_extmark_id then
    api.nvim_buf_del_extmark(self.result_container.bufnr, STATE_NAMESPACE, self.state_extmark_id)
  end
  local spinner_char = self.state_spinner_chars[self.state_spinner_idx]
  self.state_spinner_idx = (self.state_spinner_idx % #self.state_spinner_chars) + 1
  local hl = "AvanteStateSpinnerGenerating"
  if self.current_state == "tool calling" then hl = "AvanteStateSpinnerToolCalling" end
  if self.current_state == "failed" then hl = "AvanteStateSpinnerFailed" end
  if self.current_state == "succeeded" then hl = "AvanteStateSpinnerSucceeded" end
  if self.current_state == "searching" then hl = "AvanteStateSpinnerSearching" end
  if self.current_state == "thinking" then hl = "AvanteStateSpinnerThinking" end
  if self.current_state ~= "generating" and self.current_state ~= "tool calling" then spinner_char = "" end
  local virt_line
  if spinner_char == "" then
    virt_line = " " .. self.current_state .. " "
  else
    virt_line = " " .. spinner_char .. " " .. self.current_state .. " "
  end

  local win_width = api.nvim_win_get_width(self.result_container.winid)
  local padding = math.floor((win_width - vim.fn.strdisplaywidth(virt_line)) / 2)
  local centered_virt_lines = {
    { { string.rep(" ", padding) }, { virt_line, hl } },
  }

  local line_num = math.max(0, #lines - 2)
  self.state_extmark_id = api.nvim_buf_set_extmark(self.result_container.bufnr, STATE_NAMESPACE, line_num, 0, {
    virt_lines = centered_virt_lines,
    hl_eol = true,
    hl_mode = "combine",
  })
  self.state_timer = vim.defer_fn(function() self:render_state() end, 160)
end

function Sidebar:new_chat(args, cb)
  local history = Path.history.new(self.code.bufnr)
  Path.history.save(self.code.bufnr, history)
  self:reload_chat_history()
  self.current_state = nil
  self:update_content("New chat", { focus = false, scroll = false, callback = function() self:focus_input() end })
  if cb then cb(args) end
end

---@param messages avante.HistoryMessage | avante.HistoryMessage[]
function Sidebar:add_history_messages(messages)
  local history_messages = Utils.get_history_messages(self.chat_history)
  messages = vim.islist(messages) and messages or { messages }
  for _, message in ipairs(messages) do
    if message.is_user_submission then
      message.provider = Config.provider
      message.model = Config.get_provider_config(Config.provider).model
    end
    local idx = nil
    for idx_, message_ in ipairs(history_messages) do
      if message_.uuid == message.uuid then
        idx = idx_
        break
      end
    end
    if idx ~= nil then
      history_messages[idx] = message
    else
      table.insert(history_messages, message)
    end
  end
  self.chat_history.messages = history_messages
  Path.history.save(self.code.bufnr, self.chat_history)
  if self.chat_history.title == "untitled" and #messages > 0 then
    Llm.summarize_chat_thread_title(messages[1].message.content, function(title)
      self:reload_chat_history()
      if title then self.chat_history.title = title end
      Path.history.save(self.code.bufnr, self.chat_history)
    end)
  end
  local last_message = messages[#messages]
  if last_message then
    local content = last_message.message.content
    if type(content) == "table" and content[1].type == "tool_use" then
      self.current_state = "tool calling"
    elseif type(content) == "table" and content[1].type == "thinking" then
      self.current_state = "thinking"
    elseif type(content) == "table" and content[1].type == "redacted_thinking" then
      self.current_state = "thinking"
    else
      self.current_state = "generating"
    end
  end
  self:update_content("")
end

---@param messages AvanteLLMMessage | AvanteLLMMessage[]
---@param options {visible?: boolean}
function Sidebar:add_chat_history(messages, options)
  options = options or {}
  messages = vim.islist(messages) and messages or { messages }
  self:reload_chat_history()
  local is_first_user = true
  local history_messages = {}
  for _, message in ipairs(messages) do
    local content = message.content
    if message.role == "system" and type(content) == "string" then
      ---@cast content string
      self.chat_history.system_prompt = content
      goto continue
    end
    local history_message = HistoryMessage:new(message)
    if message.role == "user" and is_first_user then
      is_first_user = false
      history_message.is_user_submission = true
      history_message.provider = Config.provider
      history_message.model = Config.get_provider_config(Config.provider).model
    end
    table.insert(history_messages, history_message)
    ::continue::
  end
  if options.visible ~= nil then
    for _, history_message in ipairs(history_messages) do
      history_message.visible = options.visible
    end
  end
  self:add_history_messages(history_messages)
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

function Sidebar:close_input_hint()
  if self.input_hint_window and api.nvim_win_is_valid(self.input_hint_window) then
    local buf = api.nvim_win_get_buf(self.input_hint_window)
    if INPUT_HINT_NAMESPACE then api.nvim_buf_clear_namespace(buf, INPUT_HINT_NAMESPACE, 0, -1) end
    api.nvim_win_close(self.input_hint_window, true)
    api.nvim_buf_delete(buf, { force = true })
    self.input_hint_window = nil
  end
end

function Sidebar:get_input_float_window_row()
  local win_height = api.nvim_win_get_height(self.input_container.winid)
  local winline = Utils.winline(self.input_container.winid)
  if winline >= win_height - 1 then return 0 end
  return winline
end

-- Create a floating window as a hint
function Sidebar:show_input_hint()
  self:close_input_hint() -- Close the existing hint window

  local hint_text = (fn.mode() ~= "i" and Config.mappings.submit.normal or Config.mappings.submit.insert) .. ": submit"

  local function show()
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, { hint_text })
    api.nvim_buf_set_extmark(buf, INPUT_HINT_NAMESPACE, 0, 0, { hl_group = "AvantePopupHint", end_col = #hint_text })

    -- Get the current window size
    local win_width = api.nvim_win_get_width(self.input_container.winid)
    local width = #hint_text

    -- Set the floating window options
    local win_opts = {
      relative = "win",
      win = self.input_container.winid,
      width = width,
      height = 1,
      row = self:get_input_float_window_row(),
      col = math.max(win_width - width, 0), -- Display in the bottom right corner
      style = "minimal",
      border = "none",
      focusable = false,
      zindex = 100,
    }

    -- Create the floating window
    self.input_hint_window = api.nvim_open_win(buf, false, win_opts)
  end

  if Config.behaviour.enable_token_counting then
    local input_value = table.concat(api.nvim_buf_get_lines(self.input_container.bufnr, 0, -1, false), "\n")
    self:get_generate_prompts_options(input_value, function(generate_prompts_options)
      local tokens = Llm.calculate_tokens(generate_prompts_options) + Utils.tokens.calculate_tokens(input_value)
      hint_text = "Tokens: " .. tostring(tokens) .. "; " .. hint_text
      show()
    end)
  else
    show()
  end
end

function Sidebar:close_selected_files_hint()
  if self.selected_files_container and api.nvim_win_is_valid(self.selected_files_container.winid) then
    pcall(api.nvim_buf_clear_namespace, self.selected_files_container.bufnr, SELECTED_FILES_HINT_NAMESPACE, 0, -1)
  end
end

function Sidebar:show_selected_files_hint()
  self:close_selected_files_hint()

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

function Sidebar:reload_chat_history()
  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then return end
  self.chat_history = Path.history.load(self.code.bufnr)
end

---@return avante.HistoryMessage[]
function Sidebar:get_history_messages_for_api()
  local history_messages = Utils.get_history_messages(self.chat_history)
  self.chat_history.messages = history_messages

  if self.chat_history.memory then
    history_messages = {}
    for i = #self.chat_history.messages, 1, -1 do
      local message = self.chat_history.messages[i]
      if message.uuid == self.chat_history.memory.last_message_uuid then break end
      table.insert(history_messages, 1, message)
    end
  end
  return vim.iter(history_messages):filter(function(message) return not message.just_for_display end):totable()
end

---@param request string
---@param cb fun(opts: AvanteGeneratePromptsOptions): nil
function Sidebar:get_generate_prompts_options(request, cb)
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

  local history_messages = self:get_history_messages_for_api()

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

  local selected_filepaths = self.file_selector.selected_filepaths or {}

  ---@type AvanteGeneratePromptsOptions
  local prompts_opts = {
    ask = self.ask_opts.ask or true,
    project_context = vim.json.encode(project_context),
    selected_filepaths = selected_filepaths,
    recently_viewed_files = Utils.get_recent_filepaths(),
    diagnostics = vim.json.encode(diagnostics),
    history_messages = history_messages,
    code_lang = filetype,
    selected_code = selected_code,
    -- instructions = request,
    tools = tools,
  }

  if self.chat_history.system_prompt then
    prompts_opts.prompt_opts = {
      system_prompt = self.chat_history.system_prompt,
      messages = history_messages,
    }
  end

  if self.chat_history.memory then prompts_opts.memory = self.chat_history.memory.content end

  cb(prompts_opts)
end

function Sidebar:create_input_container()
  if self.input_container then self.input_container:unmount() end

  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then return end

  if self.chat_history == nil then self:reload_chat_history() end

  ---@param request string
  local function handle_submit(request)
    if self.is_generating then
      self:add_history_messages({
        HistoryMessage:new({ role = "user", content = request }),
      })
      return
    end
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

    -- local model = Config.has_provider(Config.provider) and Config.get_provider_config(Config.provider).model
    --   or "default"
    --
    -- local timestamp = Utils.get_timestamp()

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

    --- HACK: we need to set focus to true and scroll to false to
    --- prevent the cursor from jumping to the bottom of the
    --- buffer at the beginning
    self:update_content("", { focus = true, scroll = false })

    ---stop scroll when user presses j/k keys
    local function on_j()
      self.scroll = false
      ---perform scroll
      vim.cmd("normal! j")
    end

    local function on_k()
      self.scroll = false
      ---perform scroll
      vim.cmd("normal! k")
    end

    local function on_G()
      self.scroll = true
      ---perform scroll
      vim.cmd("normal! G")
    end

    vim.keymap.set("n", "j", on_j, { buffer = self.result_container.bufnr })
    vim.keymap.set("n", "k", on_k, { buffer = self.result_container.bufnr })
    vim.keymap.set("n", "G", on_G, { buffer = self.result_container.bufnr })

    ---@type AvanteLLMStartCallback
    local function on_start(_) end

    ---@param messages avante.HistoryMessage[]
    local function on_messages_add(messages) self:add_history_messages(messages) end

    ---@param state avante.GenerateState
    local function on_state_change(state)
      self:clear_state()
      self.current_state = state
      self:render_state()
    end

    local save_history = Utils.debounce(function() Path.history.save(self.code.bufnr, self.chat_history) end, 3000)

    ---@param tool_id string
    ---@param tool_name string
    ---@param log string
    ---@param state AvanteLLMToolUseState
    local function on_tool_log(tool_id, tool_name, log, state)
      if state == "generating" then on_state_change("tool calling") end
      local tool_use_message = nil
      for idx = #self.chat_history.messages, 1, -1 do
        local message = self.chat_history.messages[idx]
        local content = message.message.content
        if type(content) == "table" and content[1].type == "tool_use" and content[1].id == tool_id then
          tool_use_message = message
          break
        end
      end
      if not tool_use_message then
        Utils.debug("tool_use message not found", tool_id, tool_name)
        return
      end
      local tool_use_logs = tool_use_message.tool_use_logs or {}
      local content = string.format("[%s]: %s", tool_name, log)
      table.insert(tool_use_logs, content)
      tool_use_message.tool_use_logs = tool_use_logs
      save_history()
      self:update_content("")
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
        local msg_content = stop_opts.error
        if type(msg_content) ~= "string" then msg_content = vim.inspect(msg_content) end
        self:add_history_messages({
          HistoryMessage:new({
            role = "assistant",
            content = "\n\nError: " .. msg_content,
          }, {
            just_for_display = true,
          }),
        })
        on_state_change("failed")
        return
      end

      on_state_change("succeeded")

      self:update_content("", {
        callback = function() api.nvim_exec_autocmds("User", { pattern = VIEW_BUFFER_UPDATED_PATTERN }) end,
      })

      vim.defer_fn(function()
        if Utils.is_valid_container(self.result_container, true) and Config.behaviour.jump_result_buffer_on_finish then
          api.nvim_set_current_win(self.result_container.winid)
        end
        if Config.behaviour.auto_apply_diff_after_generation then self:apply(false) end
      end, 0)

      if self.chat_history.title == "untitled" then
        Llm.summarize_chat_thread_title(request, function(title)
          if title then self.chat_history.title = title end
          Path.history.save(self.code.bufnr, self.chat_history)
        end)
      else
        Path.history.save(self.code.bufnr, self.chat_history)
      end
    end

    if request and request ~= "" then
      self:add_history_messages({
        HistoryMessage:new({
          role = "user",
          content = request,
        }, {
          is_user_submission = true,
          selected_filepaths = selected_filepaths,
          selected_code = selected_code,
        }),
      })
    end

    self:get_generate_prompts_options(request, function(generate_prompts_options)
      ---@type AvanteLLMStreamOptions
      ---@diagnostic disable-next-line: assign-type-mismatch
      local stream_options = vim.tbl_deep_extend("force", generate_prompts_options, {
        on_start = on_start,
        on_stop = on_stop,
        on_tool_log = on_tool_log,
        on_messages_add = on_messages_add,
        on_state_change = on_state_change,
        get_history_messages = function() return self:get_history_messages_for_api() end,
        session_ctx = {},
      })

      ---@param dropped_history_messages avante.HistoryMessage[]
      local function on_memory_summarize(dropped_history_messages)
        local history_memory = self.chat_history.memory
        Llm.summarize_memory(history_memory and history_memory.content, dropped_history_messages, function(memory)
          if memory then
            self.chat_history.memory = memory
            Path.history.save(self.code.bufnr, self.chat_history)
            stream_options.memory = memory.content
          end
          stream_options.history_messages = self:get_history_messages_for_api()
          Llm.stream(stream_options)
        end)
      end

      stream_options.on_memory_summarize = on_memory_summarize

      on_state_change("generating")
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

  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "VimResized" }, {
    group = self.augroup,
    buffer = self.input_container.bufnr,
    callback = function()
      self:show_input_hint()
      place_sign_at_first_line(self.input_container.bufnr)
    end,
  })

  api.nvim_create_autocmd("QuitPre", {
    group = self.augroup,
    buffer = self.input_container.bufnr,
    callback = function() self:close_input_hint() end,
  })

  api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    callback = function(args)
      local closed_winid = tonumber(args.match)
      if closed_winid == self.input_container.winid then self:close_input_hint() end
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
      if self.input_container and cur_buf == self.input_container.bufnr then self:show_input_hint() end
    end,
  })

  -- Close hint when exiting insert mode
  api.nvim_create_autocmd("ModeChanged", {
    group = self.augroup,
    pattern = "i:*",
    callback = function()
      local cur_buf = api.nvim_get_current_buf()
      if self.input_container and cur_buf == self.input_container.bufnr then self:show_input_hint() end
    end,
  })

  api.nvim_create_autocmd("WinEnter", {
    group = self.augroup,
    callback = function()
      local cur_win = api.nvim_get_current_win()
      if self.input_container and cur_win == self.input_container.winid then
        self:show_input_hint()
      else
        self:close_input_hint()
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

  -- Clear hint when leaving the window
  self.input_container:on(event.BufLeave, function() self:close_input_hint() end, {})

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

  local selected_filepaths = self.file_selector:get_selected_filepaths()
  local selected_files_size = #selected_filepaths
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
  self.ask_opts = opts

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

  self:create_input_container()

  self:create_selected_files_container()

  self:update_content_with_history()

  if self.code.bufnr and api.nvim_buf_is_valid(self.code.bufnr) then
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
  end

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
      if self.selected_files_container and api.nvim_win_is_valid(self.selected_files_container.winid) then
        self.selected_files_container:unmount()
      end
      return
    end

    if not self.selected_files_container or not api.nvim_win_is_valid(self.selected_files_container.winid) then
      self:create_selected_files_container()
      if not self.selected_files_container or not api.nvim_win_is_valid(self.selected_files_container.winid) then
        Utils.warn("Failed to create or find selected files container window.")
        return
      end
    end

    local lines_to_set = {}
    local highlights_to_apply = {}

    for i, filepath in ipairs(selected_filepaths_) do
      local icon, hl = Utils.file.get_file_icon(filepath)
      local formatted_line = string.format("%s %s", icon, filepath)
      table.insert(lines_to_set, formatted_line)
      if hl and hl ~= "" then table.insert(highlights_to_apply, { line_nr = i, icon = icon, hl = hl }) end
    end

    local selected_files_buf = api.nvim_win_get_buf(self.selected_files_container.winid)
    Utils.unlock_buf(selected_files_buf)
    api.nvim_buf_clear_namespace(selected_files_buf, SELECTED_FILES_ICON_NAMESPACE, 0, -1)
    api.nvim_buf_set_lines(selected_files_buf, 0, -1, true, lines_to_set)

    for _, highlight_info in ipairs(highlights_to_apply) do
      local line_idx = highlight_info.line_nr - 1
      local icon_bytes = #highlight_info.icon
      pcall(api.nvim_buf_set_extmark, selected_files_buf, SELECTED_FILES_ICON_NAMESPACE, line_idx, 0, {
        end_col = icon_bytes,
        hl_group = highlight_info.hl,
        priority = PRIORITY,
      })
    end

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
  self.selected_files_container:on({ event.CursorMoved }, function() self:show_selected_files_hint() end, {})

  -- Clear hint when leaving the window
  self.selected_files_container:on(event.BufLeave, function() self:close_selected_files_hint() end, {})

  render()
end

return Sidebar
