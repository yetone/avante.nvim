local api = vim.api

---@class mentions_source : cmp.Source
---@field mentions {description: string, command: AvanteMentions, details: string, shorthelp?: string, callback?: AvanteMentionCallback}[]
---@field bufnr integer
local mentions_source = {}
mentions_source.__index = mentions_source

---@param mentions {description: string, command: AvanteMentions, details: string, shorthelp?: string, callback?: AvanteMentionCallback}[]
---@param bufnr integer
function mentions_source:new(mentions, bufnr)
  local instance = setmetatable({}, mentions_source)

  instance.mentions = mentions
  instance.bufnr = bufnr

  return instance
end

function mentions_source:is_available() return api.nvim_get_current_buf() == self.bufnr end

mentions_source.get_position_encoding_kind = function() return "utf-8" end

function mentions_source:get_trigger_characters() return { "@" } end

function mentions_source:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function mentions_source:complete(_, callback)
  local kind = require("cmp").lsp.CompletionItemKind.Variable

  local items = {}

  for _, mention in ipairs(self.mentions) do
    table.insert(items, {
      label = "@" .. mention.command .. " ",
      kind = kind,
      detail = mention.details,
    })
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

return mentions_source
