---@class AvanteBedrockClaudeTextMessage
---@field type "text"
---@field text string
---
---@class AvanteBedrockClaudeMessage
---@field role "user" | "assistant"
---@field content [AvanteBedrockClaudeTextMessage][]

local P = require("avante.providers")
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
M.transform_tool = Claude.transform_tool

---@param provider AvanteProviderFunctor
---@param prompt_opts AvantePromptOptions
---@param request_body table
---@return table
function M.build_bedrock_payload(provider, prompt_opts, request_body)
  local system_prompt = prompt_opts.system_prompt or ""
  local messages = provider:parse_messages(prompt_opts)
  local max_tokens = request_body.max_tokens or 2000

  local provider_conf, _ = P.parse_config(provider)
  local disable_tools = provider_conf.disable_tools or false
  local tools = {}
  if not disable_tools and prompt_opts.tools then
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, provider:transform_tool(tool))
    end
  end

  local payload = {
    anthropic_version = "bedrock-2023-05-31",
    max_tokens = max_tokens,
    messages = messages,
    tools = tools,
    system = system_prompt,
  }
  return vim.tbl_deep_extend("force", payload, request_body or {})
end

return M
