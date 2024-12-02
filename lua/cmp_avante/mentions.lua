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

---@param completion_item table
---@param callback fun(response: {behavior: number})
function mentions_source:execute(completion_item, callback)
  local current_line = api.nvim_get_current_line()
  local label = completion_item.label:match("^@(%S+)") -- Extract mention command without '@' and space

  -- Find the corresponding mention
  local selected_mention
  for _, mention in ipairs(self.mentions) do
    if mention.command == label then
      selected_mention = mention
      break
    end
  end

  -- Execute the mention's callback if it exists
  if selected_mention and type(selected_mention.callback) == "function" then
    selected_mention.callback(selected_mention)
    -- Get the current cursor position
    local row, col = unpack(api.nvim_win_get_cursor(0))

    -- Replace the current line with the new line (removing the mention)
    local new_line = current_line:gsub(vim.pesc(completion_item.label), "")
    api.nvim_buf_set_lines(0, row - 1, row, false, { new_line })

    -- Adjust the cursor position if needed
    local new_col = math.min(col, #new_line)
    api.nvim_win_set_cursor(0, { row, new_col })
  end

  callback({ behavior = require("cmp").ConfirmBehavior.Insert })
end

return mentions_source
