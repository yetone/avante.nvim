---@class AvanteBedrockClaudeTextMessage
---@field type "text"
---@field text string
---
---@class AvanteBedrockClaudeMessage
---@field role "user" | "assistant"
---@field content [AvanteBedrockClaudeTextMessage][]

local Claude = require("avante.providers.claude")

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

  if opts.tool_use then
    local msg = {
      role = "assistant",
      content = {},
    }
    if opts.response_content then
      msg.content[#msg.content + 1] = {
        type = "text",
        text = opts.response_content,
      }
    end
    msg.content[#msg.content + 1] = {
      type = "tool_use",
      id = opts.tool_use.id,
      name = opts.tool_use.name,
      input = vim.json.decode(opts.tool_use.input_json),
    }
    messages[#messages + 1] = msg
  end

  if opts.tool_result then
    messages[#messages + 1] = {
      role = "user",
      content = {
        {
          type = "tool_result",
          tool_use_id = opts.tool_result.tool_use_id,
          content = opts.tool_result.content,
          is_error = opts.tool_result.is_error,
        },
      },
    }
  end

  return messages
end

M.parse_response = Claude.parse_response

---@param prompt_opts AvantePromptOptions
---@param body_opts table
---@return table
M.build_bedrock_payload = function(prompt_opts, body_opts)
  local system_prompt = prompt_opts.system_prompt or ""
  local messages = M.parse_messages(prompt_opts)
  local max_tokens = body_opts.max_tokens or 2000
  local payload = {
    anthropic_version = "bedrock-2023-05-31",
    max_tokens = max_tokens,
    messages = messages,
    system = system_prompt,
  }
  return vim.tbl_deep_extend("force", payload, body_opts or {})
end

return M
