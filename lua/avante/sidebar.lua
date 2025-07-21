local api = vim.api
local fn = vim.fn

local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local PPath = require("plenary.path")
local Providers = require("avante.providers")
local Path = require("avante.path")
local Config = require("avante.config")
local Diff = require("avante.diff")
local Llm = require("avante.llm")
local Utils = require("avante.utils")
local PromptLogger = require("avante.utils.promptLogger")
local Highlights = require("avante.highlights")
local RepoMap = require("avante.repo_map")
local FileSelector = require("avante.file_selector")
local LLMTools = require("avante.llm_tools")
local History = require("avante.history")
local Render = require("avante.history.render")
local Line = require("avante.ui.line")
local LRUCache = require("avante.utils.lru_cache")

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

---This is a list of known sidebar containers or sub-windows. They are listed in
---the order they appear in the sidebar, from top to bottom.
local SIDEBAR_CONTAINERS = {
  "result",
  "selected_code",
  "selected_files",
  "todos",
  "input",
}

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
---@field containers { result?: NuiSplit, todos?: NuiSplit, selected_code?: NuiSplit, selected_files?: NuiSplit, input?: NuiSplit }
---@field file_selector FileSelector
---@field chat_history avante.ChatHistory | nil
---@field current_state avante.GenerateState | nil
---@field state_timer table | nil
---@field state_spinner_chars string[]
---@field thinking_spinner_chars string[]
---@field state_spinner_idx integer
---@field state_extmark_id integer | nil
---@field scroll boolean
---@field input_hint_window integer | nil
---@field ask_opts AskOptions
---@field old_result_lines avante.ui.Line[]
---@field token_count integer | nil

---@param id integer the tabpage id retrieved from api.nvim_get_current_tabpage()
function Sidebar:new(id)
  return setmetatable({
    id = id,
    code = { bufnr = 0, winid = 0, selection = nil, old_winhl = nil },
    winids = {
      result_container = 0,
      todos_container = 0,
      selected_files_container = 0,
      selected_code_container = 0,
      input_container = 0,
    },
    containers = {},
    file_selector = FileSelector:new(id),
    is_generating = false,
    chat_history = nil,
    current_state = nil,
    state_timer = nil,
    state_spinner_chars = Config.windows.spinner.generating,
    thinking_spinner_chars = Config.windows.spinner.thinking,
    state_spinner_idx = 1,
    state_extmark_id = nil,
    scroll = true,
    input_hint_window = nil,
    ask_opts = {},
    old_result_lines = {},
    token_count = nil,
    -- Cache-related fields
    _cached_history_lines = nil,
    _history_cache_invalidated = true,
  }, Sidebar)
end

function Sidebar:delete_autocmds()
  if self.augroup then api.nvim_del_augroup_by_id(self.augroup) end
  self.augroup = nil
end

function Sidebar:delete_containers()
  for _, container in pairs(self.containers) do
    container:unmount()
  end
  self.containers = {}
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

  self:delete_containers()

  self.code = { bufnr = 0, winid = 0, selection = nil }
  self.scroll = true
  self.old_result_lines = {}
  self.token_count = nil
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
    api.nvim_exec_autocmds("User", { pattern = Providers.env.REQUEST_LOGIN_PATTERN })
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
  if not Utils.is_valid_container(self.containers.result, true) then return end

  if Utils.should_hidden_border(self.code.winid, self.containers.result.winid) then
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
    if self.code.winid and api.nvim_win_is_valid(self.code.winid) then
      vim.wo[self.code.winid].winhl = self.code.old_winhl
    end
    self.code.old_winhl = nil
  end
end

---@class SidebarCloseOptions
---@field goto_code_win? boolean

---@param opts? SidebarCloseOptions
function Sidebar:close(opts)
  opts = vim.tbl_extend("force", { goto_code_win = true }, opts or {})

  self:delete_autocmds()
  self:delete_containers()

  self.old_result_lines = {}
  if opts.goto_code_win and self.code and self.code.winid and api.nvim_win_is_valid(self.code.winid) then
    fn.win_gotoid(self.code.winid)
  end

  self:recover_code_winhl()
  self:close_input_hint()
end

function Sidebar:shutdown()
  Llm.cancel_inflight_request()
  self:close()
  vim.cmd("noautocmd stopinsert")
end

---@return boolean
function Sidebar:focus()
  if self:is_open() then
    fn.win_gotoid(self.containers.result.winid)
    return true
  end
  return false
end

function Sidebar:focus_input()
  if Utils.is_valid_container(self.containers.input, true) then
    api.nvim_set_current_win(self.containers.input.winid)
    self:show_input_hint()
  end
end

function Sidebar:is_open() return Utils.is_valid_container(self.containers.result, true) end

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

      local match_filetype = nil
      local filepath = current_filepath or prev_filepath or ""

      if filepath == "" then goto continue end

      local file_content_lines = Utils.read_file_from_buf_or_disk(filepath) or {}
      local file_type = Utils.get_filetype(filepath)
      local search_lines = vim.list_slice(result_lines, search_start, search_end - 1)
      local start_line, end_line = Utils.fuzzy_match(file_content_lines, search_lines)

      if start_line ~= nil and end_line ~= nil then
        match_filetype = file_type
      else
        start_line = 0
        end_line = 0
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

