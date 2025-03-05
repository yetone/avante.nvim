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

M.parse_messages = Claude.parse_messages
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
