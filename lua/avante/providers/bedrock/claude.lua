---@class AvanteBedrockClaudeTextMessage
---@field type "text"
---@field text string
---
---@class AvanteBedrockClaudeMessage
---@field role "user" | "assistant"
---@field content [AvanteBedrockClaudeTextMessage][]

---@class AvanteBedrockModelHandler
local M = {}

M.role_map = {
  user = "user",
  assistant = "assistant",
}

M.parse_messages = function(opts)
  ---@type AvanteBedrockClaudeMessage[]
  local messages = {}

  for _, message in ipairs(opts.messages) do
    table.insert(messages, {
      role = M.role_map[message.role],
      content = {
        {
          type = "text",
          text = message.content,
        },
      },
    })
  end

  return messages
end

M.parse_response = function(ctx, data_stream, event_state, opts)
  if event_state == nil then
    if data_stream:match('"content_block_delta"') then
      event_state = "content_block_delta"
    elseif data_stream:match('"message_stop"') then
      event_state = "message_stop"
    end
  end
  if event_state == "content_block_delta" then
    local ok, json = pcall(vim.json.decode, data_stream)
    if not ok then return end
    opts.on_chunk(json.delta.text)
  elseif event_state == "message_stop" then
    opts.on_complete(nil)
    return
  elseif event_state == "error" then
    opts.on_complete(vim.json.decode(data_stream))
  end
end

---@param prompt_opts AvantePromptOptions
---@param body_opts table
---@return table
M.build_bedrock_payload = function(prompt_opts, body_opts)
  local system_prompt = prompt_opts.system_prompt or ""
  local messages = M.parse_messages(prompt_opts)
  local max_tokens = body_opts.max_tokens or 2000
  local temperature = body_opts.temperature or 0.7
  local payload = {
    anthropic_version = "bedrock-2023-05-31",
    max_tokens = max_tokens,
    messages = messages,
    system = system_prompt
  }
  return vim.tbl_deep_extend("force", payload, body_opts or {})
end

return M
