local Utils = require("avante.utils")
local P = require("avante.providers")

---@alias CohereFinishReason "COMPLETE" | "LENGTH" | "ERROR"
---@alias CohereStreamType "message-start" | "content-start" | "content-delta" | "content-end" | "message-end"
---
---@class CohereChatContent
---@field type? CohereStreamType
---@field text string
---
---@class CohereChatMessage
---@field content CohereChatContent
---
---@class CohereChatStreamBase
---@field type CohereStreamType
---@field index integer
---
---@class CohereChatContentDelta: CohereChatStreamBase
---@field type "content-delta" | "content-start" | "content-end"
---@field delta? { message: CohereChatMessage }
---
---@class CohereChatMessageStart: CohereChatStreamBase
---@field type "message-start"
---@field delta { message: { role: "assistant" } }
---
---@class CohereChatMessageEnd: CohereChatStreamBase
---@field type "message-end"
---@field delta { finish_reason: CohereFinishReason, usage: CohereChatUsage }
---
---@class CohereChatUsage
---@field billed_units { input_tokens: integer, output_tokens: integer }
---@field tokens { input_tokens: integer, output_tokens: integer }
---
---@alias CohereChatResponse CohereChatContentDelta | CohereChatMessageStart | CohereChatMessageEnd
---
---@class CohereMessage
---@field type "text"
---@field text string
---
---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "CO_API_KEY"
M.tokenizer_id = "https://storage.googleapis.com/cohere-public/tokenizers/command-r-08-2024.json"
M.role_map = {
  user = "user",
  assistant = "assistant",
}

function M:is_disable_stream() return false end

function M:parse_messages(opts)
  local messages = {
    { role = "system", content = opts.system_prompt },
  }
  vim
    .iter(opts.messages)
    :each(function(msg) table.insert(messages, { role = M.role_map[msg.role], content = msg.content }) end)
  return { messages = messages }
end

function M:parse_stream_data(ctx, data, opts)
  ---@type CohereChatResponse
  local json = vim.json.decode(data)
  if json.type ~= nil then
    if json.type == "message-end" and json.delta.finish_reason == "COMPLETE" then
      opts.on_stop({ reason = "complete" })
      return
    end
    if json.type == "content-delta" then opts.on_chunk(json.delta.message.content.text) end
  end
end

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)

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
  if P.env.require_api_key(provider_conf) then headers["Authorization"] = "Bearer " .. self.parse_api_key() end

  return {
    url = Utils.url_join(provider_conf.endpoint, "/chat"),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = provider_conf.model,
      stream = true,
    }, self:parse_messages(prompt_opts), request_body),
  }
end

function M.setup()
  P.env.parse_envvar(M)
  require("avante.tokenizers").setup(M.tokenizer_id, false)
  vim.g.avante_login = true
end

return M
