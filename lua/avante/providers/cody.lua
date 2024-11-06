--- Documentation for setting up Sourcegraph Cody
--- Generating an access token: https://sourcegraph.com/docs/cli/how-tos/creating_an_access_token

local P = require("avante.providers")
local Utils = require("avante.utils")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "SRC_ACCESS_TOKEN"

M.parse_response = function(data_stream, event_state, opts)
  if event_state == "done" then
    opts.on_complete()
    return
  end

  local json = vim.json.decode(data_stream)
  local delta = json.deltaText
  local stopReason = json.stopReason

  if stopReason == "end_turn" then return end

  opts.on_chunk(delta)
end

---@param provider AvanteProviderFunctor
---@param prompt_opts AvantePromptOptions
---@return table
M.parse_curl_args = function(provider, prompt_opts)
  local base, body_opts = P.parse_config(provider)

  local api_key = provider.parse_api_key()
  if api_key == nil then
    -- if no api key is available, make a request with a empty api key.
    api_key = ""
  end

  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "token " .. api_key,
  }

  return {
    url = Utils.trim(base.endpoint, { suffix = "/" })
      .. "/.api/completions/stream?api-version=2&client-name=web&client-version=0.0.1",
    timeout = base.timeout,
    insecure = false,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = base.model,
      temperature = body_opts.temperature,
      topK = body_opts.topK,
      topP = body_opts.topP,
      maxTokensToSample = body_opts.max_tokens,
      stream = true,
      messages = {
        {
          speaker = "system",
          text = prompt_opts.system_prompt,
        },
        {
          speaker = "human",
          text = table.concat(prompt_opts.user_prompts, "\n"),
        },
      },
    }, {}),
  }
end

M.on_error = function() end

return M
