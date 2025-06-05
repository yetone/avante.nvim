-- lua/avante/providers/gitlab.lua
local curl = require("plenary.curl")
local Utils = require("avante.utils")
local Providers = require("avante.providers")
local Path = require("plenary.path") -- For basename

local H = {}
local M = {}

H.gitlab_api_base_url = "https://gitlab.com/api/v4" -- Placeholder for GitLab API base URL

---@private
---@class AvanteGitlabState
---@field access_token string?
M.state = nil

M.api_key_name = "GITLAB_TOKEN"
M.tokenizer_id = "gpt-4o" -- Placeholder: Actual tokenizer depends on GitLab Duo's models and if client-side counting is needed. Not specified in API docs.
M.role_map = {
  user = "user",
  assistant = "assistant",
  system = "system",
}

function M:is_disable_stream(is_streaming_capability)
  return not is_streaming_capability
end

function M:parse_messages(opts)
  local messages = {}
  if opts.system_prompt and opts.system_prompt ~= "" then
    table.insert(messages, { role = M.role_map.system, content = opts.system_prompt })
  end

  local last_role = nil
  if #messages > 0 then last_role = messages[#messages].role end

  for _, msg in ipairs(opts.messages) do
    local current_role = M.role_map[msg.role] or msg.role
    if current_role == last_role and #messages > 0 then
      if current_role == (M.role_map.assistant or "assistant") then
        table.insert(messages, { role = M.role_map.user or "user", content = "(Context continued)" })
      else
        table.insert(messages, { role = M.role_map.assistant or "assistant", content = "Ok." })
      end
    end

    if type(msg.content) == "string" then
      table.insert(messages, { role = current_role, content = msg.content })
      last_role = current_role
    elseif type(msg.content) == "table" then
        local combined_text = ""
        for _, item in ipairs(msg.content) do
            if type(item) == "string" then combined_text = combined_text .. item .. " "
            elseif item.type == "text" and item.text then combined_text = combined_text .. item.text .. " "
            end
        end
        if combined_text ~= "" then
            table.insert(messages, { role = current_role, content = vim.trim(combined_text) })
            last_role = current_role
        end
    end
  end
  return messages
end

function H.build_code_suggestion_body(prompt_opts, provider_conf)
  local file_name = "unknown_file.txt"
  if prompt_opts.current_file_path then
    file_name = Path:new(prompt_opts.current_file_path):basename()
  end

  local lang_identifier = provider_conf.language_identifier
  if not lang_identifier and prompt_opts.language_identifier then
    lang_identifier = prompt_opts.language_identifier
  elseif not lang_identifier then
    lang_identifier = vim.bo.filetype
  end

  -- Model sourcing: config specific, then general config, then default
  local model_name = provider_conf.code_suggestion_model or provider_conf.model or "code-gecko@002"

  local payload = {
    file_name = file_name,
    content_above_cursor = prompt_opts.content_above_cursor or "",
    content_below_cursor = prompt_opts.content_below_cursor or "",
    language_identifier = lang_identifier,
    model_name = model_name,
    stream = true,
  }

  return {
    prompt_components = {
      {
        type = "code_editor_completion",
        payload = payload,
      },
    },
  }
end

function H.build_chat_body(prompt_opts, provider_conf)
  local messages_array = M:parse_messages(prompt_opts)
  -- Model sourcing: config specific, then general config, then default
  local model_name = provider_conf.chat_model or provider_conf.model or "claude-3-5-sonnet-20240620"
  local avante_version = "0.1.0"
  if Utils.get_plugin_version then
      avante_version = Utils.get_plugin_version("avante.nvim") or avante_version
  else
      Utils.get_plugin_version = function() return "test-version" end -- Temp for test env
      avante_version = Utils.get_plugin_version("avante.nvim") or avante_version
  end

  return {
    prompt_components = {
      {
        type = "prompt",
        payload = {
          content = messages_array,
          provider = "anthropic",
          model = model_name,
        },
        metadata = {
          source = "AvanteNvim",
          version = avante_version,
        },
      },
    },
  }
end

function M:parse_curl_args(prompt_opts)
  if not M.state or not M.state.access_token or M.state.access_token == "" then
    Utils.warn("GITLAB_TOKEN is not set or is empty. Please set it in your environment.")
    return nil
  end

  local provider_conf, request_body_extras = Providers.parse_config(self)
  local effective_api_base_url = provider_conf.endpoint or H.gitlab_api_base_url
  local request_body
  local target_api_path
  local is_streaming_capability

  if prompt_opts.content_above_cursor ~= nil or prompt_opts.content_below_cursor ~= nil then
    Utils.debug("GitLab Provider: Detected Code Suggestion request.")
    target_api_path = "/v4/code/suggestions"
    request_body = H.build_code_suggestion_body(prompt_opts, provider_conf)
    is_streaming_capability = true
  else
    Utils.debug("GitLab Provider: Detected Chat request.")
    target_api_path = "/v1/agent/chat"
    request_body = H.build_chat_body(prompt_opts, provider_conf)
    is_streaming_capability = false
  end

  if request_body_extras and request_body.prompt_components and request_body.prompt_components[1] and request_body.prompt_components[1].payload then
      for k,v in pairs(request_body_extras) do
          if request_body.prompt_components[1].payload[k] == nil then
              request_body.prompt_components[1].payload[k] = v
          end
      end
  end

  return {
    url = Utils.url_join(effective_api_base_url, target_api_path),
    timeout = provider_conf.timeout,
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. M.state.access_token,
      ["X-Gitlab-Authentication-Type"] = "oidc",
    },
    body = request_body,
    is_streaming = is_streaming_capability,
  }
