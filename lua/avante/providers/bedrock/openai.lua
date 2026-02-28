local P = require("avante.providers")
local Utils = require("avante.utils")
local OpenAI = require("avante.providers.openai")

local M = {}

M.role_map = {
  user = "user",
  assistant = "assistant",
  system = "system",
}

M.is_disable_stream = OpenAI.is_disable_stream
M.parse_messages = OpenAI.parse_messages
M.parse_response = OpenAI.parse_response
M.parse_response_without_stream = OpenAI.parse_response_without_stream
M.is_reasoning_model = OpenAI.is_reasoning_model
M.transform_tool = OpenAI.transform_tool
M.add_text_message = OpenAI.add_text_message
M.finish_pending_messages = OpenAI.finish_pending_messages
M.add_tool_use_message = OpenAI.add_tool_use_message
M.add_tool_use_messages = OpenAI.add_tool_use_messages
M.transform_openai_usage = OpenAI.transform_openai_usage

function M.is_mistral(url)
  return false
end

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