local Utils = require("avante.utils")
local P = require("avante.providers")

---@class AvanteBedrockProviderFunctor
local M = {}

M.api_key_name = "BEDROCK_KEYS"

---@class AWSCreds
---@field access_key_id string
---@field secret_access_key string
---@field session_token string
local AWSCreds = {}

M = setmetatable(M, {
  __index = function(_, k)
    local model_handler = M.load_model_handler()
    return model_handler[k]
  end,
})

function M.setup()
  -- Check if AWS CLI is installed
  if not M.check_aws_cli_installed() then
    Utils.error(
      "AWS CLI not found. Please install it to use the Bedrock provider: https://aws.amazon.com/cli/",
      { once = true, title = "Avante Bedrock" }
    )
    return false
  end

  -- Check if curl supports AWS signature v4
  if not M.check_curl_supports_aws_sig() then
    Utils.error(
      "Your curl version doesn't support AWS signature v4 properly. Please upgrade to curl 8.10.0 or newer.",
      { once = true, title = "Avante Bedrock" }
    )
    return false
  end

  return true
end

function M.load_model_handler()
  local provider_conf, _ = P.parse_config(P["bedrock"])
  local bedrock_model = provider_conf.model
  if provider_conf.model:match("anthropic") then bedrock_model = "claude" end

  local ok, model_module = pcall(require, "avante.providers.bedrock." .. bedrock_model)
  if ok then return model_module end
  local error_msg = "Bedrock model handler not found: " .. bedrock_model
  error(error_msg)
end

function M:parse_messages(prompt_opts)
  local model_handler = M.load_model_handler()
  return model_handler.parse_messages(self, prompt_opts)
end

function M:parse_response(ctx, data_stream, event_state, opts)
  local model_handler = M.load_model_handler()
  return model_handler.parse_response(self, ctx, data_stream, event_state, opts)
end

function M:transform_tool(tool)
  local model_handler = M.load_model_handler()
  return model_handler.transform_tool(self, tool)
end

function M:build_bedrock_payload(prompt_opts, request_body)
  local model_handler = M.load_model_handler()
  return model_handler.build_bedrock_payload(self, prompt_opts, request_body)
end

function M:parse_stream_data(ctx, data, opts)
  -- @NOTE: Decode and process Bedrock response
  -- Each response contains a Base64-encoded `bytes` field, which is decoded into JSON.
  -- The `type` field in the decoded JSON determines how the response is handled.
  local bedrock_match = data:gmatch("event(%b{})")
  for bedrock_data_match in bedrock_match do
    local jsn = vim.json.decode(bedrock_data_match)
    local data_stream = vim.base64.decode(jsn.bytes)
    local json = vim.json.decode(data_stream)
    self:parse_response(ctx, data_stream, json.type, opts)
  end
end

function M:parse_response_without_stream(data, event_state, opts)
  if opts.on_chunk == nil then return end
  local bedrock_match = data:gmatch("exception(%b{})")
  opts.on_chunk("\n**Exception caught**\n\n")
  for bedrock_data_match in bedrock_match do
    local jsn = vim.json.decode(bedrock_data_match)
    opts.on_chunk("- " .. jsn.message .. "\n")
  end
  vim.schedule(function() opts.on_stop({ reason = "complete" }) end)
end

