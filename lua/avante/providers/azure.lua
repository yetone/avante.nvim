---@class AvanteAzureProvider: AvanteDefaultBaseProvider
---@field deployment string
---@field api_version string
---@field temperature number
---@field max_completion_tokens number
---@field reasoning_effort? string

local Utils = require("avante.utils")
local P = require("avante.providers")
local O = require("avante.providers").openai

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "AZURE_OPENAI_API_KEY"

-- Inherit from OpenAI class
setmetatable(M, { __index = O })

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

  self.set_allowed_params(provider_conf, request_body)

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
