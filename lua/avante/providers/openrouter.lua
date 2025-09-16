---@class AvanteProviderFunctor
local M = {}

-- Inherit from OpenAI provider for full compatibility
M.__inherited_from = "openai"

-- OpenRouter-specific configuration
M.api_key_name = "OPENROUTER_API_KEY"
M.endpoint = "https://api.openrouter.ai/api/v1"
M.model = "openai/gpt-4o-mini" -- Cost-effective default model

-- Request configuration
M.timeout = 30000 -- 30 seconds
M.context_window = 128000
M.extra_request_body = {
  temperature = 0.75,
  max_tokens = 4096,
}

return M