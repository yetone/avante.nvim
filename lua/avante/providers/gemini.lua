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

M.parse_messages = function(opts)
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
    table.insert(contents, { role = M.role_map[role] or role, parts = {
      { text = message.content },
    } })
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

M.parse_response = function(data_stream, _, opts)
  local ok, json = pcall(vim.json.decode, data_stream)
  if not ok then opts.on_complete(json) end
  if json.candidates then
    if #json.candidates > 0 then
      if json.candidates[1].finishReason and json.candidates[1].finishReason == "STOP" then
        opts.on_chunk(json.candidates[1].content.parts[1].text)
        opts.on_complete(nil)
      else
        opts.on_chunk(json.candidates[1].content.parts[1].text)
      end
    else
      opts.on_complete(nil)
    end
  end
end

M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  body_opts = vim.tbl_deep_extend("force", body_opts, {
    generationConfig = {
      temperature = body_opts.temperature,
      maxOutputTokens = body_opts.max_tokens,
    },
  })
  body_opts.temperature = nil
  body_opts.max_tokens = nil

  return {
    url = Utils.url_join(
      base.endpoint,
      base.model .. ":streamGenerateContent?alt=sse&key=" .. provider.parse_api_key()
    ),
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = { ["Content-Type"] = "application/json" },
    body = vim.tbl_deep_extend("force", {}, M.parse_messages(code_opts), body_opts),
  }
end

return M
