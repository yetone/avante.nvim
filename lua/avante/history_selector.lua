local Utils = require("avante.utils")
local Path = require("avante.path")
local Config = require("avante.config")
local Selector = require("avante.ui.selector")

---@class avante.HistorySelector
local M = {}

---@param history avante.ChatHistory
---@return table?
local function to_selector_item(history)
  local messages = Utils.get_history_messages(history)
  local timestamp = #messages > 0 and messages[#messages].timestamp or history.timestamp
  local name = history.title .. " - " .. timestamp .. " (" .. #messages .. ")"
  name = name:gsub("\n", "\\n")
  return {
    name = name,
    filename = history.filename,
  }
end

---@param bufnr integer
---@param cb fun(filename: string)
function M.open(bufnr, cb)
  local selector_items = {}

  local histories = Path.history.list(bufnr)

  for _, history in ipairs(histories) do
    table.insert(selector_items, to_selector_item(history))
  end

  if #selector_items == 0 then
    Utils.warn("No history items found.")
    return
  end

  local current_selector -- To be able to close it from the keymap

  current_selector = Selector:new({
    provider = Config.selector.provider, -- This should be 'native' for the current setup
    title = "Avante History (Select, then choose action)", -- Updated title
    items = vim
      .iter(selector_items)
      :map(
        function(item)
          return {
            id = item.filename,
            title = item.name,
          }
        end
      )
      :totable(),
    on_select = function(item_ids)
      if not item_ids then return end
      if #item_ids == 0 then return end
      cb(item_ids[1])
    end,
    get_preview_content = function(item_id)
      local history = Path.history.load(vim.api.nvim_get_current_buf(), item_id)
      local Sidebar = require("avante.sidebar")
      local content = Sidebar.render_history_content(history)
      return content, "markdown"
    end,
    on_delete_item = function(item_id_to_delete)
      if not item_id_to_delete then
        Utils.warn("No item ID provided for deletion.")
        return
      end
      Path.history.delete(bufnr, item_id_to_delete) -- bufnr from M.open's scope
      -- The native provider handles the UI flow; we just need to refresh.
      M.open(bufnr, cb) -- Re-open the selector to refresh the list
    end,
    on_action_cancel = function()
      -- If the user cancels the open/delete prompt, re-open the history selector.
      M.open(bufnr, cb)
    end,
  })
  current_selector:open()
end

return M
