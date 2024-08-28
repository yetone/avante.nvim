local Config = require("avante.config")
local Utils = require("avante.utils")
local Clipboard = require("avante.clipboard")
local P = require("avante.providers")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "ANTHROPIC_API_KEY"

M.parse_message = function(opts)
  local code_prompt_obj = {
    type = "text",
    text = string.format("<code>```%s\n%s```</code>", opts.code_lang, opts.code_content),
  }

  if Utils.tokens.calculate_tokens(code_prompt_obj.text) > 1024 then
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

    if Utils.tokens.calculate_tokens(selected_code_obj.text) > 1024 then
      selected_code_obj.cache_control = { type = "ephemeral" }
    end

    table.insert(message_content, selected_code_obj)
  end

  if Clipboard.support_paste_image() and opts.image_path then
    table.insert(message_content, {
      type = "image",
      source = {
        type = "base64",
        media_type = "image/png",
        data = Clipboard.get_base64_content(opts.image_path),
      },
    })
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

  if Utils.tokens.calculate_tokens(user_prompt_obj.text) > 1024 then
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

---@param provider AvanteProviderFunctor
---@param code_opts AvantePromptOptions
---@return table
M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  local headers = {
    ["Content-Type"] = "application/json",
    ["anthropic-version"] = "2023-06-01",
    ["anthropic-beta"] = "prompt-caching-2024-07-31",
  }
  if not P.env.is_local("claude") then
    headers["x-api-key"] = provider.parse_api_key()
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

M.on_error = function(result)
  if not result.body then
    return Utils.error("API request failed with status " .. result.status, { once = true, title = "Avante" })
  end

  local ok, body = pcall(vim.json.decode, result.body)
  if not (ok and body and body.error) then
    return Utils.error("Failed to parse error response", { once = true, title = "Avante" })
  end

  local error_msg = body.error.message
  local error_type = body.error.type

  if error_type == "insufficient_quota" then
    error_msg = "You don't have any credits or have exceeded your quota. Please check your plan and billing details."
  elseif error_type == "invalid_request_error" and error_msg:match("temperature") then
    error_msg = "Invalid temperature value. Please ensure it's between 0 and 1."
  end

  Utils.error(error_msg, { once = true, title = "Avante" })
end

return M
