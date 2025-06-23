---@class AvanteAzureDatabricksExtraRequestBody
---@field temperature number
---@field max_tokens number

---@class AvanteAzureDatabricksProvider: AvanteDefaultBaseProvider
---@field databricks_base_url string
---@field extra_request_body AvanteAzureDatabricksExtraRequestBody

local Utils = require("avante.utils")
local P = require("avante.providers")
local O = require("avante.providers").openai

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "DATABRICKS_TOKEN"

-- Inherit from OpenAI class since Databricks uses OpenAI-compatible API
setmetatable(M, { __index = O })

function M.set_allowed_params(provider_conf, request_body)
  -- Databricks doesn't support max_completion_tokens, use max_tokens instead
  if request_body.max_completion_tokens then
    request_body.max_tokens = request_body.max_completion_tokens
    request_body.max_completion_tokens = nil
  end
  -- Remove unsupported parameters
  request_body.reasoning_effort = nil
  request_body.stream_options = nil
end

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)
  local disable_tools = provider_conf.disable_tools or false

  -- Validate endpoint configuration
  if not provider_conf.endpoint or provider_conf.endpoint == "" then
    error(
      'Azure Databricks endpoint is not configured. Please set the endpoint in your provider configuration.\nExample: endpoint = "https://adb-2222222222222222.2.azuredatabricks.net/serving-endpoints"'
    )
  end

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if P.env.require_api_key(provider_conf) then
    local api_key = self.parse_api_key()
    if api_key == nil then
      error(
        "Databricks API token is not set, please set it in your DATABRICKS_TOKEN environment variable or config file"
      )
    end
    headers["Authorization"] = "Bearer " .. api_key
  end

  self.set_allowed_params(provider_conf, request_body)

  local use_ReAct_prompt = provider_conf.use_ReAct_prompt == true

  local tools = nil
  if not disable_tools and prompt_opts.tools and not use_ReAct_prompt then
    tools = {}
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, self:transform_tool(tool))
    end
  end

  return {
    url = Utils.url_join(provider_conf.endpoint, "/chat/completions"),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = Utils.tbl_override(headers, self.extra_headers),
    body = vim.tbl_deep_extend("force", {
      model = provider_conf.model,
      messages = self:parse_messages(prompt_opts),
      stream = true,
      tools = tools,
    }, request_body),
  }
end

return M
