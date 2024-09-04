local Utils = require("avante.utils")
local P = require("avante.providers")

---@alias CohereFinishReason "COMPLETE" | "LENGTH" | "ERROR"
---
---@class CohereChatStreamResponse
---@field event_type "stream-start" | "text-generation" | "stream-end"
---@field is_finished boolean
---
---@class CohereTextGenerationResponse: CohereChatStreamResponse
---@field text string
---
---@class CohereStreamEndResponse: CohereChatStreamResponse
---@field response CohereChatResponse
---@field finish_reason CohereFinishReason
---
---@class CohereChatResponse
---@field text string
---@field generation_id string
---@field chat_history CohereMessage[]
---@field finish_reason CohereFinishReason
---@field meta {api_version: {version: integer}, billed_units: {input_tokens: integer, output_tokens: integer}, tokens: {input_tokens: integer, output_tokens: integer}}
---
---@class CohereMessage
---@field role? "USER" | "SYSTEM" | "CHATBOT"
---@field message string
---
---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "CO_API_KEY"
M.tokenizer_id = "CohereForAI/c4ai-command-r-plus-08-2024"

M.parse_message = function(opts)
  return {
    preamble = opts.system_prompt,
    message = table.concat(opts.user_prompts, "\n"),
  }
end

M.parse_stream_data = function(data, opts)
  ---@type CohereChatStreamResponse
  local json = vim.json.decode(data)
  if json.is_finished then
    opts.on_complete(nil)
    return
  end
  if json.event_type ~= nil then
    ---@cast json CohereStreamEndResponse
    if json.event_type == "stream-end" and json.finish_reason == "COMPLETE" then
      opts.on_complete(nil)
      return
    end
    ---@cast json CohereTextGenerationResponse
    if json.event_type == "text-generation" then opts.on_chunk(json.text) end
  end
end

M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
    ["X-Client-Name"] = "avante.nvim/Neovim/"
      .. vim.version().major
      .. "."
      .. vim.version().minor
      .. "."
      .. vim.version().patch,
  }
  if not P.env.is_local("cohere") then headers["Authorization"] = "Bearer " .. provider.parse_api_key() end

  return {
    url = Utils.trim(base.endpoint, { suffix = "/" }) .. "/chat",
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = base.model,
      stream = true,
    }, M.parse_message(code_opts), body_opts),
  }
end

return M
