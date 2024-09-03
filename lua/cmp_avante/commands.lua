---@class source
---@field sidebar avante.Sidebar
local source = {}

---@param sidebar avante.Sidebar
function source.new(sidebar)
  ---@type cmp.Source
  return setmetatable({
    sidebar = sidebar,
  }, { __index = source })
end

function source:is_available() return vim.bo.filetype == "AvanteInput" end

source.get_position_encoding_kind = function() return "utf-8" end

function source:get_trigger_characters() return { "/" } end

function source:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function source:complete(_, callback)
  local kind = require("cmp").lsp.CompletionItemKind.Variable

  local items = {}

  local commands = self.sidebar:get_commands()

  for _, command in ipairs(commands) do
    table.insert(items, {
      label = "/" .. command.command,
      kind = kind,
      detail = command.details,
    })
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

return source
