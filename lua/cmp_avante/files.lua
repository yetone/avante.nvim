local api = vim.api

---@class files_source : cmp.Source
---@field files {description: string, command: AvanteFiles, details: string, shorthelp?: string, callback?: AvanteFileCallback}[]
---@field bufnr integer
---@field callback fun(completion_item: table)
local files_source = {}
files_source.__index = files_source

---@param callback fun(completion_item: table)
---@param bufnr integer
function files_source:new(callback, bufnr)
  local instance = setmetatable({}, files_source)

  instance.bufnr = bufnr
  instance.callback = callback

  return instance
end

function files_source:is_available() return api.nvim_get_current_buf() == self.bufnr end

files_source.get_position_encoding_kind = function() return "utf-8" end

function files_source:get_trigger_characters() return { "@", ":" } end

function files_source:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function files_source:complete(params, callback)
  local kind = require("cmp").lsp.CompletionItemKind.File

  local items = {}

  table.insert(items, {
    label = "@file",
    kind = kind,
    insertText = " ",
  })

  callback({ items = items })
end

---@param completion_item table
---@param callback fun(response: {behavior: number})
function files_source:execute(completion_item, callback)
  if type(self.callback) == "function" then self.callback(completion_item) end
  callback({ behavior = require("cmp").ConfirmBehavior.Nothing })
end

function files_source:reset() self.stage = "initial" end

return files_source
