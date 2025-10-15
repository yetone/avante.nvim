---@class AvanteAzureExtraRequestBody
---@field temperature number
---@field max_completion_tokens number
---@field reasoning_effort? string

---@class AvanteAzureProvider: AvanteDefaultBaseProvider
---@field deployment string
---@field api_version string
---@field extra_request_body AvanteAzureExtraRequestBody

local Utils = require("avante.utils")
local P = require("avante.providers")
local O = require("avante.providers").openai

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "AZURE_OPENAI_API_KEY"

-- Inherit from OpenAI class
setmetatable(M, { __index = O })

---@param prompt_opts AvantePromptOptions
---@return AvanteCurlOutput|nil
function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)
  local disable_tools = provider_conf.disable_tools or false

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if P.env.require_api_key(provider_conf) then
    local api_key = self.parse_api_key()
    if not api_key then
      Utils.error("Azure: API key is not set. Please set " .. M.api_key_name)
      return nil
    end
    if provider_conf.entra then
      headers["Authorization"] = "Bearer " .. api_key
    else
      headers["api-key"] = api_key
    end
  end

  self.set_allowed_params(provider_conf, request_body)

  local tools = nil
  if not disable_tools and prompt_opts.tools then
    tools = {}
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, self:transform_tool(tool))
    end
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
    headers = Utils.tbl_override(headers, self.extra_headers),
    body = vim.tbl_deep_extend("force", {
      messages = self:parse_messages(prompt_opts),
      stream = true,
      tools = tools,
    }, request_body),
  }
end

return M
