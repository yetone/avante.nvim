local Utils = require("avante.utils")
local Config = require("avante.config")
local Tiktoken = require("avante.tiktoken")
local P = require("avante.providers")

---@class AvanteProviderFunctor
local M = {}

M.API_KEY = "ANTHROPIC_API_KEY"

M.has = function()
  return os.getenv(M.API_KEY) and true or false
end

M.parse_message = function(opts)
  local code_prompt_obj = {
    type = "text",
    text = string.format("<code>```%s\n%s```</code>", opts.code_lang, opts.code_content),
  }

  if Tiktoken.count(code_prompt_obj.text) > 1024 then
    code_prompt_obj.cache_control = { type = "ephemeral" }
  end

  if opts.selected_code_content then
    code_prompt_obj.text = string.format("<code_context>```%s\n%s```</code_context>", opts.code_lang, opts.code_content)
  end

  local message_content = {
    code_prompt_obj,
  }

  if opts.selected_code_content then
    local selected_code_obj = {
      type = "text",
      text = string.format("<code>```%s\n%s```</code>", opts.code_lang, opts.selected_code_content),
    }

    if Tiktoken.count(selected_code_obj.text) > 1024 then
      selected_code_obj.cache_control = { type = "ephemeral" }
    end

    table.insert(message_content, selected_code_obj)
  end

  table.insert(message_content, {
    type = "text",
    text = string.format("<question>%s</question>", opts.question),
  })

  local user_prompt = opts.base_prompt

  local user_prompt_obj = {
    type = "text",
    text = user_prompt,
  }

  if Tiktoken.count(user_prompt_obj.text) > 1024 then
    user_prompt_obj.cache_control = { type = "ephemeral" }
  end

  table.insert(message_content, user_prompt_obj)

  return {
    {
      role = "user",
      content = message_content,
    },
  }
end

M.parse_response = function(data_stream, event_state, opts)
  if event_state == "content_block_delta" then
    local ok, json = pcall(vim.json.decode, data_stream)
    if not ok then
      return
    end
    opts.on_chunk(json.delta.text)
  elseif event_state == "message_stop" then
    opts.on_complete(nil)
    return
  elseif event_state == "error" then
    opts.on_complete(vim.json.decode(data_stream))
  end
end

M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  local headers = {
    ["Content-Type"] = "application/json",
    ["anthropic-version"] = "2023-06-01",
    ["anthropic-beta"] = "prompt-caching-2024-07-31",
  }
  if not P.env.is_local("claude") then
    headers["x-api-key"] = os.getenv(M.API_KEY)
  end

  return {
    url = Utils.trim(base.endpoint, { suffix = "/" }) .. "/v1/messages",
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = base.model,
      messages = M.parse_message(code_opts),
      stream = true,
    }, body_opts),
  }
end

return M
