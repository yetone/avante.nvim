local Utils = require("avante.utils")
local P = require("avante.providers")

---@alias AvanteBedrockPayloadBuilder fun(prompt_opts: AvantePromptOptions, body_opts: table<string, any>): table<string, any>
---
---@class AvanteBedrockModelHandler
---@field role_map table<"user" | "assistant", string>
---@field parse_messages AvanteMessagesParser
---@field parse_response AvanteResponseParser
---@field build_bedrock_payload AvanteBedrockPayloadBuilder

---@class AvanteBedrockProviderFunctor
local M = {}

M.api_key_name = "BEDROCK_KEYS"
M.use_xml_format = true

M.load_model_handler = function()
  local provider_conf, _ = P.parse_config(P["bedrock"])
  local bedrock_model = provider_conf.model
  if provider_conf.model:match("anthropic") then bedrock_model = "claude" end

  local ok, model_module = pcall(require, "avante.providers.bedrock." .. bedrock_model)
  if ok then return model_module end
  local error_msg = "Bedrock model handler not found: " .. bedrock_model
  error(error_msg)
end

M.parse_response = function(ctx, data_stream, event_state, opts)
  local model_handler = M.load_model_handler()
  return model_handler.parse_response(ctx, data_stream, event_state, opts)
end

M.build_bedrock_payload = function(prompt_opts, body_opts)
  local model_handler = M.load_model_handler()
  return model_handler.build_bedrock_payload(prompt_opts, body_opts)
end

M.parse_stream_data = function(data, opts)
  -- @NOTE: Decode and process Bedrock response
  -- Each response contains a Base64-encoded `bytes` field, which is decoded into JSON.
  -- The `type` field in the decoded JSON determines how the response is handled.
  local bedrock_match = data:gmatch("event(%b{})")
  for bedrock_data_match in bedrock_match do
    local jsn = vim.json.decode(bedrock_data_match)
    local data_stream = vim.base64.decode(jsn.bytes)
    local json = vim.json.decode(data_stream)
    M.parse_response({}, data_stream, json.type, opts)
  end
end

---@param provider AvanteBedrockProviderFunctor
---@param prompt_opts AvantePromptOptions
---@return table
M.parse_curl_args = function(provider, prompt_opts)
  local base, body_opts = P.parse_config(provider)

  local api_key = provider.parse_api_key()
  if api_key == nil then error("Cannot get the bedrock api key!") end
  local parts = vim.split(api_key, ",")
  local aws_access_key_id = parts[1]
  local aws_secret_access_key = parts[2]
  local aws_region = parts[3]
  local aws_session_token = parts[4]

  local endpoint = string.format(
    "https://bedrock-runtime.%s.amazonaws.com/model/%s/invoke-with-response-stream",
    aws_region,
    base.model
  )

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if aws_session_token and aws_session_token ~= "" then headers["x-amz-security-token"] = aws_session_token end

  local body_payload = M.build_bedrock_payload(prompt_opts, body_opts)

  local rawArgs = {
    "--aws-sigv4",
    string.format("aws:amz:%s:bedrock", aws_region),
    "--user",
    string.format("%s:%s", aws_access_key_id, aws_secret_access_key),
  }

  return {
    url = endpoint,
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = headers,
    body = body_payload,
    rawArgs = rawArgs,
  }
end

M.on_error = function(result)
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
