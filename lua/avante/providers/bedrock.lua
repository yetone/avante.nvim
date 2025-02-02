local Utils = require("avante.utils")
local Clipboard = require("avante.clipboard")
local P = require("avante.providers")

---@class AvanteClaudeBaseMessage
---@field cache_control {type: "ephemeral"}?
---
---@class AvanteClaudeTextMessage: AvanteClaudeBaseMessage
---@field type "text"
---@field text string
---
---@class AvanteClaudeImageMessage: AvanteClaudeBaseMessage
---@field type "image"
---@field source {type: "base64", media_type: string, data: string}
---
---@class AvanteClaudeMessage
---@field role "user" | "assistant"
---@field content [AvanteClaudeTextMessage | AvanteClaudeImageMessage][]

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "BEDROCK_KEYS"
M.use_xml_format = true

M.role_map = {
  user = "user",
  assistant = "assistant",
}

M.parse_messages = function(opts)
  ---@type AvanteClaudeMessage[]
  local messages = {}

  ---@type {idx: integer, length: integer}[]
  local messages_with_length = {}
  for idx, message in ipairs(opts.messages) do
    table.insert(messages_with_length, { idx = idx, length = Utils.tokens.calculate_tokens(message.content) })
  end

  table.sort(messages_with_length, function(a, b) return a.length > b.length end)

  ---@type table<integer, boolean>
  local top_three = {}
  for i = 1, math.min(3, #messages_with_length) do
    top_three[messages_with_length[i].idx] = true
  end

  for idx, message in ipairs(opts.messages) do
    table.insert(messages, {
      role = M.role_map[message.role],
      content = {
        {
          type = "text",
          text = message.content,
          cache_control = top_three[idx] and { type = "ephemeral" } or nil,
        },
      },
    })
  end

  if Clipboard.support_paste_image() and opts.image_paths and #opts.image_paths > 0 then
    local message_content = messages[#messages].content
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
    messages[#messages].content = message_content
  end

  return messages
end

M.parse_response = function(ctx, data_stream, event_state, opts)
  if event_state == nil then
    if data_stream:match('"content_block_delta"') then
      event_state = "content_block_delta"
    elseif data_stream:match('"message_stop"') then
      event_state = "message_stop"
    end
  end
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
  -- 既存の設定を取得
  local base, body_opts = P.parse_config(provider)

  -- provider.parse_api_key() は "AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,AWS_REGION" の形式で返る
  local api_key = provider.parse_api_key()
  local parts = vim.split(api_key, ",")
  local aws_access_key_id     = parts[1]
  local aws_secret_access_key = parts[2]
  local aws_region            = parts[3]

  -- Bedrock用のエンドポイントを組み立てる
  -- base.model は "anthropic.claude-v2" 等、Bedrockで利用するモデルIDとする
  local endpoint = string.format("https://bedrock-runtime.%s.amazonaws.com/model/%s/invoke", aws_region, base.model)

  -- ヘッダーは Bedrock では "Content-Type" のみ必要（追加ヘッダーは不要）
  local headers = {
    ["Content-Type"] = "application/json",
  }

  -- ユーザーが作成したメッセージを取得
  local messages = M.parse_messages(prompt_opts)
  -- ※必要に応じて system prompt の内容を messages に含める処理をここで追加可能

  -- Bedrock 用のリクエストボディを作成
  -- ※ここでは "anthropic_version" を Bedrock 固有の値にし、max_tokens は prompt_opts から取得（無ければ 2000 をデフォルト）
  local body_payload = vim.tbl_deep_extend("force", {
    anthropic_version = "bedrock-2023-05-31",
    max_tokens = prompt_opts.max_tokens or 2000,
    messages = messages,
  }, body_opts)

  local rawArgs = {
    "--aws-sigv4", string.format("aws:amz:%s:bedrock", aws_region),
    "--user", string.format("%s:%s", aws_access_key_id, aws_secret_access_key)
  }

  -- curl 呼び出し時に必要な AWS シグネチャ情報やユーザー認証情報をフィールドとして追加
  return {
    url = endpoint,
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = headers,
    body = body_payload,
    rawArgs = rawArgs,
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
