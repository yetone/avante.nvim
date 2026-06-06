local History = require("avante.history")
local Utils = require("avante.utils")
local Path = require("avante.path")
local Config = require("avante.config")
local Selector = require("avante.ui.selector")

---@class avante.HistorySelector
local M = {}

-- Sentinel item ids used for non-history rows in the picker.
local EXPAND_ID = "__avante_expand_other_projects__"
local SEPARATOR_ID = "__avante_separator__"

-- Collapse whitespace and truncate a string to max_len, appending "…" if cut.
---@param s string
---@param max_len integer
---@return string
local function truncate(s, max_len)
  s = s:gsub("[\n\r\t]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
  if #s <= max_len then return s end
  return s:sub(1, max_len - 1) .. "…"
end

-- Format a mtime as "5m ago", "3h ago", "2d ago", or a date stamp for older
-- entries.
---@param mtime integer  seconds since epoch
---@return string
local function format_relative_time(mtime)
  if not mtime or mtime <= 0 then return "" end
  local now = os.time()
  local diff = now - mtime
  if diff < 0 then diff = 0 end
  if diff < 60 then return diff .. "s ago" end
  if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
  if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
  if diff < 86400 * 7 then return math.floor(diff / 86400) .. "d ago" end
  if diff < 86400 * 30 then return math.floor(diff / (86400 * 7)) .. "w ago" end
  return os.date("%Y-%m-%d", mtime) --[[@as string]]
end

---@param summary avante.HistoryInstanceSummary
---@param include_project boolean  if true, prefix label with project basename
---@return avante.ui.SelectorItem
local function to_selector_item(summary, include_project)
  local time_str = format_relative_time(summary.mtime)
  local first = summary.first_message_text
  if first == "" then first = summary.last_message_text end
  if first == "" then first = "(empty)" end
  first = truncate(first, 80)

  local pieces = {}
  if include_project then
    local project_name = vim.fn.fnamemodify(summary.project_root, ":t")
    if project_name == "" then project_name = summary.project_dirname end
    table.insert(pieces, "[" .. project_name .. "]")
  end
  table.insert(pieces, summary.instance_name)
  if time_str ~= "" then table.insert(pieces, time_str) end
  table.insert(pieces, first)
  if summary.is_legacy then table.insert(pieces, "(legacy)") end

  return {
    -- Encode both the relative filename and the project storage key in the
    -- item id so we can disambiguate cross-project picks unambiguously.
    id = summary.filename .. "\0" .. summary.project_dirname,
    title = table.concat(pieces, "  "),
  }
end

-- Build plain-text representation of a conversation for the write action.
---@param history avante.ChatHistory
---@return string
local function render_plain_text(history)
  local messages = History.get_history_messages(history)
  local lines = {}
  local function msg_role(m) return m.role or (type(m.message) == "table" and m.message.role) or "" end
  local function msg_content(m) return m.content or (type(m.message) == "table" and m.message.content) or "" end
  for _, msg in ipairs(messages) do
    local role = msg_role(msg)
    if role ~= "user" and role ~= "assistant" then goto continue end

    local content = msg_content(msg)
    local text = ""
    if type(content) == "string" then
      text = content
    elseif type(content) == "table" then
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

-- Load a multi-part instance history by absolute storage path (used for
-- preview / write actions on cross-project picks, where bufnr won't resolve
-- to the right project dir).
---@param summary avante.HistoryInstanceSummary
---@return avante.ChatHistory | nil
local function load_history_by_summary(summary)
  local PlPath = require("plenary.path")
  local instance_dir = PlPath:new(Config.history.storage_path)
    :joinpath("projects")
    :joinpath(summary.project_dirname)
    :joinpath("history")
    :joinpath(summary.instance_dirname)
  if not instance_dir:exists() then return nil end
  local json_files = vim.fn.glob(tostring(instance_dir:joinpath("*.json")), true, true)
  table.sort(json_files, function(a, b)
    local na = tonumber(vim.fn.fnamemodify(a, ":t:r")) or 0
    local nb = tonumber(vim.fn.fnamemodify(b, ":t:r")) or 0
    return na < nb
  end)
  if #json_files == 0 then return nil end
  local history = Path.history.from_file(PlPath:new(json_files[1]))
  if not history then return nil end
  history.filename = summary.filename
  for i = 2, #json_files do
    local part = Path.history.from_file(PlPath:new(json_files[i]))
    if part then
      if part.messages then vim.list_extend(history.messages, part.messages) end
      if part.entries then vim.list_extend(history.entries, part.entries) end
    end
  end
  return history
end

---@param bufnr integer
---@param cb fun(payload: { filename: string, project_root: string, project_dirname: string, cross_project: boolean })
---@param include_other_projects boolean
local function open_picker(bufnr, cb, include_other_projects)
  local current = Path.history.list_instances(bufnr) or {}
  local current_project_root = Utils.root.get({ buf = bufnr }) or ""

  local others = {}
  if include_other_projects then others = Path.history.list_all_instances(current_project_root) or {} end

  local items_by_id = {}
  local function index(s) items_by_id[s.filename .. "\0" .. s.project_dirname] = s end
  for _, s in ipairs(current) do
    index(s)
  end
  for _, s in ipairs(others) do
    index(s)
  end

  ---@type avante.ui.SelectorItem[]
  local selector_items = {}
  for _, s in ipairs(current) do
    table.insert(selector_items, to_selector_item(s, false))
  end

  if include_other_projects then
    if #others > 0 and #current > 0 then
      table.insert(selector_items, { id = SEPARATOR_ID, title = string.rep("─", 60) })
    end
    for _, s in ipairs(others) do
      table.insert(selector_items, to_selector_item(s, true))
    end
  else
    -- Always offer the expand option at the bottom (even when current is empty).
    table.insert(selector_items, {
      id = EXPAND_ID,
      title = "▶ Show histories from other projects (will switch nvim cwd on pick)",
    })
  end

  if #selector_items == 0 then
    Utils.warn("No avante history found for this project.")
    return
  end

  local title = include_other_projects and "Avante History (all projects, mtime-sorted)"
    or "Avante History (this project, mtime-sorted)"

  Selector:new({
    provider = Config.selector.provider,
    title = title,
    items = selector_items,

    on_select = function(item_ids)
      if not item_ids or #item_ids == 0 then return end
      local picked = item_ids[1]
      if picked == EXPAND_ID then
        vim.schedule(function() open_picker(bufnr, cb, true) end)
        return
      end
      if picked == SEPARATOR_ID then return end

      local summary = items_by_id[picked]
      if not summary then return end

      cb({
        filename = summary.filename,
        project_root = summary.project_root,
        project_dirname = summary.project_dirname,
        cross_project = summary.project_root ~= current_project_root,
      })
    end,

    get_preview_content = function(item_id)
      if item_id == EXPAND_ID or item_id == SEPARATOR_ID then return "", "markdown" end
      local summary = items_by_id[item_id]
      if not summary then return "", "markdown" end
      local history = load_history_by_summary(summary)
      if not history then return "", "markdown" end
      local Sidebar = require("avante.sidebar")
      local content = Sidebar.render_history_content(history)
      return content, "markdown"
    end,

    on_delete_item = function(item_id)
      if item_id == EXPAND_ID or item_id == SEPARATOR_ID then return end
      local summary = items_by_id[item_id]
      if not summary then return end
      -- Mark the instance as deleted (sentinel file) without touching the JSONs.
      -- We can't use Path.history.mark_instance_deleted(bufnr, ...) for
      -- cross-project picks because the bufnr resolves to a DIFFERENT project
      -- dir, so write the sentinel directly using the storage path we know.
      local PlPath = require("plenary.path")
      local sentinel = PlPath:new(Config.history.storage_path)
        :joinpath("projects")
        :joinpath(summary.project_dirname)
        :joinpath("history")
        :joinpath(summary.instance_dirname)
        :joinpath(".deleted")
      pcall(function() sentinel:write(tostring(os.time()), "w") end)
      Utils.info("Marked '" .. summary.instance_name .. "' as deleted (instance dir kept on disk)")
    end,

    on_write_item = function(item_id)
      if item_id == EXPAND_ID or item_id == SEPARATOR_ID then return end
      local summary = items_by_id[item_id]
      if not summary then return end
      local history = load_history_by_summary(summary)
      if not history then
        Utils.warn("Could not load history for writing.")
        return
      end
      local plain = render_plain_text(history)
      local cwd = vim.fn.getcwd()
      local default_dest = cwd .. "/" .. summary.instance_name .. "_conversation.txt"

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

    on_open = function() open_picker(bufnr, cb, include_other_projects) end,
  }):open()
end

---@param bufnr integer
---@param cb fun(payload: { filename: string, project_root: string, project_dirname: string, cross_project: boolean })
function M.open(bufnr, cb) open_picker(bufnr, cb, false) end

return M

