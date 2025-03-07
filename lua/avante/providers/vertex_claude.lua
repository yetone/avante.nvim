local P = require("avante.providers")
local Utils = require("avante.utils")
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
Vertex.api_key_name = "cmd:gcloud auth print-access-token"

---@param provider AvanteProviderFunctor
---@param prompt_opts AvantePromptOptions
---@return table
function M:parse_curl_args(provider, prompt_opts)
  local provider_conf, request_body = P.parse_config(provider)
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
        text = prompt_opts.system_prompt,
        cache_control = { type = "ephemeral" },
      },
    },
  })
  return {
    url = provider_conf.endpoint .. "/" .. provider_conf.model .. ":streamRawPredict",
    headers = {
      ["Authorization"] = "Bearer " .. Vertex.parse_api_key(),
      ["Content-Type"] = "application/json; charset=utf-8",
    },
    body = vim.tbl_deep_extend("force", {}, request_body),
  }
end

function M.on_error(result)
  if not result.body then
    return Utils.error("API request failed with status " .. result.status, { once = true, title = "Avante" })
  end

  local ok, body = pcall(vim.json.decode, result.body)
  if not (ok and body and body.error) then
    return Utils.error("Failed to parse error response", { once = true, title = "Avante" })
  end

  local error_msg = body.error.message

  Utils.error(error_msg, { once = true, title = "Avante" })
end
return M
