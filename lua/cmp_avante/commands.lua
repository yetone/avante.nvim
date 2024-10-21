local api = vim.api

---@class commands_source : cmp.Source
---@field commands AvanteSlashCommand[]
---@field bufnr integer
local commands_source = {}
commands_source.__index = commands_source

---@param commands AvanteSlashCommand[]
---@param bufnr integer
function commands_source:new(commands, bufnr)
  local instance = setmetatable({}, commands_source)

  instance.commands = commands
  instance.bufnr = bufnr

  return instance
end

function commands_source:is_available() return api.nvim_get_current_buf() == self.bufnr end

commands_source.get_position_encoding_kind = function() return "utf-8" end

function commands_source:get_trigger_characters() return { "/" } end

function commands_source:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function commands_source:complete(_, callback)
  local kind = require("cmp").lsp.CompletionItemKind.Variable

  local items = {}

  for _, command in ipairs(self.commands) do
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
