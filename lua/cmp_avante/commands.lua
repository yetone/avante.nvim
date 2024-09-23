---@class commands_source
---@field sidebar avante.Sidebar
local commands_source = {}

---@param sidebar avante.Sidebar
function commands_source.new(sidebar)
  ---@type cmp.Source
  return setmetatable({
    sidebar = sidebar,
  }, { __index = commands_source })
end

function commands_source:is_available() return vim.bo.filetype == "AvanteInput" end

commands_source.get_position_encoding_kind = function() return "utf-8" end

function commands_source:get_trigger_characters() return { "/" } end

function commands_source:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function commands_source:complete(_, callback)
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

return commands_source
