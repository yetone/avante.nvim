local Utils = require("avante.utils")
local Config = require("avante.config")
local Clipboard = require("avante.clipboard")
local P = require("avante.providers")

---@class OpenAIChatResponse
---@field id string
---@field object "chat.completion" | "chat.completion.chunk"
---@field created integer
---@field model string
---@field system_fingerprint string
---@field choices? OpenAIResponseChoice[] | OpenAIResponseChoiceComplete[]
---@field usage {prompt_tokens: integer, completion_tokens: integer, total_tokens: integer}
---
---@class OpenAIResponseChoice
---@field index integer
---@field delta OpenAIMessage
---@field logprobs? integer
---@field finish_reason? "stop" | "length"
---
---@class OpenAIResponseChoiceComplete
---@field message OpenAIMessage
---@field finish_reason "stop" | "length" | "eos_token"
---@field index integer
---@field logprobs integer
---
---@class OpenAIMessage
---@field role? "user" | "system" | "assistant"
---@field content string
---
---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "OPENAI_API_KEY"

M.role_map = {
  user = "user",
  assistant = "assistant",
}

---@param opts AvantePromptOptions
M.get_user_message = function(opts)
  vim.deprecate("get_user_message", "parse_messages", "0.1.0", "avante.nvim")
  return table.concat(
    vim
      .iter(opts.messages)
      :filter(function(_, value) return value == nil or value.role ~= "user" end)
      :fold({}, function(acc, value)
        acc = vim.list_extend({}, acc)
        acc = vim.list_extend(acc, { value.content })
        return acc
      end),
    "\n"
  )
end

M.is_o_series_model = function(model) return model and string.match(model, "^o%d+") ~= nil end

M.parse_messages = function(opts)
  local messages = {}
  local provider = P[Config.provider]
  local base, _ = P.parse_config(provider)

  -- NOTE: Handle the case where the selected model is the `o1` model
  -- "o1" models are "smart" enough to understand user prompt as a system prompt in this context
  if M.is_o_series_model(base.model) then
    table.insert(messages, { role = "user", content = opts.system_prompt })
  else
    table.insert(messages, { role = "system", content = opts.system_prompt })
  end

  vim
    .iter(opts.messages)
    :each(function(msg) table.insert(messages, { role = M.role_map[msg.role], content = msg.content }) end)

  if Config.behaviour.support_paste_from_clipboard and opts.image_paths and #opts.image_paths > 0 then
    local message_content = messages[#messages].content
    if type(message_content) ~= "table" then message_content = { type = "text", text = message_content } end
    for _, image_path in ipairs(opts.image_paths) do
      table.insert(message_content, {
        type = "image_url",
        image_url = {
          url = "data:image/png;base64," .. Clipboard.get_base64_content(image_path),
        },
      })
    end
    messages[#messages].content = message_content
  end

  local final_messages = {}
  local prev_role = nil

  vim.iter(messages):each(function(message)
    local role = message.role
    if role == prev_role then
      if role == M.role_map["user"] then
        table.insert(final_messages, { role = M.role_map["assistant"], content = "Ok, I understand." })
      else
        table.insert(final_messages, { role = M.role_map["user"], content = "Ok" })
      end
    end
    prev_role = role
    table.insert(final_messages, { role = M.role_map[role] or role, content = message.content })
  end)

  return final_messages
end

M.parse_response = function(data_stream, _, opts)
  if data_stream:match('"%[DONE%]":') then
    opts.on_complete(nil)
    return
  end
  if data_stream:match('"delta":') then
    ---@type OpenAIChatResponse
    local json = vim.json.decode(data_stream)
    if json.choices and json.choices[1] then
      local choice = json.choices[1]
      if choice.finish_reason == "stop" or choice.finish_reason == "eos_token" then
        opts.on_complete(nil)
      elseif choice.delta.content then
        if choice.delta.content ~= vim.NIL then opts.on_chunk(choice.delta.content) end
      end
    end
  end
end

M.parse_response_without_stream = function(data, _, opts)
  ---@type OpenAIChatResponse
  local json = vim.json.decode(data)
  if json.choices and json.choices[1] then
    local choice = json.choices[1]
    if choice.message and choice.message.content then
      opts.on_chunk(choice.message.content)
      vim.schedule(function() opts.on_complete(nil) end)
    end
  end
end

M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if P.env.require_api_key(base) then
    local api_key = provider.parse_api_key()
    if api_key == nil then
      error(Config.provider .. " API key is not set, please set it in your environment variable or config file")
    end
    headers["Authorization"] = "Bearer " .. api_key
  end

  -- NOTE: When using "o" series set the supported parameters only
  local stream = true
  if M.is_o_series_model(base.model) then
    body_opts.max_completion_tokens = body_opts.max_tokens
    body_opts.max_tokens = nil
    body_opts.temperature = 1
  end

  Utils.debug("endpoint", base.endpoint)
  Utils.debug("model", base.model)

  return {
    url = Utils.url_join(base.endpoint, "/chat/completions"),
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = base.model,
      messages = M.parse_messages(code_opts),
      stream = stream,
    }, body_opts),
  }
end

return M
