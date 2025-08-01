---@class AvanteAzureNextGenModelConfig
---@field deployment string The Azure deployment name
---@field openai_model? string The base OpenAI model to inherit defaults from
---@field display_name? string Display name for the model selector

---@class AvanteAzureNextGenProvider: AvanteDefaultBaseProvider
-- This provider inherits all fields from the openai provider and reuses its logic.
-- It only overrides the request format to match Azure's next-gen API requirements.
---@field models table<string, AvanteAzureNextGenModelConfig>

local Utils = require("avante.utils")
local P = require("avante.providers")
local O = require("avante.providers").openai -- The parent 'openai' provider
local Config = require("avante.config")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "AZURE_OPENAI_API_KEY"

-- Inherit all functions and fields from the OpenAI provider
setmetatable(M, { __index = O })

---@param model_name string
---@return table
local function apply_model_inheritance(self, model_name)
  local provider_conf, _ = P.parse_config(self)
  if not provider_conf.models or not provider_conf.models[model_name] then
    return {}
  end
  
  local model_config = provider_conf.models[model_name]
  if not model_config.openai_model then
    return {}
  end
  
  -- Get the base OpenAI model defaults from the config
  local openai_config = Config._defaults.providers.openai
  if not openai_config then return {} end
  
  -- Return inherited defaults that can be merged
  return {
    context_window = openai_config.context_window,
    extra_request_body = vim.deepcopy(openai_config.extra_request_body),
    timeout = openai_config.timeout,
  }
end

-- Override the request-building function to add Azure-specific modifications
function M:parse_curl_args(prompt_opts)
  -- Apply Azure-specific model inheritance before calling parent
  local provider_conf, _ = P.parse_config(self)
  local current_model = provider_conf.model
  local inherited_config = apply_model_inheritance(self, current_model)
  
  -- Temporarily merge inherited config into self for the parent call
  local original_extra_request_body = self.extra_request_body
  local original_context_window = self.context_window
  local original_timeout = self.timeout
  
  if inherited_config.extra_request_body then
    self.extra_request_body = vim.tbl_deep_extend("keep", 
      self.extra_request_body or {}, 
      inherited_config.extra_request_body)
  end
  if inherited_config.context_window then
    self.context_window = inherited_config.context_window
  end
  if inherited_config.timeout then
    self.timeout = inherited_config.timeout
  end
  
  -- 1. Call the parent 'openai' provider's function first.
  -- This gives us a standard OpenAI request structure, including the body,
  -- model-specific options, tools, etc. It reuses all the complex logic.
  local curl_args = O.parse_curl_args(self, prompt_opts)
  
  -- Restore original config
  self.extra_request_body = original_extra_request_body
  self.context_window = original_context_window
  self.timeout = original_timeout

  -- 2. Now, modify the result to fit Azure's next-gen API requirements.
  local api_key = self:parse_api_key()

  -- 2a. Change the authentication header from 'Authorization: Bearer' to 'api-key'.
  curl_args.headers["api-key"] = api_key
  curl_args.headers["Authorization"] = nil -- Remove the original header

  -- 2b. Add the required 'api-version' to the URL.
  -- The base URL already comes from the parent function.
  local api_version = self.api_version or "preview"
  curl_args.url = curl_args.url .. "?api-version=" .. api_version"

  -- 3. Return the fully-formed, Azure-compatible request arguments.
  return curl_args
end

return M