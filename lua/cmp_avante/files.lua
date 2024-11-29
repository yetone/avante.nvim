local api = vim.api

---@class files_source : cmp.Source
---@field files {description: string, command: AvanteFiles, details: string, shorthelp?: string, callback?: AvanteFileCallback}[]
---@field bufnr integer
local files_source = {}
files_source.__index = files_source

---@param files {description: string, command: AvanteFiles, details: string, shorthelp?: string, callback?: AvanteFileCallback}[]
---@param bufnr integer
function files_source:new(files, bufnr)
  local instance = setmetatable({}, files_source)

  instance.files = files
  instance.bufnr = bufnr
  instance.stage = "initial" -- Add a stage property

  return instance
end

function files_source:is_available() return api.nvim_get_current_buf() == self.bufnr end

files_source.get_position_encoding_kind = function() return "utf-8" end

function files_source:get_trigger_characters() return { "@", ":" } end

function files_source:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function files_source:complete(params, callback)
  local input = string.sub(params.context.cursor_before_line, params.offset)
  local cursor_before_line = params.context.cursor_before_line
  local kind = require("cmp").lsp.CompletionItemKind.File

  local items = {}

  if self.stage == "initial" then
    table.insert(items, {
      label = "@file",
      kind = kind,
      insertText = "@",
    })
  elseif self.stage == "file_selection" then
    for _, file in ipairs(self.files) do
      table.insert(items, {
        label = "@" .. file.command,
        kind = kind,
        detail = file.details,
      })
    end
  end

  callback({ items = items })
end

function files_source:on_complete(completion_item)
  if completion_item.label == "@file" then
    self.stage = "file_selection"
  else
    self.stage = "initial"
  end
end

function files_source:execute(completion_item, callback)
  self:on_complete(completion_item)
  callback({ behavior = require("cmp").ConfirmBehavior.Insert })
end

function files_source:reset() self.stage = "initial" end

return files_source
