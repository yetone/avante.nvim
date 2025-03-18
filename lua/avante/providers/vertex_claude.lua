local P = require("avante.providers")
local Vertex = require("avante.providers.vertex")

---@class AvanteProviderFunctor
local M = {}

M.role_map = {
  user = "user",
  assistant = "assistant",
}

M.is_disable_stream = P.claude.is_disable_stream
M.parse_messages = P.claude.parse_messages
M.parse_response = P.claude.parse_response
M.parse_api_key = Vertex.parse_api_key
M.on_error = Vertex.on_error

Vertex.api_key_name = "cmd:gcloud auth print-access-token"

---@param prompt_opts AvantePromptOptions
function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)
  local disable_tools = provider_conf.disable_tools or false
  local location = vim.fn.getenv("LOCATION")
  local project_id = vim.fn.getenv("PROJECT_ID")
  local model_id = provider_conf.model or "default-model-id"
  if location == nil or location == vim.NIL then location = "default-location" end
  if project_id == nil or project_id == vim.NIL then project_id = "default-project-id" end
  local url = provider_conf.endpoint:gsub("LOCATION", location):gsub("PROJECT_ID", project_id)

  url = string.format("%s/%s:streamRawPredict", url, model_id)

  local system_prompt = prompt_opts.system_prompt or ""
  local messages = self:parse_messages(prompt_opts)

  local tools = {}
  if not disable_tools and prompt_opts.tools then
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, P.claude:transform_tool(tool))
    end
  end

  if self.support_prompt_caching and #tools > 0 then
    local last_tool = vim.deepcopy(tools[#tools])
    last_tool.cache_control = { type = "ephemeral" }
    tools[#tools] = last_tool
  end

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
    tools = tools,
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
