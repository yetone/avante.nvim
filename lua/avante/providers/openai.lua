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
---@field choices? OpenAIResponseChoice[]
---@field usage {prompt_tokens: integer, completion_tokens: integer, total_tokens: integer}
---
---@class OpenAIResponseChoice
---@field index integer
---@field delta OpenAIMessage
---@field logprobs? integer
---@field finish_reason? "stop" | "length"
---
---@class OpenAIMessage
---@field role? "user" | "system" | "assistant"
---@field content string
---
---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "OPENAI_API_KEY"

---@param opts AvantePromptOptions
M.get_user_message = function(opts)
  local user_prompt = opts.base_prompt
    .. "\n\nCODE:\n"
    .. "```"
    .. opts.code_lang
    .. "\n"
    .. opts.code_content
    .. "\n```"
    .. "\n\nQUESTION:\n"
    .. opts.question

  if opts.selected_code_content ~= nil then
    user_prompt = opts.base_prompt
      .. "\n\nCODE CONTEXT:\n"
      .. "```"
      .. opts.code_lang
      .. "\n"
      .. opts.code_content
      .. "\n```"
      .. "\n\nCODE:\n"
      .. "```"
      .. opts.code_lang
      .. "\n"
      .. opts.selected_code_content
      .. "\n```"
      .. "\n\nQUESTION:\n"
      .. opts.question
  end

  return user_prompt
end

M.parse_message = function(opts)
  ---@type string | OpenAIMessage[]
  local user_content
  if Config.behaviour.support_paste_from_clipboard and opts.image_path then
    user_content = {}
    table.insert(user_content, {
      type = "image_url",
      image_url = {
        url = "data:image/png;base64," .. Clipboard.get_base64_content(opts.image_path),
      },
    })
    table.insert(user_content, { type = "text", text = M.get_user_message(opts) })
  else
    user_content = M.get_user_message(opts)
  end

  return {
    { role = "system", content = opts.system_prompt },
    { role = "user", content = user_content },
  }
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
      if choice.finish_reason == "stop" then
        opts.on_complete(nil)
      elseif choice.delta.content then
        if choice.delta.content ~= vim.NIL then
          opts.on_chunk(choice.delta.content)
        end
      end
    end
  end
end

M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  local headers = {
    ["Content-Type"] = "application/json",
  }
  if not P.env.is_local("openai") then
    headers["Authorization"] = "Bearer " .. provider.parse_api_key()
  end

  return {
    url = Utils.trim(base.endpoint, { suffix = "/" }) .. "/chat/completions",
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