local function insert_conflict_contents(bufnr, snippets)
  -- sort snippets by start_line
  table.sort(snippets, function(a, b) return a.range[1] < b.range[1] end)

  local lines = Utils.get_buf_lines(0, -1, bufnr)

  local offset = 0

  for _, snippet in ipairs(snippets) do
    local start_line, end_line = unpack(snippet.range)

    local first_line_content = lines[start_line]
    local old_first_line_indentation = ""

    if first_line_content then old_first_line_indentation = Utils.get_indentation(first_line_content) end

    local result = {}
    table.insert(result, "<<<<<<< HEAD")
    for i = start_line, end_line do
      table.insert(result, lines[i])
    end
    table.insert(result, "=======")

    local snippet_lines = vim.split(snippet.content, "\n")

    if #snippet_lines > 0 then
      local new_first_line_indentation = Utils.get_indentation(snippet_lines[1])
      if #old_first_line_indentation > #new_first_line_indentation then
        local line_indentation = old_first_line_indentation:sub(#new_first_line_indentation + 1)
        snippet_lines = vim.iter(snippet_lines):map(function(line) return line_indentation .. line end):totable()
      end
    end

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

---@param position? integer
---@return AvanteRespUserRequestBlock | nil
function Sidebar:get_current_user_request_block(position)
  local current_resp_content, current_resp_start_line = self:get_content_between_separators(position)
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
    elseif start_line ~= nil then
      break
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
  local cursor_line = api.nvim_win_get_cursor(self.containers.result.winid)[1]
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

  if Utils.is_valid_container(self.containers.input) then
    local lines = vim.split(block.content, "\n")
    api.nvim_buf_set_lines(self.containers.input.bufnr, 0, -1, false, lines)
    api.nvim_set_current_win(self.containers.input.winid)
    api.nvim_win_set_cursor(self.containers.input.winid, { 1, #lines > 0 and #lines[1] or 0 })
  end
end

---@param current_cursor boolean
function Sidebar:apply(current_cursor)
  local response, response_start_line = self:get_content_between_separators()
  local all_snippets_map = extract_code_snippets_map(response)
  local selected_snippets_map = {}
  if current_cursor then
    if self.containers.result and self.containers.result.winid then
      local cursor_line = Utils.get_cursor_pos(self.containers.result.winid)
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
      local bufnr = Utils.open_buffer(filepath)
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
  statusline = " ",
}

function Sidebar:render_header(winid, bufnr, header_text, hl, reverse_hl)
  if not Config.windows.sidebar_header.enabled then return end
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then return end

  local is_result_win = self.containers.result and self.containers.result.winid == winid
  local separator_char = is_result_win and " " or "-"
  local win_width = vim.api.nvim_win_get_width(winid)

  if not Config.windows.sidebar_header.rounded then header_text = " " .. header_text .. " " end
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
  if not Utils.is_valid_container(self.containers.result) then return end
  local header_text = Utils.icon("󰭻 ") .. "Avante"
  self:render_header(
    self.containers.result.winid,
    self.containers.result.bufnr,
    header_text,
    Highlights.TITLE,
    Highlights.REVERSED_TITLE
  )
end

---@param ask? boolean
function Sidebar:render_input(ask)
  if ask == nil then ask = true end
  if not Utils.is_valid_container(self.containers.input) then return end

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
    self.containers.input.winid,
    self.containers.input.bufnr,
    header_text,
    Highlights.THIRD_TITLE,
    Highlights.REVERSED_THIRD_TITLE
  )
end

function Sidebar:render_selected_code()
  if not self.code.selection then return end
  if not Utils.is_valid_container(self.containers.selected_code) then return end

  local count = Utils.count_lines(self.code.selection.content)
  local max_shown = api.nvim_win_get_height(self.containers.selected_code.winid)
  if Config.windows.sidebar_header.enabled then max_shown = max_shown - 1 end

  local header_text = Utils.icon(" ") .. "Selected Code"
  if max_shown < count then header_text = string.format("%s (%d/%d lines)", header_text, max_shown, count) end

  self:render_header(
    self.containers.selected_code.winid,
    self.containers.selected_code.bufnr,
    header_text,
    Highlights.SUBTITLE,
    Highlights.REVERSED_SUBTITLE
  )
end

function Sidebar:bind_apply_key()
  if self.containers.result then
    vim.keymap.set(
      "n",
      Config.mappings.sidebar.apply_cursor,
      function() self:apply(true) end,
      { buffer = self.containers.result.bufnr, noremap = true, silent = true }
    )
  end
end

function Sidebar:unbind_apply_key()
  if self.containers.result then
    pcall(vim.keymap.del, "n", Config.mappings.sidebar.apply_cursor, { buffer = self.containers.result.bufnr })
  end
end

function Sidebar:bind_retry_user_request_key()
  if self.containers.result then
    vim.keymap.set(
      "n",
      Config.mappings.sidebar.retry_user_request,
      function() self:retry_user_request() end,
      { buffer = self.containers.result.bufnr, noremap = true, silent = true }
    )
  end
end

function Sidebar:unbind_retry_user_request_key()
  if self.containers.result then
    pcall(vim.keymap.del, "n", Config.mappings.sidebar.retry_user_request, { buffer = self.containers.result.bufnr })
  end
end

function Sidebar:bind_edit_user_request_key()
  if self.containers.result then
    vim.keymap.set(
      "n",
      Config.mappings.sidebar.edit_user_request,
      function() self:edit_user_request() end,
      { buffer = self.containers.result.bufnr, noremap = true, silent = true }
    )
  end
end

function Sidebar:unbind_edit_user_request_key()
  if self.containers.result then
    pcall(vim.keymap.del, "n", Config.mappings.sidebar.edit_user_request, { buffer = self.containers.result.bufnr })
  end
end

function Sidebar:bind_sidebar_keys(codeblocks)
  ---@param direction "next" | "prev"
  local function jump_to_codeblock(direction)
    local cursor_line = api.nvim_win_get_cursor(self.containers.result.winid)[1]
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
      api.nvim_win_set_cursor(self.containers.result.winid, { target_block.start_line, 0 })
      vim.cmd("normal! zz")
    else
      Utils.error("No codeblock found")
    end
  end

  ---@param direction "next" | "prev"
  local function jump_to_prompt(direction)
    local current_request_block = self:get_current_user_request_block()
    local current_line = Utils.get_cursor_pos(self.containers.result.winid)
    if not current_request_block then
      Utils.error("No prompt found")
      return
    end
    if
      (current_request_block.start_line > current_line and direction == "next")
      or (current_request_block.end_line < current_line and direction == "prev")
    then
      api.nvim_win_set_cursor(self.containers.result.winid, { current_request_block.start_line, 0 })
      return
    end
    local start_search_line = current_line
    local result_lines = Utils.get_buf_lines(0, -1, self.containers.result.bufnr)
    local end_search_line = direction == "next" and #result_lines or 1
    local step = direction == "next" and 1 or -1
    local query_pos ---@type integer|nil
    for i = start_search_line, end_search_line, step do
      local result_line = result_lines[i]
      if result_line == RESP_SEPARATOR then
        query_pos = direction == "next" and i + 1 or i - 1
        break
      end
    end
    if not query_pos then
      Utils.error("No other prompt found " .. (direction == "next" and "below" or "above"))
      return
    end
    current_request_block = self:get_current_user_request_block(query_pos)
    if not current_request_block then
      Utils.error("No prompt found")
      return
    end
    api.nvim_win_set_cursor(self.containers.result.winid, { current_request_block.start_line, 0 })
  end

  vim.keymap.set(
    "n",
    Config.mappings.sidebar.apply_all,
    function() self:apply(false) end,
    { buffer = self.containers.result.bufnr, noremap = true, silent = true }
  )
  vim.keymap.set(
    "n",
    Config.mappings.jump.next,
    function() jump_to_codeblock("next") end,
    { buffer = self.containers.result.bufnr, noremap = true, silent = true }
  )
  vim.keymap.set(
    "n",
    Config.mappings.jump.prev,
    function() jump_to_codeblock("prev") end,
    { buffer = self.containers.result.bufnr, noremap = true, silent = true }
  )
  vim.keymap.set(
    "n",
    Config.mappings.sidebar.next_prompt,
    function() jump_to_prompt("next") end,
    { buffer = self.containers.result.bufnr, noremap = true, silent = true }
  )
  vim.keymap.set(
    "n",
    Config.mappings.sidebar.prev_prompt,
    function() jump_to_prompt("prev") end,
    { buffer = self.containers.result.bufnr, noremap = true, silent = true }
  )
end

function Sidebar:unbind_sidebar_keys()
  if Utils.is_valid_container(self.containers.result) then
    pcall(vim.keymap.del, "n", Config.mappings.sidebar.apply_all, { buffer = self.containers.result.bufnr })
    pcall(vim.keymap.del, "n", Config.mappings.jump.next, { buffer = self.containers.result.bufnr })
    pcall(vim.keymap.del, "n", Config.mappings.jump.prev, { buffer = self.containers.result.bufnr })
  end
end

---@param opts AskOptions
function Sidebar:on_mount(opts)
  self:setup_window_navigation(self.containers.result)

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

  api.nvim_set_option_value("wrap", Config.windows.wrap, { win = self.containers.result.winid })

  local current_apply_extmark_id = nil

  ---@param block AvanteCodeblock
  local function show_apply_button(block)
    if current_apply_extmark_id then
      api.nvim_buf_del_extmark(self.containers.result.bufnr, CODEBLOCK_KEYBINDING_NAMESPACE, current_apply_extmark_id)
    end

    current_apply_extmark_id = api.nvim_buf_set_extmark(
      self.containers.result.bufnr,
      CODEBLOCK_KEYBINDING_NAMESPACE,
      block.start_line - 1,
      -1,
      {
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
      }
    )
  end

  local current_user_request_block_extmark_id = nil

  local function show_user_request_block_control_buttons()
    if current_user_request_block_extmark_id then
      api.nvim_buf_del_extmark(
        self.containers.result.bufnr,
        USER_REQUEST_BLOCK_KEYBINDING_NAMESPACE,
        current_user_request_block_extmark_id
      )
    end

    local block = self:get_current_user_request_block()
    if not block then return end

    current_user_request_block_extmark_id = api.nvim_buf_set_extmark(
      self.containers.result.bufnr,
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
    buffer = self.containers.result.bufnr,
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
      buffer = self.containers.result.bufnr,
      callback = function(ev)
        codeblocks = parse_codeblocks(ev.buf)
        self:bind_sidebar_keys(codeblocks)
      end,
    })

    api.nvim_create_autocmd("User", {
      group = self.augroup,
      pattern = VIEW_BUFFER_UPDATED_PATTERN,
      callback = function()
        if not Utils.is_valid_container(self.containers.result) then return end
        codeblocks = parse_codeblocks(self.containers.result.bufnr)
        self:bind_sidebar_keys(codeblocks)
      end,
    })
  end

  api.nvim_create_autocmd("BufLeave", {
    group = self.augroup,
    buffer = self.containers.result.bufnr,
    callback = function() self:unbind_sidebar_keys() end,
  })

  self:render_result()
  self:render_input(opts.ask)
  self:render_selected_code()

  if self.containers.selected_code ~= nil then
    local selected_code_buf = self.containers.selected_code.bufnr
    if selected_code_buf ~= nil then
      if self.code.selection ~= nil then
        Utils.unlock_buf(selected_code_buf)
        local lines = vim.split(self.code.selection.content, "\n")
        api.nvim_buf_set_lines(selected_code_buf, 0, -1, false, lines)
        Utils.lock_buf(selected_code_buf)
      end
      if self.code.bufnr and api.nvim_buf_is_valid(self.code.bufnr) then
        local ts_ok, ts_highlighter = pcall(require, "vim.treesitter.highlighter")
        if ts_ok and ts_highlighter.active[self.code.bufnr] then
          -- Treesitter highlighting is active in the code buffer, activate it
          -- it in code selection buffer as well.
          local filetype = vim.bo[self.code.bufnr].filetype
          if filetype and filetype ~= "" then
            vim.treesitter.start(selected_code_buf, vim.bo[self.code.bufnr].filetype)
          end
        end
        -- Try the old syntax highlighting
        local syntax = api.nvim_get_option_value("syntax", { buf = self.code.bufnr })
        if syntax and syntax ~= "" then api.nvim_set_option_value("syntax", syntax, { buf = selected_code_buf }) end
      end
    end
  end

  api.nvim_create_autocmd("BufEnter", {
    group = self.augroup,
    buffer = self.containers.result.bufnr,
    callback = function()
      if Config.behaviour.auto_focus_sidebar then
        self:focus()
        if Utils.is_valid_container(self.containers.input, true) then
          api.nvim_set_current_win(self.containers.input.winid)
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
      if closed_winid then
        local container = self:get_sidebar_window(closed_winid)
        -- Ignore closing selected files and todos windows because they can disappear during normal operation
        if container and container ~= self.containers.selected_files and container ~= self.containers.todos then
          self:close()
        end
      end
    end,
  })

  for _, container in pairs(self.containers) do
    if container.mount and container.bufnr and api.nvim_buf_is_valid(container.bufnr) then
      Utils.mark_as_sidebar_buffer(container.bufnr)
    end
  end
