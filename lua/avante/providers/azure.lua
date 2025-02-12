---@class AvanteAzureProvider: AvanteDefaultBaseProvider
---@field deployment string
---@field api_version string
---@field temperature number
---@field max_tokens number

local Utils = require("avante.utils")
local P = require("avante.providers")
local O = require("avante.providers").openai

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "AZURE_OPENAI_API_KEY"

M.parse_messages = O.parse_messages
M.parse_response = O.parse_response
M.parse_response_without_stream = O.parse_response_without_stream

M.parse_curl_args = function(provider, prompt_opts)
  local provider_conf, request_body = P.parse_config(provider)

  local headers = {
    ["Content-Type"] = "application/json",
  }
  if P.env.require_api_key(provider_conf) then headers["api-key"] = provider.parse_api_key() end

  -- NOTE: When using "o" series set the supported parameters only
  if O.is_o_series_model(provider_conf.model) then
    request_body.max_tokens = nil
    request_body.temperature = 1
  end

  return {
    url = Utils.url_join(
      provider_conf.endpoint,
      "/openai/deployments/"
        .. provider_conf.deployment
        .. "/chat/completions?api-version="
        .. provider_conf.api_version
    ),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      messages = M.parse_messages(prompt_opts),
      stream = true,
    }, request_body),
  }
end

return M
