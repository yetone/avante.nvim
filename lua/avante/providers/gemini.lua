local Utils = require("avante.utils")
local P = require("avante.providers")
local Clipboard = require("avante.clipboard")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "GEMINI_API_KEY"

M.parse_message = function(opts)
  local message_content = {}

  if Clipboard.support_paste_image() and opts.image_paths then
    for _, image_path in ipairs(opts.image_paths) do
      local image_data = {
        inline_data = {
          mime_type = "image/png",
          data = Clipboard.get_base64_content(image_path),
        },
      }

      table.insert(message_content, image_data)
    end
  end

  -- insert a part into parts
  for _, user_prompt in ipairs(opts.user_prompts) do
    table.insert(message_content, {
      text = user_prompt,
    })
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
    contents = {
      {
        role = "user",
        parts = message_content,
      },
    },
  }
end

M.parse_response = function(data_stream, _, opts)
  local json = vim.json.decode(data_stream)
  if json.candidates and #json.candidates > 0 then
    opts.on_chunk(json.candidates[1].content.parts[1].text)
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
    url = Utils.trim(base.endpoint, { suffix = "/" })
      .. "/"
      .. base.model
      .. ":streamGenerateContent?alt=sse&key="
      .. provider.parse_api_key(),
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = { ["Content-Type"] = "application/json" },
    body = vim.tbl_deep_extend("force", {}, M.parse_message(code_opts), body_opts),
  }
end

return M
