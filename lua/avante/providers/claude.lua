local Utils = require("avante.utils")
local Clipboard = require("avante.clipboard")
local P = require("avante.providers")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "ANTHROPIC_API_KEY"
M.use_xml_format = true

M.parse_message = function(opts)
  local message_content = {}

  if Clipboard.support_paste_image() and opts.image_paths then
    for _, image_path in ipairs(opts.image_paths) do
      table.insert(message_content, {
        type = "image",
        source = {
          type = "base64",
          media_type = "image/png",
          data = Clipboard.get_base64_content(image_path),
        },
      })
    end
  end

  ---@type {idx: integer, length: integer}[]
  local user_prompts_with_length = {}
  for idx, user_prompt in ipairs(opts.user_prompts) do
    table.insert(user_prompts_with_length, { idx = idx, length = Utils.tokens.calculate_tokens(user_prompt) })
  end

  table.sort(user_prompts_with_length, function(a, b) return a.length > b.length end)

  ---@type table<integer, boolean>
  local top_three = {}
  for i = 1, math.min(3, #user_prompts_with_length) do
    top_three[user_prompts_with_length[i].idx] = true
  end

  for idx, prompt_data in ipairs(opts.user_prompts) do
    table.insert(message_content, {
      type = "text",
      text = prompt_data,
      cache_control = top_three[idx] and { type = "ephemeral" } or nil,
    })
  end

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
    if not ok then return end
    opts.on_chunk(json.delta.text)
  elseif event_state == "message_stop" then
    opts.on_complete(nil)
    return
  elseif event_state == "error" then
    opts.on_complete(vim.json.decode(data_stream))
  end
end

---@param provider AvanteProviderFunctor
---@param prompt_opts AvantePromptOptions
---@return table
M.parse_curl_args = function(provider, prompt_opts)
  local base, body_opts = P.parse_config(provider)

  local headers = {
    ["Content-Type"] = "application/json",
    ["anthropic-version"] = "2023-06-01",
    ["anthropic-beta"] = "prompt-caching-2024-07-31",
  }
  if not P.env.is_local("claude") then headers["x-api-key"] = provider.parse_api_key() end

  local messages = M.parse_message(prompt_opts)

  return {
    url = Utils.trim(base.endpoint, { suffix = "/" }) .. "/v1/messages",
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = base.model,
      system = {
        {
          type = "text",
          text = prompt_opts.system_prompt,
          cache_control = { type = "ephemeral" },
        },
      },
      messages = messages,
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