---@param prompt_opts AvantePromptOptions
---@return table
function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)

  local access_key_id, secret_access_key, session_token, region

  -- try to parse credentials from api key
  local api_key = self.parse_api_key()
  if api_key ~= nil then
    local parts = vim.split(api_key, ",")
    access_key_id = parts[1]
    secret_access_key = parts[2]
    region = parts[3]
    session_token = parts[4]
  else
    -- alternatively parse credentials from default AWS credentials provider chain

    ---@diagnostic disable-next-line: undefined-field
    region = provider_conf.aws_region
    ---@diagnostic disable-next-line: undefined-field
    local profile = provider_conf.aws_profile

    local awsCreds = M:get_aws_credentials(region, profile)
    if not region or region == "" then error("No aws_region specified in bedrock config") end

    access_key_id = awsCreds.access_key_id
    secret_access_key = awsCreds.secret_access_key
    session_token = awsCreds.session_token
  end

  local endpoint
  if provider_conf.endpoint then
    -- Use custom endpoint if provided
    endpoint = provider_conf.endpoint
  else
    -- Default to AWS Bedrock endpoint
    endpoint = string.format(
      "https://bedrock-runtime.%s.amazonaws.com/model/%s/invoke-with-response-stream",
      region,
      provider_conf.model
    )
  end

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if session_token and session_token ~= "" then headers["x-amz-security-token"] = session_token end

  local body_payload = self:build_bedrock_payload(prompt_opts, request_body)

  local rawArgs = {
    "--aws-sigv4",
    string.format("aws:amz:%s:bedrock", region),
    "--user",
    string.format("%s:%s", access_key_id, secret_access_key),
  }

  return {
    url = endpoint,
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = Utils.tbl_override(headers, self.extra_headers),
    body = body_payload,
    rawArgs = rawArgs,
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

--- Run a command and capture its output. Time out after 10 seconds
---@param ... string Command and its arguments
---@return string stdout
---@return integer exit code (0 for success, 124 for timeout, etc)
local function run_command(...)
  local args = { ... }
  local result = vim.system(args, { text = true }):wait(10000) -- Wait up to 10 seconds
  -- result.code will be 124 if the command times out.
  return result.stdout, result.code
end

--- get_aws_credentials returns aws credentials using the aws cli
---@param region string
---@param profile string
---@return AWSCreds
function M:get_aws_credentials(region, profile)
  local awsCreds = {
    access_key_id = "",
    secret_access_key = "",
    session_token = "",
  }

  local args = { "aws", "configure", "export-credentials" }

  if profile and profile ~= "" then
    table.insert(args, "--profile")
    table.insert(args, profile)
  end

  if region and region ~= "" then
    table.insert(args, "--region")
    table.insert(args, region)
  end

  -- run aws configure export-credentials and capture the json output
  local start_time = vim.uv.hrtime()
  local output, exit_code = run_command(unpack(args))

  if exit_code == 0 then
    local credentials = vim.json.decode(output)
    awsCreds.access_key_id = credentials.AccessKeyId
    awsCreds.secret_access_key = credentials.SecretAccessKey
    awsCreds.session_token = credentials.SessionToken
  else
    print("Failed to run AWS command")
  end

  local end_time = vim.uv.hrtime()
  local duration_ms = (end_time - start_time) / 1000000
  Utils.debug(string.format("AWS credentials fetch took %.2f ms", duration_ms))

  return awsCreds
end

--- check_aws_cli_installed returns true when the aws cli is installed
--- @return boolean
function M.check_aws_cli_installed()
  local _, exit_code = run_command("aws", "--version")
  return exit_code == 0
end

--- check_curl_version_supports_aws_sig checks if the given curl version supports aws sigv4 correctly
--- we require at least version 8.10.0 because it contains critical fixes for aws sigv4 support
--- https://curl.se/ch/8.10.0.html
--- @param version_string string The curl version string to check
--- @return boolean
function M.check_curl_version_supports_aws_sig(version_string)
  -- Extract the version number
  local major, minor = version_string:match("curl (%d+)%.(%d+)")

  if major and minor then
    major = tonumber(major)
    minor = tonumber(minor)

    -- Check if the version is at least 8.10
    if major > 8 or (major == 8 and minor >= 10) then return true end
  end

  return false
end

--- check_curl_supports_aws_sig returns true when the installed curl version supports aws sigv4
--- @return boolean
function M.check_curl_supports_aws_sig()
  local output, exit_code = run_command("curl", "--version")
  if exit_code ~= 0 then return false end

  -- Get first line of output which contains version info
  local version_string = output:match("^[^\n]+")
  return M.check_curl_version_supports_aws_sig(version_string)
end

return M