end

--- Given a desired container name, returns the window ID of the first valid container
--- situated above it in the sidebar's order.
--- @param container_name string The name of the container to start searching from.
--- @return integer|nil The window ID of the previous valid container, or nil.
function Sidebar:get_split_candidate(container_name)
  local start_index = 0
  for i, name in ipairs(SIDEBAR_CONTAINERS) do
    if name == container_name then
      start_index = i
      break
    end
  end

  if start_index > 1 then
    for i = start_index - 1, 1, -1 do
      local container = self.containers[SIDEBAR_CONTAINERS[i]]
      if Utils.is_valid_container(container, true) then return container.winid end
    end
  end
  return nil
end

---Cycles focus over sidebar components.
---@param direction "next" | "previous"
function Sidebar:switch_window_focus(direction)
  local current_winid = vim.api.nvim_get_current_win()
  local current_index = nil
  local ordered_winids = {}

  for _, name in ipairs(SIDEBAR_CONTAINERS) do
    local container = self.containers[name]
    if container and container.winid then
      table.insert(ordered_winids, container.winid)
      if container.winid == current_winid then current_index = #ordered_winids end
    end
  end

  if current_index and #ordered_winids > 1 then
    local next_index
    if direction == "next" then
      next_index = (current_index % #ordered_winids) + 1
    elseif direction == "previous" then
      next_index = current_index - 1
      if next_index < 1 then next_index = #ordered_winids end
    else
      error("Invalid 'direction' parameter: " .. direction)
    end

    vim.api.nvim_set_current_win(ordered_winids[next_index])
  end
end

---Sets up focus switching shortcuts for a sidebar component
---@param container NuiSplit
function Sidebar:setup_window_navigation(container)
  local buf = api.nvim_win_get_buf(container.winid)
  Utils.safe_keymap_set(
    { "n", "i" },
    Config.mappings.sidebar.switch_windows,
    function() self:switch_window_focus("next") end,
    { buffer = buf, noremap = true, silent = true, nowait = true }
  )
  Utils.safe_keymap_set(
    { "n", "i" },
    Config.mappings.sidebar.reverse_switch_windows,
    function() self:switch_window_focus("previous") end,
    { buffer = buf, noremap = true, silent = true, nowait = true }
  )
end

function Sidebar:resize()
  for _, container in pairs(self.containers) do
    if container.winid and api.nvim_win_is_valid(container.winid) then
      api.nvim_win_set_width(container.winid, Config.get_window_width())
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
  local filepath = Utils.file.is_in_project(buf_path) and Utils.relative_path(buf_path) or buf_path
  Utils.debug("Sidebar:initialize adding buffer to file selector", buf_path)

  self.file_selector:reset()

  local stat = vim.uv.fs_stat(filepath)
  if stat == nil or stat.type == "file" then self.file_selector:add_selected_file(filepath) end

  self:reload_chat_history()

  return self
end

function Sidebar:is_focused_on_result()
  return self:is_open() and self.containers.result and self.containers.result.winid == api.nvim_get_current_win()
end

---Locates container object by its window ID
---@param winid integer
---@return NuiSplit|nil
function Sidebar:get_sidebar_window(winid)
  for _, container in pairs(self.containers) do
    if container and container.winid == winid then return container end
  end
end

---Checks if a window with given ID belongs to the sidebar
---@param winid integer
---@return boolean
function Sidebar:is_sidebar_winid(winid) return self:get_sidebar_window(winid) ~= nil end

---@return boolean
function Sidebar:should_auto_scroll()
  if not self.containers.result or not self.containers.result.winid then return false end
  if not api.nvim_win_is_valid(self.containers.result.winid) then return false end

  local win_height = api.nvim_win_get_height(self.containers.result.winid)
  local total_lines = api.nvim_buf_line_count(self.containers.result.bufnr)

  local topline = vim.fn.line("w0", self.containers.result.winid)

  local last_visible_line = topline + win_height - 1

  local is_scrolled_to_bottom = last_visible_line >= total_lines - 1

  return is_scrolled_to_bottom
end

Sidebar.throttled_update_content = Utils.throttle(function(self, ...)
  local args = { ... }
  self:update_content(unpack(args))
end, 50)

---@param content string concatenated content of the buffer
---@param opts? {focus?: boolean, scroll?: boolean, backspace?: integer, callback?: fun(): nil} whether to focus the result view
function Sidebar:update_content(content, opts)
  if not self.containers.result or not self.containers.result.bufnr then return end

  -- 提前验证容器有效性，避免后续无效操作
  if not Utils.is_valid_container(self.containers.result) then return end

  local should_auto_scroll = self:should_auto_scroll()

  opts = vim.tbl_deep_extend(
    "force",
    { focus = false, scroll = should_auto_scroll and self.scroll, callback = nil },
    opts or {}
  )

  -- 缓存历史行，避免重复计算
  local history_lines
  if not self._cached_history_lines or self._history_cache_invalidated then
    history_lines = self.get_history_lines(self.chat_history)
    self._cached_history_lines = history_lines
    self._history_cache_invalidated = false
  else
    history_lines = vim.deepcopy(self._cached_history_lines)
  end

  if content ~= nil and content ~= "" then
    table.insert(history_lines, Line:new({ { "" } }))
    for _, line in ipairs(vim.split(content, "\n")) do
      table.insert(history_lines, Line:new({ { line } }))
    end
  end

  -- 使用 vim.schedule 而不是 vim.defer_fn(0)，性能更好
  -- 再次检查容器有效性
  if not Utils.is_valid_container(self.containers.result) then return end

  self:clear_state()

  -- 批量更新操作
  local bufnr = self.containers.result.bufnr
  Utils.unlock_buf(bufnr)

  Utils.update_buffer_lines(RESULT_BUF_HL_NAMESPACE, bufnr, self.old_result_lines, history_lines)

  -- 缓存结果行
  self.old_result_lines = history_lines

  -- 批量设置选项
  api.nvim_set_option_value("filetype", "Avante", { buf = bufnr })
  Utils.lock_buf(bufnr)

  -- 处理焦点和滚动
  if opts.focus and not self:is_focused_on_result() then
    xpcall(function() api.nvim_set_current_win(self.containers.result.winid) end, function(err)
      Utils.debug("Failed to set current win:", err)
      return err
    end)
  end

  if opts.scroll then Utils.buf_scroll_to_end(bufnr) end

  -- 延迟执行回调和状态渲染
  if opts.callback then vim.schedule(opts.callback) end

  -- 最后渲染状态
  vim.schedule(function()
    self:render_state()
    -- 延迟重绘，避免阻塞
    vim.defer_fn(function() vim.cmd("redraw") end, 10)
  end)

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
  local res = "- Datetime: " .. timestamp .. "\n" .. "- Model:    " .. provider .. "/" .. model
  if selected_filepaths ~= nil and #selected_filepaths > 0 then
    res = res .. "\n- Selected files:"
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

  ---@cast position -"smart", -string
  return position
end

function Sidebar:get_layout()
  return vim.tbl_contains({ "left", "right" }, calculate_config_window_position()) and "vertical" or "horizontal"
end

---@param message avante.HistoryMessage
---@param messages avante.HistoryMessage[]
---@param ctx table
---@return avante.ui.Line[]
local function _get_message_lines(message, messages, ctx)
  if message.visible == false then return {} end
  local lines = Render.message_to_lines(message, messages)
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
    if History.Helpers.is_tool_use_message(message) then return lines end
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

local _message_to_lines_lru_cache = LRUCache:new(100)

---@param message avante.HistoryMessage
---@param messages avante.HistoryMessage[]
---@param ctx table
---@return avante.ui.Line[]
local function get_message_lines(message, messages, ctx)
  if message.state == "generating" or message.is_calling then return _get_message_lines(message, messages, ctx) end
  local cached_lines = _message_to_lines_lru_cache:get(message.uuid)
  if cached_lines then return cached_lines end
  local lines = _get_message_lines(message, messages, ctx)
  _message_to_lines_lru_cache:set(message.uuid, lines)
  return lines
end

---@param history avante.ChatHistory
---@return avante.ui.Line[]
function Sidebar.get_history_lines(history)
  local history_messages = History.get_history_messages(history)
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
  local text = Render.message_to_text(message, messages)
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
  local history_messages = History.get_history_messages(history)
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

---@param position? integer
---@return string, integer
function Sidebar:get_content_between_separators(position)
  local separator = RESP_SEPARATOR
  local cursor_line = position or Utils.get_cursor_pos()
  local lines = Utils.get_buf_lines(0, -1, self.containers.result.bufnr)
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
  if next(self.chat_history) ~= nil then
    self.chat_history.messages = {}
    self.chat_history.entries = {}
    Path.history.save(self.code.bufnr, self.chat_history)
    self._history_cache_invalidated = true
    self:reload_chat_history()
    self:update_content_with_history()
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
    pcall(api.nvim_buf_del_extmark, self.containers.result.bufnr, STATE_NAMESPACE, self.state_extmark_id)
  end
  self.state_extmark_id = nil
  self.state_spinner_idx = 1
  if self.state_timer then self.state_timer:stop() end
end

function Sidebar:render_state()
  if not Utils.is_valid_container(self.containers.result) then return end
  if not self.current_state then return end
  local lines = vim.api.nvim_buf_get_lines(self.containers.result.bufnr, 0, -1, false)
  if self.state_extmark_id then
    api.nvim_buf_del_extmark(self.containers.result.bufnr, STATE_NAMESPACE, self.state_extmark_id)
  end
  local spinner_chars = self.state_spinner_chars
  if self.current_state == "thinking" then spinner_chars = self.thinking_spinner_chars end
  local hl = "AvanteStateSpinnerGenerating"
  if self.current_state == "tool calling" then hl = "AvanteStateSpinnerToolCalling" end
  if self.current_state == "failed" then hl = "AvanteStateSpinnerFailed" end
  if self.current_state == "succeeded" then hl = "AvanteStateSpinnerSucceeded" end
  if self.current_state == "searching" then hl = "AvanteStateSpinnerSearching" end
  if self.current_state == "thinking" then hl = "AvanteStateSpinnerThinking" end
  if self.current_state == "compacting" then hl = "AvanteStateSpinnerCompacting" end
  local spinner_char = spinner_chars[self.state_spinner_idx]
  self.state_spinner_idx = (self.state_spinner_idx % #spinner_chars) + 1
  if
    self.current_state ~= "generating"
    and self.current_state ~= "tool calling"
    and self.current_state ~= "thinking"
    and self.current_state ~= "compacting"
  then
    spinner_char = ""
  end
  local virt_line
  if spinner_char == "" then
    virt_line = " " .. self.current_state .. " "
  else
    virt_line = " " .. spinner_char .. " " .. self.current_state .. " "
  end

  local win_width = api.nvim_win_get_width(self.containers.result.winid)
  local padding = math.floor((win_width - vim.fn.strdisplaywidth(virt_line)) / 2)
  local centered_virt_lines = {
    { { string.rep(" ", padding) }, { virt_line, hl } },
  }

  local line_num = math.max(0, #lines - 2)
  self.state_extmark_id = api.nvim_buf_set_extmark(self.containers.result.bufnr, STATE_NAMESPACE, line_num, 0, {
    virt_lines = centered_virt_lines,
    hl_eol = true,
    hl_mode = "combine",
  })
  self.state_timer = vim.defer_fn(function() self:render_state() end, 160)
end

function Sidebar:init_current_project(args, cb)
  local user_input = [[
You are a responsible senior development engineer, and you are about to leave your position. Please carefully analyze the entire project and generate a handover document to be stored in the AGENTS.md file, so that subsequent developers can quickly get up to speed. The requirements are as follows:
- If there is an AGENTS.md file in the project root directory, combine it with the existing AGENTS.md content to generate a new AGENTS.md.
- If the existing AGENTS.md content conflicts with the newly generated content, replace the conflicting old parts with the new content.
- If there is no AGENTS.md file in the project root directory, create a new AGENTS.md file and write the new content in it.]]
  self:new_chat(args, cb)
  self.code.selection = nil
  self.file_selector:reset()
  if self.containers.selected_files then self.containers.selected_files:unmount() end
  vim.api.nvim_exec_autocmds("User", { pattern = "AvanteInputSubmitted", data = { request = user_input } })
end

function Sidebar:compact_history_messages(args, cb)
  local history_memory = self.chat_history.memory
  local messages = History.get_history_messages(self.chat_history)
  self.current_state = "compacting"
  self:render_state()
  self:update_content(
    "compacting history messsages",
    { focus = false, scroll = true, callback = function() self:focus_input() end }
  )
  Llm.summarize_memory(history_memory and history_memory.content, messages, function(memory)
    if memory then
      self.chat_history.memory = memory
      Path.history.save(self.code.bufnr, self.chat_history)
    end
    self:update_content("compacted!", { focus = false, scroll = true, callback = function() self:focus_input() end })
    self.current_state = "compacted"
    self:clear_state()
    if cb then cb(args) end
  end)
end

function Sidebar:new_chat(args, cb)
  local history = Path.history.new(self.code.bufnr)
  Path.history.save(self.code.bufnr, history)
  self:reload_chat_history()
  self.current_state = nil
  self:update_content("New chat", { focus = false, scroll = false, callback = function() self:focus_input() end })
  if cb then cb(args) end
  vim.schedule(function() self:create_todos_container() end)
end

local debounced_save_history = Utils.debounce(
  function(self) Path.history.save(self.code.bufnr, self.chat_history) end,
  1000
)

function Sidebar:save_history() debounced_save_history(self) end

---@param uuids string[]
function Sidebar:delete_history_messages(uuids)
  local history_messages = History.get_history_messages(self.chat_history)
  for _, msg in ipairs(history_messages) do
    if vim.list_contains(uuids, msg.uuid) then msg.is_deleted = true end
  end
  Path.history.save(self.code.bufnr, self.chat_history)
end

---@param todos avante.TODO[]
function Sidebar:update_todos(todos)
  if self.chat_history == nil then self:reload_chat_history() end
  if self.chat_history == nil then return end
  self.chat_history.todos = todos
  Path.history.save(self.code.bufnr, self.chat_history)
  self:create_todos_container()
end

---@param messages avante.HistoryMessage | avante.HistoryMessage[]
function Sidebar:add_history_messages(messages)
  local history_messages = History.get_history_messages(self.chat_history)
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
  self._history_cache_invalidated = true
  self:save_history()
  if
    self.chat_history.title == "untitled"
    and #messages > 0
    and messages[1].just_for_display ~= true
    and messages[1].state == "generated"
  then
    local first_msg_text = Render.message_to_text(messages[1], messages)
    local lines_ = vim.iter(vim.split(first_msg_text, "\n")):filter(function(line) return line ~= "" end):totable()
    if #lines_ > 0 then
      self.chat_history.title = lines_[1]
      self:save_history()
    end
  end
  local last_message = messages[#messages]
  if last_message then
    if History.Helpers.is_tool_use_message(last_message) then
      self.current_state = "tool calling"
    elseif History.Helpers.is_thinking_message(last_message) then
      self.current_state = "thinking"
    else
      self.current_state = "generating"
    end
  end
  xpcall(function() self:throttled_update_content("") end, function(err)
    Utils.debug("Failed to update content:", err)
    return nil
  end)
end

-- FIXME: this is used by external plugin users
---@param messages AvanteLLMMessage | AvanteLLMMessage[]
---@param options {visible?: boolean}
function Sidebar:add_chat_history(messages, options)
  options = options or {}
  messages = vim.islist(messages) and messages or { messages }
  local is_first_user = true
  local history_messages = {}
  for _, message in ipairs(messages) do
    local role = message.role
    if role == "system" and type(message.content) == "string" then
      self.chat_history.system_prompt = message.content --[[@as string]]
    else
      ---@type AvanteLLMMessageContentItem
      local content = type(message.content) ~= "table" and message.content or message.content[1]
      local msg_opts = { visible = options.visible }
      if role == "user" and is_first_user then
        msg_opts.is_user_submission = true
        is_first_user = false
      end
      table.insert(history_messages, History.Message:new(role, content, msg_opts))
    end
  end
  self:add_history_messages(history_messages)
end

function Sidebar:create_selected_code_container()
  if self.containers.selected_code ~= nil then
    self.containers.selected_code:unmount()
    self.containers.selected_code = nil
  end

  local height = self:get_selected_code_container_height()

  if self.code.selection ~= nil then
    self.containers.selected_code = Split({
      enter = false,
      relative = {
        type = "win",
        winid = self:get_split_candidate("selected_code"),
      },
      buf_options = vim.tbl_deep_extend("force", buf_options, { filetype = "AvanteSelectedCode" }),
      win_options = vim.tbl_deep_extend("force", base_win_options, {}),
      size = {
        height = height,
      },
      position = "bottom",
    })
    self.containers.selected_code:mount()
    self:adjust_layout()
    self:setup_window_navigation(self.containers.selected_code)
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
  local win_height = api.nvim_win_get_height(self.containers.input.winid)
  local winline = Utils.winline(self.containers.input.winid)
  if winline >= win_height - 1 then return 0 end
  return winline
end

-- Create a floating window as a hint
function Sidebar:show_input_hint()
  self:close_input_hint() -- Close the existing hint window

  local hint_text = (fn.mode() ~= "i" and Config.mappings.submit.normal or Config.mappings.submit.insert) .. ": submit"
  if Config.behaviour.enable_token_counting then
    local input_value = table.concat(api.nvim_buf_get_lines(self.containers.input.bufnr, 0, -1, false), "\n")
    if self.token_count == nil then self:initialize_token_count() end
    local tokens = self.token_count + Utils.tokens.calculate_tokens(input_value)
    hint_text = "Tokens: " .. tostring(tokens) .. "; " .. hint_text
  end

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, { hint_text })
  api.nvim_buf_set_extmark(buf, INPUT_HINT_NAMESPACE, 0, 0, { hl_group = "AvantePopupHint", end_col = #hint_text })

  -- Get the current window size
  local win_width = api.nvim_win_get_width(self.containers.input.winid)
  local width = #hint_text

  -- Create the floating window
  self.input_hint_window = api.nvim_open_win(buf, false, {
    relative = "win",
    win = self.containers.input.winid,
    width = width,
    height = 1,
    row = self:get_input_float_window_row(),
    col = math.max(win_width - width, 0), -- Display in the bottom right corner
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 100,
  })
end

function Sidebar:close_selected_files_hint()
  if self.containers.selected_files and api.nvim_win_is_valid(self.containers.selected_files.winid) then
    pcall(api.nvim_buf_clear_namespace, self.containers.selected_files.bufnr, SELECTED_FILES_HINT_NAMESPACE, 0, -1)
  end
end

function Sidebar:show_selected_files_hint()
  self:close_selected_files_hint()

  local cursor_pos = api.nvim_win_get_cursor(self.containers.selected_files.winid)
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
    self.containers.selected_files.bufnr,
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
  self.token_count = nil
  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then return end
  self.chat_history = Path.history.load(self.code.bufnr)
  self._history_cache_invalidated = true
end

---@param opts? {all?: boolean}
---@return avante.HistoryMessage[]
function Sidebar:get_history_messages_for_api(opts)
  opts = opts or {}
  local messages = History.get_history_messages(self.chat_history)

  -- Scan the initial set of messages, filtering out "uninteresting" ones, but also
  -- check if the last message mentioned in the chat memory is actually present.
  local last_message = self.chat_history.memory and self.chat_history.memory.last_message_uuid
  local last_message_present = false
  messages = vim
    .iter(messages)
    :filter(function(message)
      if message.just_for_display or message.is_compacted then return false end
      if not opts.all then
        if message.state == "generating" then return false end
        if last_message and message.uuid == last_message then last_message_present = true end
      end
      return true
    end)
    :totable()

  if not opts.all then
    if last_message and last_message_present then
      -- Drop all old messages preceding the "last" one from the memory
      local last_message_seen = false
      messages = vim
        .iter(messages)
        :filter(function(message)
          if not last_message_seen then
            if message.uuid == last_message then last_message_seen = true end
            return false
          end
          return true
        end)
        :totable()
    end

    local tool_limit
    if Providers[Config.provider].use_ReAct_prompt then
      tool_limit = nil
    else
      tool_limit = 25
    end
    messages = History.update_tool_invocation_history(messages, tool_limit, Config.behaviour.auto_check_diagnostics)
  end

  return messages
end

---@param request string
---@param cb? fun(opts: AvanteGeneratePromptsOptions): nil
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
      diagnostics = Utils.lsp.get_current_selection_diagnostics(self.code.bufnr, self.code.selection)
    else
      diagnostics = Utils.lsp.get_diagnostics(self.code.bufnr)
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

  local ask = self.ask_opts.ask
  if ask == nil then ask = true end

  ---@type AvanteGeneratePromptsOptions
  local prompts_opts = {
    ask = ask,
    project_context = vim.json.encode(project_context),
    selected_filepaths = selected_filepaths,
    recently_viewed_files = Utils.get_recent_filepaths(),
    diagnostics = vim.json.encode(diagnostics),
    history_messages = history_messages,
    code_lang = filetype,
    selected_code = selected_code,
    tools = tools,
  }

  if self.chat_history.system_prompt then
    prompts_opts.prompt_opts = {
      system_prompt = self.chat_history.system_prompt,
      messages = history_messages,
    }
  end

  if self.chat_history.memory then prompts_opts.memory = self.chat_history.memory.content end

  if Config.behaviour.enable_token_counting then self.token_count = Llm.calculate_tokens(prompts_opts) end

  if cb then cb(prompts_opts) end
end

function Sidebar:initialize_token_count()
  if Config.behaviour.enable_token_counting then self:get_generate_prompts_options("") end
end

function Sidebar:create_input_container()
  if self.containers.input then self.containers.input:unmount() end

  if not self.code.bufnr or not api.nvim_buf_is_valid(self.code.bufnr) then return end

  if self.chat_history == nil then self:reload_chat_history() end

  ---@param request string
  local function handle_submit(request)
    if Config.prompt_logger.enabled then PromptLogger.log_prompt(request) end

    if self.is_generating then
      self:add_history_messages({
        History.Message:new("user", request),
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

    vim.keymap.set("n", "j", on_j, { buffer = self.containers.result.bufnr })
    vim.keymap.set("n", "k", on_k, { buffer = self.containers.result.bufnr })
    vim.keymap.set("n", "G", on_G, { buffer = self.containers.result.bufnr })

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

    ---@param tool_id string
    ---@param tool_name string
    ---@param log string
    ---@param state AvanteLLMToolUseState
    local function on_tool_log(tool_id, tool_name, log, state)
      if state == "generating" then on_state_change("tool calling") end
      local tool_use_message = History.Helpers.get_tool_use_message(tool_id, self.chat_history.messages)
      if not tool_use_message then
        -- Utils.debug("tool_use message not found", tool_id, tool_name)
        return
      end

      local tool_use_logs = tool_use_message.tool_use_logs or {}
      local content = string.format("[%s]: %s", tool_name, log)
      table.insert(tool_use_logs, content)
      tool_use_message.tool_use_logs = tool_use_logs

      local orig_is_calling = tool_use_message.is_calling
      tool_use_message.is_calling = true
      self:update_content("")
      tool_use_message.is_calling = orig_is_calling
      self:save_history()
    end

    local function set_tool_use_store(tool_id, key, value)
      local tool_use_message = History.Helpers.get_tool_use_message(tool_id, self.chat_history.messages)
      if tool_use_message then
        local tool_use_store = tool_use_message.tool_use_store or {}
        tool_use_store[key] = value
        tool_use_message.tool_use_store = tool_use_store
        self:save_history()
      end
    end

    ---@type AvanteLLMStopCallback
    local function on_stop(stop_opts)
      self.is_generating = false

      pcall(function()
        ---remove keymaps
        vim.keymap.del("n", "j", { buffer = self.containers.result.bufnr })
        vim.keymap.del("n", "k", { buffer = self.containers.result.bufnr })
        vim.keymap.del("n", "G", { buffer = self.containers.result.bufnr })
      end)

      if stop_opts.error ~= nil then
        local msg_content = stop_opts.error
        if type(msg_content) ~= "string" then msg_content = vim.inspect(msg_content) end
        self:add_history_messages({
          History.Message:new("assistant", "\n\nError: " .. msg_content, {
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
        if
          Utils.is_valid_container(self.containers.result, true) and Config.behaviour.jump_result_buffer_on_finish
        then
          api.nvim_set_current_win(self.containers.result.winid)
        end
        if Config.behaviour.auto_apply_diff_after_generation then self:apply(false) end
      end, 0)

      Path.history.save(self.code.bufnr, self.chat_history)
    end

    if request and request ~= "" then
      self:add_history_messages({
        History.Message:new("user", request, {
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
        set_tool_use_store = set_tool_use_store,
        get_history_messages = function(opts) return self:get_history_messages_for_api(opts) end,
        get_todos = function()
          local history = Path.history.load(self.code.bufnr)
          return history and history.todos or {}
        end,
        session_ctx = {},
        ---@param usage avante.LLMTokenUsage
        update_tokens_usage = function(usage)
          if not usage then return end
          if usage.completion_tokens == nil then return end
          if usage.prompt_tokens == nil then return end
          self.chat_history.tokens_usage = usage
          self:save_history()
        end,
        get_tokens_usage = function() return self.chat_history.tokens_usage end,
      })

      ---@param pending_compaction_history_messages avante.HistoryMessage[]
      local function on_memory_summarize(pending_compaction_history_messages)
        local history_memory = self.chat_history.memory
        Llm.summarize_memory(
          history_memory and history_memory.content,
          pending_compaction_history_messages,
          function(memory)
            if memory then
              self.chat_history.memory = memory
              Path.history.save(self.code.bufnr, self.chat_history)
              stream_options.memory = memory.content
            end
            stream_options.history_messages = self:get_history_messages_for_api()
            Llm.stream(stream_options)
          end
        )
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

    local selected_code_container_height = self:get_selected_code_container_height()

    return {
      width = "40%",
      height = math.max(1, api.nvim_win_get_height(self.containers.result.winid) - selected_code_container_height),
    }
  end

  self.containers.input = Split({
    enter = false,
    relative = {
      type = "win",
      winid = self.containers.result.winid,
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
    if not Utils.is_valid_container(self.containers.input) then return end
    local lines = api.nvim_buf_get_lines(self.containers.input.bufnr, 0, -1, false)
    local request = table.concat(lines, "\n")
    if request == "" then return end
    api.nvim_buf_set_lines(self.containers.input.bufnr, 0, -1, false, {})
    api.nvim_win_set_cursor(self.containers.input.winid, { 1, 0 })
    handle_submit(request)
  end

  self.handle_submit = handle_submit

  self.containers.input:mount()

  local function place_sign_at_first_line(bufnr)
    local group = "avante_input_prompt_group"

    fn.sign_unplace(group, { buffer = bufnr })

    fn.sign_place(0, group, "AvanteInputPromptSign", bufnr, { lnum = 1 })
  end

  place_sign_at_first_line(self.containers.input.bufnr)

  if Utils.in_visual_mode() then
    -- Exit visual mode. Unfortunately there is no appropriate command
    -- so we have to simulate keystrokes.
    local esc_key = api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc_key, "n", false)
  end

  self:setup_window_navigation(self.containers.input)
  self.containers.input:map("n", Config.mappings.submit.normal, on_submit)
  self.containers.input:map("i", Config.mappings.submit.insert, on_submit)
  self.containers.input:map("n", Config.prompt_logger.next_prompt.normal, PromptLogger.on_log_retrieve(-1))
  self.containers.input:map("i", Config.prompt_logger.next_prompt.insert, PromptLogger.on_log_retrieve(-1))
  self.containers.input:map("n", Config.prompt_logger.prev_prompt.normal, PromptLogger.on_log_retrieve(1))
  self.containers.input:map("i", Config.prompt_logger.prev_prompt.insert, PromptLogger.on_log_retrieve(1))

  if Config.mappings.sidebar.close_from_input ~= nil then
    if Config.mappings.sidebar.close_from_input.normal ~= nil then
      self.containers.input:map("n", Config.mappings.sidebar.close_from_input.normal, function() self:shutdown() end)
    end
    if Config.mappings.sidebar.close_from_input.insert ~= nil then
      self.containers.input:map("i", Config.mappings.sidebar.close_from_input.insert, function() self:shutdown() end)
    end
  end

  api.nvim_set_option_value("filetype", "AvanteInput", { buf = self.containers.input.bufnr })

  -- Setup completion
  api.nvim_create_autocmd("InsertEnter", {
    group = self.augroup,
    buffer = self.containers.input.bufnr,
    once = true,
    desc = "Setup the completion of helpers in the input buffer",
    callback = function() end,
  })

  local debounced_show_input_hint = Utils.debounce(function()
    if vim.api.nvim_win_is_valid(self.containers.input.winid) then self:show_input_hint() end
  end, 200)
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "VimResized" }, {
    group = self.augroup,
    buffer = self.containers.input.bufnr,
    callback = function()
      debounced_show_input_hint()
      place_sign_at_first_line(self.containers.input.bufnr)
    end,
  })

  api.nvim_create_autocmd("QuitPre", {
    group = self.augroup,
    buffer = self.containers.input.bufnr,
    callback = function() self:close_input_hint() end,
  })

  api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    pattern = tostring(self.containers.input.winid),
    callback = function() self:close_input_hint() end,
  })

  api.nvim_create_autocmd("BufEnter", {
    group = self.augroup,
    buffer = self.containers.input.bufnr,
    callback = function()
      if Config.windows.ask.start_insert then vim.cmd("noautocmd startinsert!") end
    end,
  })

  api.nvim_create_autocmd("BufLeave", {
    group = self.augroup,
    buffer = self.containers.input.bufnr,
    callback = function()
      vim.cmd("noautocmd stopinsert")
      self:close_input_hint()
    end,
  })

  -- Update hint on mode change as submit key sequence may be different
  api.nvim_create_autocmd("ModeChanged", {
    group = self.augroup,
    buffer = self.containers.input.bufnr,
    callback = function() self:show_input_hint() end,
  })

  api.nvim_create_autocmd("WinEnter", {
    group = self.augroup,
    callback = function()
      local cur_win = api.nvim_get_current_win()
      if self.containers.input and cur_win == self.containers.input.winid then
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
end

-- FIXME: this is used by external plugin users
---@param value string
function Sidebar:set_input_value(value)
  if not self.containers.input then return end
  if not value then return end
  api.nvim_buf_set_lines(self.containers.input.bufnr, 0, -1, false, vim.split(value, "\n"))
end

---@return string
function Sidebar:get_input_value()
  if not self.containers.input then return "" end
  local lines = api.nvim_buf_get_lines(self.containers.input.bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function Sidebar:get_selected_code_container_height()
  if not self.code.selection then return 0 end

  local max_height = 5

  local count = Utils.count_lines(self.code.selection.content)
  if Config.windows.sidebar_header.enabled then count = count + 1 end

  return math.min(count, max_height)
end

function Sidebar:get_todos_container_height()
  local history = Path.history.load(self.code.bufnr)
  if not history or not history.todos or #history.todos == 0 then return 0 end
  return 3
end

function Sidebar:get_result_container_height()
  local todos_container_height = self:get_todos_container_height()
  local selected_code_container_height = self:get_selected_code_container_height()
  local selected_files_container_height = self:get_selected_files_container_height()

  if self:get_layout() == "horizontal" then return math.floor(Config.windows.height / 100 * vim.o.lines) end

  return math.max(
    1,
    api.nvim_get_option_value("lines", {})
      - selected_files_container_height
      - selected_code_container_height
      - todos_container_height
      - Config.windows.input.height
  )
end

function Sidebar:get_result_container_width()
  if self:get_layout() == "vertical" then return math.floor(Config.windows.width / 100 * vim.o.columns) end

  return math.max(1, api.nvim_win_get_width(self.code.winid))
end

function Sidebar:adjust_result_container_layout()
  local width = self:get_result_container_width()
  local height = self:get_result_container_height()

  api.nvim_win_set_width(self.containers.result.winid, width)
  api.nvim_win_set_height(self.containers.result.winid, height)
end

---@param opts AskOptions
function Sidebar:render(opts)
  self.ask_opts = opts

  local function get_position()
    return (opts and opts.win and opts.win.position) and opts.win.position or calculate_config_window_position()
  end

  self.containers.result = Split({
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

  self.containers.result:mount()

  self.augroup =
    api.nvim_create_augroup("avante_sidebar_" .. self.id .. self.containers.result.winid, { clear = true })

  self.containers.result:on(event.BufWinEnter, function()
    xpcall(function() api.nvim_buf_set_name(self.containers.result.bufnr, RESULT_BUF_NAME) end, function(_) end)
  end)

  self.containers.result:map("n", Config.mappings.sidebar.close, function() self:shutdown() end)

  self:create_input_container()

  self:create_selected_files_container()

  self:update_content_with_history()

  if self.code.bufnr and api.nvim_buf_is_valid(self.code.bufnr) then
    -- reset states when buffer is closed
    api.nvim_buf_attach(self.code.bufnr, false, {
      on_detach = function(_, _)
        vim.schedule(function()
          if not self.code.winid or not api.nvim_win_is_valid(self.code.winid) then return end
          local bufnr = api.nvim_win_get_buf(self.code.winid)
          self.code.bufnr = bufnr
          self:reload_chat_history()
        end)
      end,
    })
  end

  self:create_selected_code_container()

  self:create_todos_container()

  self:on_mount(opts)

  self:setup_colors()

  return self
end

function Sidebar:get_selected_files_container_height()
  local selected_filepaths_ = self.file_selector:get_selected_filepaths()
  return math.min(vim.o.lines - 2, #selected_filepaths_ + 1)
end

function Sidebar:adjust_selected_files_container_layout()
  if not Utils.is_valid_container(self.containers.selected_files, true) then return end

  local win_height = self:get_selected_files_container_height()
  api.nvim_win_set_height(self.containers.selected_files.winid, win_height)
end

function Sidebar:adjust_selected_code_container_layout()
  if not Utils.is_valid_container(self.containers.selected_code, true) then return end

  local win_height = self:get_selected_code_container_height()
  api.nvim_win_set_height(self.containers.selected_code.winid, win_height)
end

function Sidebar:adjust_todos_container_layout()
  if not Utils.is_valid_container(self.containers.todos, true) then return end

  local win_height = self:get_todos_container_height()
  api.nvim_win_set_height(self.containers.todos.winid, win_height)
end

function Sidebar:create_selected_files_container()
  if self.containers.selected_files then self.containers.selected_files:unmount() end

  local selected_filepaths = self.file_selector:get_selected_filepaths()
  if #selected_filepaths == 0 then
    self.file_selector:off("update")
    self.file_selector:on("update", function() self:create_selected_files_container() end)
    return
  end

  self.containers.selected_files = Split({
    enter = false,
    relative = {
      type = "win",
      winid = self:get_split_candidate("selected_files"),
    },
    buf_options = vim.tbl_deep_extend("force", buf_options, {
      modifiable = false,
      swapfile = false,
      buftype = "nofile",
      bufhidden = "wipe",
      filetype = "AvanteSelectedFiles",
    }),
    win_options = vim.tbl_deep_extend("force", base_win_options, {
      fillchars = Config.windows.fillchars,
    }),
    position = "bottom",
    size = {
      height = 2,
    },
  })
  self.containers.selected_files:mount()

  local function render()
    local selected_filepaths_ = self.file_selector:get_selected_filepaths()
    if #selected_filepaths_ == 0 then
      if Utils.is_valid_container(self.containers.selected_files) then self.containers.selected_files:unmount() end
      return
    end

    if not Utils.is_valid_container(self.containers.selected_files, true) then
      self:create_selected_files_container()
      if not Utils.is_valid_container(self.containers.selected_files, true) then
        Utils.warn("Failed to create or find selected files container window.")
        return
      end
    end

    local lines_to_set = {}
    local highlights_to_apply = {}

    local project_path = Utils.root.get()
    for i, filepath in ipairs(selected_filepaths_) do
      local icon, hl = Utils.file.get_file_icon(filepath)
      local renderpath = PPath:new(filepath):normalize(project_path)
      local formatted_line = string.format("%s %s", icon, renderpath)
      table.insert(lines_to_set, formatted_line)
      if hl and hl ~= "" then table.insert(highlights_to_apply, { line_nr = i, icon = icon, hl = hl }) end
    end

    local selected_files_count = #lines_to_set ---@type integer
    local selected_files_buf = api.nvim_win_get_buf(self.containers.selected_files.winid)
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
    api.nvim_win_set_height(self.containers.selected_files.winid, win_height)
    self:render_header(
      self.containers.selected_files.winid,
      selected_files_buf,
      string.format(
        "%sSelected (%d file%s)",
        Utils.icon(" "),
        selected_files_count,
        selected_files_count > 1 and "s" or ""
      ),
      Highlights.SUBTITLE,
      Highlights.REVERSED_SUBTITLE
    )
    self:adjust_layout()
  end

  self.file_selector:on("update", render)

  local function remove_file(line_number) self.file_selector:remove_selected_filepaths_with_index(line_number) end

  -- Set up keybinding to remove files
  self.containers.selected_files:map("n", Config.mappings.sidebar.remove_file, function()
    local line_number = api.nvim_win_get_cursor(self.containers.selected_files.winid)[1]
    remove_file(line_number)
  end, { noremap = true, silent = true })

  self.containers.selected_files:map("x", Config.mappings.sidebar.remove_file, function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    local start_line = math.min(vim.fn.line("v"), vim.fn.line("."))
    local end_line = math.max(vim.fn.line("v"), vim.fn.line("."))
    for _ = start_line, end_line do
      remove_file(start_line)
    end
  end, { noremap = true, silent = true })

  self.containers.selected_files:map(
    "n",
    Config.mappings.sidebar.add_file,
    function() self.file_selector:open() end,
    { noremap = true, silent = true }
  )

  -- Set up autocmd to show hint on cursor move
  self.containers.selected_files:on({ event.CursorMoved }, function() self:show_selected_files_hint() end, {})

  -- Clear hint when leaving the window
  self.containers.selected_files:on(event.BufLeave, function() self:close_selected_files_hint() end, {})

  self:setup_window_navigation(self.containers.selected_files)

  render()
end

function Sidebar:create_todos_container()
  local history = Path.history.load(self.code.bufnr)
  if not history or not history.todos or #history.todos == 0 then
    if self.containers.todos then self.containers.todos:unmount() end
    self.containers.todos = nil
    self:adjust_layout()
    return
  end
  if not Utils.is_valid_container(self.containers.todos, true) then
    self.containers.todos = Split({
      enter = false,
      relative = {
        type = "win",
        winid = self:get_split_candidate("todos"),
      },
      buf_options = vim.tbl_deep_extend("force", buf_options, {
        modifiable = false,
        swapfile = false,
        buftype = "nofile",
        bufhidden = "wipe",
        filetype = "AvanteTodos",
      }),
      win_options = vim.tbl_deep_extend("force", base_win_options, {
        fillchars = Config.windows.fillchars,
      }),
      position = "bottom",
      size = {
        height = 3,
      },
    })
    self.containers.todos:mount()
    self:setup_window_navigation(self.containers.todos)
  end
  local done_count = 0
  local total_count = #history.todos
  local focused_idx = 1
  local todos_content_lines = {}
  for idx, todo in ipairs(history.todos) do
    local status_content = "[ ]"
    if todo.status == "done" then
      done_count = done_count + 1
      status_content = "[x]"
    end
    if todo.status == "doing" then status_content = "[-]" end
    local line = string.format("%s %d. %s", status_content, idx, todo.content)
    if todo.status == "cancelled" then line = "~~" .. line .. "~~" end
    if todo.status ~= "todo" then focused_idx = idx + 1 end
    table.insert(todos_content_lines, line)
  end
  if focused_idx > #todos_content_lines then focused_idx = #todos_content_lines end
  local todos_buf = api.nvim_win_get_buf(self.containers.todos.winid)
  Utils.unlock_buf(todos_buf)
  api.nvim_buf_set_lines(todos_buf, 0, -1, false, todos_content_lines)
  api.nvim_win_set_cursor(self.containers.todos.winid, { focused_idx, 0 })
  Utils.lock_buf(todos_buf)
  self:render_header(
    self.containers.todos.winid,
    todos_buf,
    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
    Highlights.SUBTITLE,
    Highlights.REVERSED_SUBTITLE
  )
  self:adjust_layout()
end

function Sidebar:adjust_layout()
  self:adjust_result_container_layout()
  self:adjust_todos_container_layout()
  self:adjust_selected_code_container_layout()
  self:adjust_selected_files_container_layout()
end

return Sidebar
