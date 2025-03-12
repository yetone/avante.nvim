local P = require("avante.providers")
local Gemini = require("avante.providers.gemini")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "cmd:gcloud auth application-default print-access-token"

M.role_map = {
  user = "user",
  assistant = "model",
}

M.is_disable_stream = Gemini.is_disable_stream
M.parse_messages = Gemini.parse_messages
M.parse_response = Gemini.parse_response

local function execute_command(command)
  local handle = io.popen(command)
  if not handle then error("Failed to execute command: " .. command) end
  local result = handle:read("*a")
  handle:close()
  return result:match("^%s*(.-)%s*$")
end

function M.parse_api_key()
  if not M.api_key_name:match("^cmd:") then
    error("Invalid api_key_name: Expected 'cmd:<command>' format, got '" .. M.api_key_name .. "'")
  end
  local command = M.api_key_name:sub(5)
  local direct_output = execute_command(command)
  return direct_output
end

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)
  local location = vim.fn.getenv("LOCATION")
  local project_id = vim.fn.getenv("PROJECT_ID")
  local model_id = provider_conf.model or "default-model-id"
  if location == nil or location == vim.NIL then location = "default-location" end
  if project_id == nil or project_id == vim.NIL then project_id = "default-project-id" end
  local url = provider_conf.endpoint:gsub("LOCATION", location):gsub("PROJECT_ID", project_id)

  url = string.format("%s/%s:streamGenerateContent?alt=sse", url, model_id)

  request_body = vim.tbl_deep_extend("force", request_body, {
    generationConfig = {
      temperature = request_body.temperature,
      maxOutputTokens = request_body.max_tokens,
    },
  })
  request_body.temperature = nil
  request_body.max_tokens = nil
  local bearer_token = M.parse_api_key()

  return {
    url = url,
    headers = {
      ["Authorization"] = "Bearer " .. bearer_token,
      ["Content-Type"] = "application/json; charset=utf-8",
    },
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    body = vim.tbl_deep_extend("force", {}, self:parse_messages(prompt_opts), request_body),
  }
end

return M