end

function M.is_env_set()
  if not M.state then M.state = {} end
  if M.state.access_token and M.state.access_token ~= "" then
    vim.g.avante_login = true
    return true
  end
  local token_from_env = vim.env[M.api_key_name]
  if token_from_env and token_from_env ~= "" then
    M.state.access_token = token_from_env
    vim.g.avante_login = true
    return true
  end
  vim.g.avante_login = false
  return false
end

function M.setup()
  if not M.state then M.state = {} end
  local token = vim.env[M.api_key_name]
  if token and token ~= "" then
    M.state.access_token = token
    vim.g.avante_login = true
    Utils.info("GitLab Duo provider: Using GITLAB_TOKEN from environment.")
  else
    M.state.access_token = nil
    vim.g.avante_login = false
    Utils.warn("GitLab Duo provider: GITLAB_TOKEN environment variable not found or is empty.")
  end
  require("avante.tokenizers").setup(M.tokenizer_id)
  M._is_setup = true
end

-- Note on Tool Use: The GitLab Duo /v1/agent/chat API (as per docs reviewed) does not specify a structured
-- mechanism for model-driven function calling (like OpenAI's tool_calls).
-- However, if the underlying model (e.g., Claude) is prompted to produce specific textual cues
-- (e.g., XML-like tags) for tool invocation, Avante's existing text-based tool parsing
-- mechanisms might still be effective with responses from this provider.
function M:parse_response_without_stream(data, _, opts)
  if not opts or not opts.on_chunk or not opts.on_stop then
    Utils.warn("GitLab Duo (Chat): parse_response_without_stream called without proper opts callbacks.")
    if opts.on_stop then opts.on_stop({reason = "error", message = "Callback configuration error."}) end
    return
  end

  local ok, decoded_data = pcall(vim.json.decode, data)

  if not ok then
    Utils.warn("GitLab Duo (Chat): Failed to decode non-streamed JSON response: " .. data .. " | Error: " .. tostring(decoded_data))
    opts.on_stop({ reason = "error", message = "Failed to parse API response." })
    return
  end

  -- Expected structure: {"response": "full_chat_response_text", "metadata": {...}}
  if decoded_data and decoded_data.response and type(decoded_data.response) == "string" then
    opts.on_chunk(decoded_data.response)
    opts.on_stop({ reason = "complete" })
  else
    Utils.warn("GitLab Duo (Chat): Could not extract text from 'response' field or field is not a string. Decoded data: " .. vim.inspect(decoded_data))
    opts.on_stop({ reason = "error", message = "Could not extract text from API response (unexpected format)." })
  end
end

function M:parse_response(ctx, data_stream, _, opts)
  if not opts or not opts.on_chunk or not opts.on_stop then
    Utils.warn("GitLab Duo (Stream): parse_response called without proper opts callbacks.")
    return
  end

  ctx.buffer = (ctx.buffer or "") .. data_stream
  local current_event_type = ctx.current_event_type or nil -- Persist event type across calls for multi-line data

  while true do
    local line_end = ctx.buffer:find("\n", 1, true)
    if not line_end then break end -- No complete line in buffer

    local line = ctx.buffer:sub(1, line_end - 1)
    ctx.buffer = ctx.buffer:sub(line_end + 1)

    if line == "" then -- End of an event block
      current_event_type = nil -- Reset for next event block
      goto continue_loop -- Skip to next iteration
    end

    local event_prefix = "event: "
    local data_prefix = "data: "

    if line:sub(1, #event_prefix) == event_prefix then
      current_event_type = line:sub(#event_prefix + 1)
      Utils.debug("GitLab Duo (Stream): Event type set to: " .. current_event_type)
    elseif line:sub(1, #data_prefix) == data_prefix then
      local json_str = line:sub(#data_prefix + 1)

      if current_event_type == "stream_start" then
        Utils.debug("GitLab Duo (Stream): Received stream_start with data: " .. json_str)
        -- Optional: parse and log metadata if needed
      elseif current_event_type == "content_chunk" then
        local ok, data = pcall(vim.json.decode, json_str)
        if ok then
          if data.choices and data.choices[1] and data.choices[1].delta and data.choices[1].delta.content then
            opts.on_chunk(data.choices[1].delta.content)
          else
            Utils.warn("GitLab Duo (Stream): content_chunk JSON structure unexpected: " .. json_str)
          end
        else
          Utils.warn("GitLab Duo (Stream): Failed to decode JSON from content_chunk: " .. json_str .. " | Error: " .. tostring(data))
        end
      elseif current_event_type == "stream_end" then
        Utils.debug("GitLab Duo (Stream): Received stream_end. Data: " .. json_str) -- data should be 'null' or empty
        opts.on_stop({ reason = "complete" })
        ctx.buffer = "" -- Clear buffer as stream is complete
        current_event_type = nil
        return -- Explicitly exit after stopping
      else
        Utils.warn("GitLab Duo (Stream): Received data for unknown or unset event type: " .. (current_event_type or "nil") .. " | Data: " .. json_str)
      end
    else
      Utils.warn("GitLab Duo (Stream): Received unexpected line: " .. line)
    end

    ::continue_loop::
  end
  ctx.current_event_type = current_event_type -- Save for next invocation if buffer is not fully processed
end

return M
