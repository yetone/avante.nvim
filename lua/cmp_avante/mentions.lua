---@class mentions_source
---@field sidebar avante.Sidebar
local mentions_source = {}

---@param sidebar avante.Sidebar
function mentions_source.new(sidebar)
  ---@type cmp.Source
  return setmetatable({
    sidebar = sidebar,
  }, { __index = mentions_source })
end

function mentions_source:is_available() return vim.bo.filetype == "AvanteInput" end

mentions_source.get_position_encoding_kind = function() return "utf-8" end

function mentions_source:get_trigger_characters() return { "@" } end

function mentions_source:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function mentions_source:complete(_, callback)
  local kind = require("cmp").lsp.CompletionItemKind.Variable

  local items = {}

  local mentions = self.sidebar:get_mentions()

  for _, mention in ipairs(mentions) do
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
