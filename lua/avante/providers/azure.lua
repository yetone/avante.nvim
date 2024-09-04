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

M.parse_message = O.parse_message
M.parse_response = O.parse_response

M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  local headers = {
    ["Content-Type"] = "application/json",
  }
  if not P.env.is_local("azure") then headers["api-key"] = provider.parse_api_key() end

  return {
    url = Utils.trim(base.endpoint, { suffix = "/" })
      .. "/openai/deployments/"
      .. base.deployment
      .. "/chat/completions?api-version="
      .. base.api_version,
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      messages = M.parse_message(code_opts),
      stream = true,
    }, body_opts),
  }
end

return M
