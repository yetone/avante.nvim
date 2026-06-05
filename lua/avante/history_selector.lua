local History = require("avante.history")
local Utils = require("avante.utils")
local Path = require("avante.path")
local Config = require("avante.config")
local Selector = require("avante.ui.selector")

---@class avante.HistorySelector
local M = {}

-- Number of most-recent conversations to show per project.
local HISTORY_PER_PROJECT = 5

-- Extract a plain-text snippet from a message's content field.
-- Content may be a string (modern user messages) or an array of typed blocks.
---@param content any
---@return string
local function extract_text(content)
  if type(content) == "string" then return content end
  if type(content) == "table" then
    for _, block in ipairs(content) do
      if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
        return block.text
      end
    end
  end
  return ""
end

-- Collapse whitespace and truncate a string to max_len, appending "…" if cut.
---@param s string
---@param max_len integer
---@return string
local function truncate(s, max_len)
  s = s:gsub("[\n\r\t]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
  if #s <= max_len then return s end
  return s:sub(1, max_len - 1) .. "…"
end

-- Return the role of a message, handling both modern (msg.role) and legacy
-- (msg.message.role via the Message class wrapper) formats.
---@param msg table
---@return string
local function msg_role(msg)
  return msg.role or (type(msg.message) == "table" and msg.message.role) or ""
end

-- Return the content of a message, handling both formats.
---@param msg table
---@return any
local function msg_content(msg)
  return msg.content or (type(msg.message) == "table" and msg.message.content) or ""
end

-- Build the display label for a history entry.
-- Format: "project_name | <first user msg>…<last msg>"
---@param history avante.ChatHistory
---@param project_name string
---@param full_filepath string  absolute path to the .json file (used as the item id)
---@return avante.ui.SelectorItem
local function to_selector_item(history, project_name, full_filepath)
  local messages = History.get_history_messages(history)

  -- First user message text
  local first_text = ""
  for _, msg in ipairs(messages) do
    if msg_role(msg) == "user" then
      local text = extract_text(msg_content(msg))
      if text ~= "" then
        first_text = text
        break
      end
    end
  end

  -- Last message text (any role)
  local last_text = ""
  for i = #messages, 1, -1 do
    local text = extract_text(msg_content(messages[i]))
    if text ~= "" then
      last_text = text
      break
    end
  end

  local label
  if first_text == "" and last_text == "" then
    label = project_name .. " | (empty)"
  elseif last_text == "" or first_text == last_text then
    label = project_name .. " | " .. truncate(first_text, 70)
  else
    label = project_name .. " | " .. truncate(first_text, 40) .. " … " .. truncate(last_text, 40)
  end

  return { id = full_filepath, title = label }
end

-- Return the N most-recent history filepaths from a history directory, sorted
-- by descending numeric filename (414.json > 413.json).  Non-numeric filenames
-- and metadata.json are skipped.
---@param history_dir_path table  plenary.path object
---@param n integer
---@return string[]  absolute file paths
local function get_recent_filepaths(history_dir_path, n)
  local files = vim.fn.glob(tostring(history_dir_path:joinpath("*.json")), true, true)
  local candidates = {}
  for _, filepath in ipairs(files) do
    if not filepath:match("metadata%.json$") then
      local num = tonumber(vim.fn.fnamemodify(filepath, ":t:r"))
      if num then table.insert(candidates, { filepath = filepath, num = num }) end
    end
  end
  table.sort(candidates, function(a, b) return a.num > b.num end)
  local result = {}
  for i = 1, math.min(n, #candidates) do
    table.insert(result, candidates[i].filepath)
  end
  return result
end

-- Build plain-text representation of a conversation for the "wr" write action.
-- Includes only user/assistant message text; tool-use/result blocks are skipped.
---@param history avante.ChatHistory
---@return string
local function render_plain_text(history)
  local messages = History.get_history_messages(history)
  local lines = {}
  for _, msg in ipairs(messages) do
    local role = msg_role(msg)
    -- Skip internal tool-orchestration messages
    if role ~= "user" and role ~= "assistant" then goto continue end

    local content = msg_content(msg)
    local text = ""
    if type(content) == "string" then
      text = content
    elseif type(content) == "table" then
      -- Gather only text blocks; skip tool_use / tool_result
      local parts = {}
      for _, block in ipairs(content) do
        if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
          table.insert(parts, block.text)
        end
      end
      text = table.concat(parts, "\n")
    end

    text = vim.trim(text)
    if text == "" then goto continue end

    table.insert(lines, string.upper(role) .. ":")
    table.insert(lines, text)
    table.insert(lines, "")
    ::continue::
  end
  return table.concat(lines, "\n")
end

---@param bufnr integer
---@param cb fun(filepath: string)  called with the FULL absolute path of the selected history JSON
function M.open(bufnr, cb)
  local PlPath = require("plenary.path")
  local projects = Path.list_projects()

  if not projects or #projects == 0 then
    Utils.warn("No avante history found.")
    return
  end

  local selector_items = {}

  for _, project in ipairs(projects) do
    -- Use the last component of the real project root as the display name.
    local project_name = vim.fn.fnamemodify(project.root, ":t")
    if not project_name or project_name == "" then project_name = project.name end

    local history_dir = PlPath:new(project.directory):joinpath("history")
    if not history_dir:exists() then goto continue end

    local recent_paths = get_recent_filepaths(history_dir, HISTORY_PER_PROJECT)
    for _, filepath in ipairs(recent_paths) do
      local history = Path.history.from_file(PlPath:new(filepath))
      if history then
        table.insert(selector_items, to_selector_item(history, project_name, filepath))
      end
    end

    ::continue::
  end

  if #selector_items == 0 then
    Utils.warn("No history items found.")
    return
  end

  Selector:new({
    provider = Config.selector.provider,
    title = string.format("Avante History (top %d per project)", HISTORY_PER_PROJECT),
    items = selector_items,

    on_select = function(item_ids)
      if not item_ids then return end
      if #item_ids == 0 then return end
      cb(item_ids[1])
    end,

    get_preview_content = function(item_id)
      local history = Path.history.from_file(PlPath:new(item_id))
      if not history then return "", "markdown" end
      local Sidebar = require("avante.sidebar")
      local content = Sidebar.render_history_content(history)
      return content, "markdown"
    end,

    on_delete_item = function(item_id)
      if not item_id then return end
      vim.fn.delete(item_id)
    end,

    on_write_item = function(item_id)
      local history = Path.history.from_file(PlPath:new(item_id))
      if not history then
        Utils.warn("Could not load history for writing.")
        return
      end

      local plain = render_plain_text(history)
      -- Default output path: cwd/<numeric_stem>_conversation.txt
      local cwd = vim.fn.getcwd()
      local stem = vim.fn.fnamemodify(item_id, ":t:r")
      local default_dest = cwd .. "/" .. stem .. "_conversation.txt"

      vim.ui.input({ prompt = "Write conversation to: ", default = default_dest }, function(dest)
        if not dest or dest == "" then return end
        local f = io.open(dest, "w")
        if not f then
          Utils.error("Could not open file for writing: " .. dest)
          return
        end
        f:write(plain)
        f:close()
        Utils.info("Conversation written to: " .. dest)
      end)
    end,

    on_open = function() M.open(bufnr, cb) end,
  }):open()
end

return M
