local P = require("avante.providers")
local Utils = require("avante.utils")
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
M.transform_to_function_declaration = Gemini.transform_to_function_declaration

local function execute_command(command)
  local handle = io.popen(command .. " 2>/dev/null")
  if not handle then error("Failed to execute command: " .. command) end
  local result = handle:read("*a")
  handle:close()
  return result:match("^%s*(.-)%s*$")
end

local function parse_cmd(cmd_input, error_msg)
  if not cmd_input:match("^cmd:") then
    if not error_msg then
      error("Invalid cmd: Expected 'cmd:<command>' format, got '" .. cmd_input .. "'")
    else
      error(error_msg)
    end
  end
  local command = cmd_input:sub(5)
  local direct_output = execute_command(command)
  return direct_output
end

function M.parse_api_key()
  return parse_cmd(
    M.api_key_name,
    "Invalid api_key_name: Expected 'cmd:<command>' format, got '" .. M.api_key_name .. "'"
  )
end

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)

  local model_id = provider_conf.model or "default-model-id"
  local project_id = parse_cmd("cmd:gcloud config get-value project")
  local location = vim.fn.getenv("GOOGLE_CLOUD_LOCATION") -- same as gemini-cli

  if project_id == nil or project_id == vim.NIL then project_id = "default-project-id" end
  if location == nil or location == vim.NIL then location = "global" end

  local url = provider_conf.endpoint:gsub("LOCATION", location):gsub("PROJECT_ID", project_id)
  url = string.format("%s/%s:streamGenerateContent?alt=sse", url, model_id)

  local bearer_token = M.parse_api_key()

  return {
    url = url,
    headers = Utils.tbl_override({
      ["Authorization"] = "Bearer " .. bearer_token,
      ["Content-Type"] = "application/json; charset=utf-8",
    }, self.extra_headers),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    body = Gemini.prepare_request_body(self, prompt_opts, provider_conf, request_body),
  }
end

return M
