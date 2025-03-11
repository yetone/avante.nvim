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
M.is_disable_stream = O.is_disable_stream
M.is_o_series_model = O.is_o_series_model
M.role_map = O.role_map

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if P.env.require_api_key(provider_conf) then
    if provider_conf.entra then
      headers["Authorization"] = "Bearer " .. self.parse_api_key()
    else
      headers["api-key"] = self.parse_api_key()
    end
  end

  -- NOTE: When using "o" series set the supported parameters only
  if O.is_o_series_model(provider_conf.model) then
    request_body.max_tokens = nil
    request_body.temperature = 1
  end

  return {
    url = Utils.url_join(
      provider_conf.endpoint,
      "/openai/deployments/"
        ---@diagnostic disable-next-line: undefined-field
        .. provider_conf.deployment
        .. "/chat/completions?api-version="
        ---@diagnostic disable-next-line: undefined-field
        .. provider_conf.api_version
    ),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      messages = self:parse_messages(prompt_opts),
      stream = true,
    }, request_body),
  }
end

return M
