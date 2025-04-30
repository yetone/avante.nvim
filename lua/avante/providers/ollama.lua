local Utils = require("avante.utils")
local P = require("avante.providers")
local Config = require("avante.config")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "" -- Ollama typically doesn't require API keys for local use

M.role_map = {
  user = "user",
  assistant = "assistant",
}

M.parse_messages = P.openai.parse_messages
M.is_reasoning_model = P.openai.is_reasoning_model

function M:is_disable_stream() return false end

function M:parse_stream_data(ctx, data, opts)
  local ok, json_data = pcall(vim.json.decode, data)
  if not ok or not json_data then
    -- Add debug logging
    Utils.debug("Failed to parse JSON", data)
    return
  end

  if json_data.message and json_data.message.content then
    local content = json_data.message.content
    P.openai:add_text_message(ctx, content, "generating", opts)
    if content and content ~= "" and opts.on_chunk then opts.on_chunk(content) end
  end

  if json_data.done then
    P.openai:finish_pending_messages(ctx, opts)
    opts.on_stop({ reason = "complete" })
    return
  end
end

---@param prompt_opts AvantePromptOptions
function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)
  local keep_alive = provider_conf.keep_alive or "5m"

  if not provider_conf.model or provider_conf.model == "" then error("Ollama model must be specified in config") end
  if not provider_conf.endpoint then error("Ollama requires endpoint configuration") end
  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }

  if P.env.require_api_key(provider_conf) then
    local api_key = self.parse_api_key()
    if api_key and api_key ~= "" then
      headers["Authorization"] = "Bearer " .. api_key
    else
      Utils.info((Config.provider or "Provider") .. ": API key not set, continuing without authentication")
    end
  end

  return {
    url = Utils.url_join(provider_conf.endpoint, "/api/chat"),
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = provider_conf.model,
      messages = self:parse_messages(prompt_opts),
      stream = true,
      system = prompt_opts.system_prompt,
      keep_alive = keep_alive,
    }, request_body),
  }
end

---@param result table
M.on_error = function(result)
  local error_msg = "Ollama API error"
  if result.body then
    local ok, body = pcall(vim.json.decode, result.body)
    if ok and body.error then error_msg = body.error end
  end
  Utils.error(error_msg, { title = "Ollama" })
end

return M
