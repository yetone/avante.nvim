local api = vim.api

---@class mentions_source : cmp.Source
---@field get_mentions fun(): {description: string, command: AvanteMentions, details: string, shorthelp?: string, callback?: AvanteMentionCallback}[]
local MentionsSource = {}
MentionsSource.__index = MentionsSource

---@param get_mentions fun(): {description: string, command: AvanteMentions, details: string, shorthelp?: string, callback?: AvanteMentionCallback}[]
function MentionsSource:new(get_mentions)
  local instance = setmetatable({}, MentionsSource)

  instance.get_mentions = get_mentions

  return instance
end

function MentionsSource:is_available()
  return vim.bo.filetype == "AvanteInput" or vim.bo.filetype == "AvantePromptInput"
end

function MentionsSource.get_position_encoding_kind() return "utf-8" end

function MentionsSource:get_trigger_characters() return { "@" } end

function MentionsSource:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function MentionsSource:complete(_, callback)
  local kind = require("cmp").lsp.CompletionItemKind.Variable

  local items = {}

  local mentions = self.get_mentions()

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

---@param completion_item table
---@param callback fun(response: {behavior: number})
function MentionsSource:execute(completion_item, callback)
  local current_line = api.nvim_get_current_line()
  local label = completion_item.label:match("^@(%S+)") -- Extract mention command without '@' and space

  local mentions = self.get_mentions()

  -- Find the corresponding mention
  local selected_mention
  for _, mention in ipairs(mentions) do
    if mention.command == label then
      selected_mention = mention
      break
    end
  end

  local sidebar = require("avante").get()

  -- Execute the mention's callback if it exists
  if selected_mention and type(selected_mention.callback) == "function" then
    selected_mention.callback(sidebar)
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

return MentionsSource
