local api = vim.api

---@class ShortcutsSource : cmp.Source
local ShortcutsSource = {}
ShortcutsSource.__index = ShortcutsSource

function ShortcutsSource:new()
  local instance = setmetatable({}, ShortcutsSource)
  return instance
end

function ShortcutsSource:is_available() return vim.bo.filetype == "AvanteInput" end

function ShortcutsSource.get_position_encoding_kind() return "utf-8" end

function ShortcutsSource:get_trigger_characters() return { "#" } end

function ShortcutsSource:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function ShortcutsSource:complete(_, callback)
  local Utils = require("avante.utils")
  local kind = require("cmp").lsp.CompletionItemKind.Variable
  local shortcuts = Utils.get_shortcuts()

  local items = {}
  for _, shortcut in ipairs(shortcuts) do
    table.insert(items, {
      label = "#" .. shortcut.name,
      kind = kind,
      detail = shortcut.details,
      data = {
        name = shortcut.name,
        prompt = shortcut.prompt,
        details = shortcut.details,
      },
    })
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

function ShortcutsSource:execute(item, callback)
  -- ShortcutsSource should only provide completion, not perform replacement
  -- The actual shortcut replacement is handled in sidebar.lua handle_submit function
  callback()
end

return ShortcutsSource
