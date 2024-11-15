local P = require("avante.providers")
local Gemini = require("avante.providers.gemini")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "cmd:gcloud auth application-default print-access-token"

M.role_map = {
  user = "user",
  assistant = "model",
}

M.parse_messages = Gemini.parse_messages
M.parse_response = Gemini.parse_response

local function execute_command(command)
  local handle = io.popen(command)
  local result = handle:read("*a")
  handle:close()
  return result:match("^%s*(.-)%s*$")
end

M.parse_api_key = function()
  if M.api_key_name:match("^cmd:") then
    local command = M.api_key_name:sub(5)
    return execute_command(command)
  else
    return vim.fn.getenv(M.api_key_name)
  end
end

M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)
  local location = vim.fn.getenv("LOCATION") or "default-location"
  local project_id = vim.fn.getenv("PROJECT_ID") or "default-project-id"
  local model_id = base.model or "default-model-id"
  local url = base.endpoint:gsub("LOCATION", location):gsub("PROJECT_ID", project_id)

  url = string.format("%s/%s:streamGenerateContent?alt=sse", url, model_id)

  body_opts = vim.tbl_deep_extend("force", body_opts, {
    generationConfig = {
      temperature = body_opts.temperature,
      maxOutputTokens = body_opts.max_tokens,
    },
  })
  body_opts.temperature = nil
  body_opts.max_tokens = nil
  return {
    url = url,
    headers = {
      ["Authorization"] = "Bearer " .. M.parse_api_key(),
      ["Content-Type"] = "application/json; charset=utf-8",
    },
    proxy = base.proxy,
    insecure = base.allow_insecure,
    body = vim.tbl_deep_extend("force", {}, M.parse_messages(code_opts), body_opts),
  }
end

return M
