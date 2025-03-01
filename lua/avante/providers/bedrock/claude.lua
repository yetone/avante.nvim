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

function M.parse_messages(opts)
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

  if opts.tool_histories then
    for _, tool_history in ipairs(opts.tool_histories) do
      if tool_history.tool_use then
        local msg = {
          role = "assistant",
          content = {},
        }
        if tool_history.tool_use.thinking_contents then
          for _, thinking_content in ipairs(tool_history.tool_use.thinking_contents) do
            msg.content[#msg.content + 1] = {
              type = "thinking",
              thinking = thinking_content.content,
              signature = thinking_content.signature,
            }
          end
        end
        if tool_history.tool_use.response_contents then
          for _, response_content in ipairs(tool_history.tool_use.response_contents) do
            msg.content[#msg.content + 1] = {
              type = "text",
              text = response_content,
            }
          end
        end
        msg.content[#msg.content + 1] = {
          type = "tool_use",
          id = tool_history.tool_use.id,
          name = tool_history.tool_use.name,
          input = vim.json.decode(tool_history.tool_use.input_json),
        }
        messages[#messages + 1] = msg
      end

      if tool_history.tool_result then
        messages[#messages + 1] = {
          role = "user",
          content = {
            {
              type = "tool_result",
              tool_use_id = tool_history.tool_result.tool_use_id,
              content = tool_history.tool_result.content,
              is_error = tool_history.tool_result.is_error,
            },
          },
        }
      end
    end
  end

  return messages
end

M.parse_response = Claude.parse_response

---@param prompt_opts AvantePromptOptions
---@param body_opts table
---@return table
function M.build_bedrock_payload(prompt_opts, body_opts)
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
