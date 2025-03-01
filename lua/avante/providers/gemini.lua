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

function M.parse_messages(opts)
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

function M.parse_response(ctx, data_stream, _, opts)
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

function M.parse_curl_args(provider, prompt_opts)
  local provider_conf, request_body = P.parse_config(provider)

  request_body = vim.tbl_deep_extend("force", request_body, {
    generationConfig = {
      temperature = request_body.temperature,
      maxOutputTokens = request_body.max_tokens,
    },
  })
  request_body.temperature = nil
  request_body.max_tokens = nil

  local api_key = provider.parse_api_key()
  if api_key == nil then error("Cannot get the gemini api key!") end

  return {
    url = Utils.url_join(
      provider_conf.endpoint,
      provider_conf.model .. ":streamGenerateContent?alt=sse&key=" .. api_key
    ),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = { ["Content-Type"] = "application/json" },
    body = vim.tbl_deep_extend("force", {}, M.parse_messages(prompt_opts), request_body),
  }
end

return M
