local Utils = require("avante.utils")
local Config = require("avante.config")
local P = require("avante.providers")

---@class AvanteProviderFunctor
local M = {}

M.API_KEY = "GROQ_API_KEY"

M.has = function()
  return os.getenv(M.API_KEY) and true or false
end

M.parse_message = function(opts)
  local code_prompt_obj = {
    text = string.format("<code>```%s\n%s```</code>", opts.code_lang, opts.code_content),
  }

  if opts.selected_code_content then
    code_prompt_obj.text = string.format("<code_context>```%s\n%s```</code_context>", opts.code_lang, opts.code_content)
  end

  -- parts ready
  local message_content = {
    code_prompt_obj,
  }

  if opts.selected_code_content then
    local selected_code_obj = {
      text = string.format("<code>```%s\n%s```</code>", opts.code_lang, opts.selected_code_content),
    }

    table.insert(message_content, selected_code_obj)
  end

  -- insert a part into parts
  table.insert(message_content, {
    text = string.format("<question>%s</question>", opts.question),
  })

  return {
    systemInstruction = {
      role = "user",
      parts = {
        {
          text = opts.system_prompt .. "\n" .. opts.base_prompt,
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
  opts.on_chunk(json.candidates[1].content.parts[1].text)
end

M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  local api_key = os.getenv(body_opts.api_key_name or M.API_KEY)
  body_opts.api_key_name = nil

  return {
    url = Utils.trim(base.endpoint, { suffix = "/" })
      .. "/"
      .. base.model
      .. ":streamGenerateContent?alt=sse&key="
      .. api_key,
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = { ["Content-Type"] = "application/json" },
    body = vim.tbl_deep_extend("force", {}, M.parse_message(code_opts), body_opts),
  }
end

return M
