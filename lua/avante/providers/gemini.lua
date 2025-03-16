local Utils = require("avante.utils")
local P = require("avante.providers")
local Clipboard = require("avante.clipboard")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "GEMINI_API_KEY"
M.role_map = {
  user = "user",
  assistant = "model",
}
-- M.tokenizer_id = "google/gemma-2b"

function M:is_disable_stream() return false end

function M:parse_messages(opts)
  local contents = {}
  local prev_role = nil

  vim.iter(opts.messages):each(function(message)
    local role = message.role
    if role == prev_role then
      if role == M.role_map["user"] then
        table.insert(
          contents,
          { role = M.role_map["assistant"], parts = {
            { text = "Ok, I understand." },
          } }
        )
      else
        table.insert(contents, { role = M.role_map["user"], parts = {
          { text = "Ok" },
        } })
      end
    end
    prev_role = role
    local parts = {}
    local content_items = message.content
    if type(content_items) == "string" then
      table.insert(parts, { text = content_items })
    elseif type(content_items) == "table" then
      ---@cast content_items AvanteLLMMessageContentItem[]
      for _, item in ipairs(content_items) do
        if type(item) == "string" then
          table.insert(parts, { text = item })
        elseif type(item) == "table" and item.type == "text" then
          table.insert(parts, { text = item.text })
        elseif type(item) == "table" and item.type == "image" then
          table.insert(parts, {
            inline_data = {
              mime_type = "image/png",
              data = item.source.data,
            },
          })
        elseif type(item) == "table" and item.type == "tool_use" then
          table.insert(parts, { text = item.name })
        elseif type(item) == "table" and item.type == "tool_result" then
          table.insert(parts, { text = item.content })
        elseif type(item) == "table" and item.type == "thinking" then
          table.insert(parts, { text = item.thinking })
        elseif type(item) == "table" and item.type == "redacted_thinking" then
          table.insert(parts, { text = item.data })
        end
      end
    end
    table.insert(contents, { role = M.role_map[role] or role, parts = parts })
  end)

  if Clipboard.support_paste_image() and opts.image_paths then
    for _, image_path in ipairs(opts.image_paths) do
      local image_data = {
        inline_data = {
          mime_type = "image/png",
          data = Clipboard.get_base64_content(image_path),
        },
      }

      table.insert(contents[#contents].parts, image_data)
    end
  end

  return {
    systemInstruction = {
      role = "user",
      parts = {
        {
          text = opts.system_prompt,
        },
      },
    },
    contents = contents,
  }
end

function M:parse_response(ctx, data_stream, _, opts)
  local ok, json = pcall(vim.json.decode, data_stream)
  if not ok then opts.on_stop({ reason = "error", error = json }) end
  if json.candidates then
    if #json.candidates > 0 then
      if json.candidates[1].finishReason and json.candidates[1].finishReason == "STOP" then
        opts.on_chunk(json.candidates[1].content.parts[1].text)
        opts.on_stop({ reason = "complete" })
      else
        opts.on_chunk(json.candidates[1].content.parts[1].text)
      end
    else
      opts.on_stop({ reason = "complete" })
    end
  end
end

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)

  request_body = vim.tbl_deep_extend("force", request_body, {
    generationConfig = {
      temperature = request_body.temperature,
      maxOutputTokens = request_body.max_tokens,
    },
  })
  request_body.temperature = nil
  request_body.max_tokens = nil

  local api_key = self.parse_api_key()
  if api_key == nil then error("Cannot get the gemini api key!") end

  return {
    url = Utils.url_join(
      provider_conf.endpoint,
      provider_conf.model .. ":streamGenerateContent?alt=sse&key=" .. api_key
    ),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = { ["Content-Type"] = "application/json" },
    body = vim.tbl_deep_extend("force", {}, self:parse_messages(prompt_opts), request_body),
  }
end

return M
