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

M.support_prompt_caching = false
M.role_map = {
  user = "user",
  assistant = "assistant",
}

M.is_disable_stream = Claude.is_disable_stream
M.parse_messages = Claude.parse_messages
M.parse_response = Claude.parse_response

---@param provider AvanteProviderFunctor
---@param prompt_opts AvantePromptOptions
---@param request_body table
---@return table
function M.build_bedrock_payload(provider, prompt_opts, request_body)
  local system_prompt = prompt_opts.system_prompt or ""
  local messages = provider:parse_messages(prompt_opts)
  local max_tokens = request_body.max_tokens or 2000
  local payload = {
    anthropic_version = "bedrock-2023-05-31",
    max_tokens = max_tokens,
    messages = messages,
    system = system_prompt,
  }
  return vim.tbl_deep_extend("force", payload, request_body or {})
end

return M
