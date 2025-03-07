local P = require("avante.providers")
local Claude = require("avante.providers.claude")
local Vertex = require("avante.providers.vertex")

---@class AvanteProviderFunctor
local M = {}
M.role_map = {
  user = "user",
  assistant = "assistant",
}

M.use_xml_format = true
M.is_disable_stream = Claude.is_disable_stream
M.parse_messages = Claude.parse_messages
M.parse_response = Claude.parse_response
M.parse_api_key = Vertex.parse_api_key
M.on_error = Vertex.on_error

Vertex.api_key_name = "cmd:gcloud auth print-access-token"

---@param provider AvanteProviderFunctor
---@param prompt_opts AvantePromptOptions
---@return table
function M:parse_curl_args(provider, prompt_opts)
  local provider_conf, request_body = P.parse_config(provider)
  local location = vim.fn.getenv("LOCATION")
  local project_id = vim.fn.getenv("PROJECT_ID")
  local model_id = provider_conf.model or "default-model-id"
  if location == nil or location == vim.NIL then location = "default-location" end
  if project_id == nil or project_id == vim.NIL then project_id = "default-project-id" end
  local url = provider_conf.endpoint:gsub("LOCATION", location):gsub("PROJECT_ID", project_id)

  url = string.format("%s/%s:streamRawPredict", url, model_id)

  local system_prompt = prompt_opts.system_prompt or ""
  local messages = self:parse_messages(prompt_opts)
  request_body = vim.tbl_deep_extend("force", request_body, {
    anthropic_version = "vertex-2023-10-16",
    temperature = 0,
    max_tokens = 4096,
    stream = true,
    messages = messages,
    system = {
      {
        type = "text",
        text = system_prompt,
        cache_control = { type = "ephemeral" },
      },
    },
  })
  return {
    url = url,
    headers = {
      ["Authorization"] = "Bearer " .. Vertex.parse_api_key(),
      ["Content-Type"] = "application/json; charset=utf-8",
    },
    body = vim.tbl_deep_extend("force", {}, request_body),
  }
end

return M
