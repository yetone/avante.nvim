-- lua/avante/providers/gitlab.lua
local curl = require("plenary.curl")
local Utils = require("avante.utils")
local Providers = require("avante.providers")
local Path = require("plenary.path") -- For basename

local H = {}
local M = {}

H.gitlab_api_base_url = "https://gitlab.com/api/v4" -- Placeholder for GitLab API base URL

function H.fetch_and_store_ai_gateway_credentials()
  if not M.state or not M.state.user_gitlab_token then
    Utils.warn("GitLab Duo: Cannot fetch AI Gateway credentials, user GITLAB_TOKEN is missing.")
    return false
  end

  local provider_conf = Providers.get_config("gitlab")
  local gitlab_instance_url = provider_conf.gitlab_instance_url or "https://gitlab.com"

  local direct_access_url = Utils.url_join(gitlab_instance_url, "/api/v4/code_suggestions/direct_access")

  Utils.info("GitLab Duo: Fetching AI Gateway credentials from " .. direct_access_url .. "...")

  local curl_opts = {
    headers = {
      ["Authorization"] = "Bearer " .. M.state.user_gitlab_token,
      ["X-Gitlab-Authentication-Type"] = "oidc",
      ["Content-Type"] = "application/json", -- Typically POST requests might send content type even if body is empty
    },
    -- No body is specified for POST /code_suggestions/direct_access in docs, assuming empty or not needed.
    timeout = provider_conf.timeout or 30000, -- Use configured timeout or a default
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
  }

  local response = curl.post(direct_access_url, curl_opts)

  if not response or response.status ~= 201 then
    Utils.warn(
      "GitLab Duo: Failed to fetch AI Gateway credentials. Status: "
        .. (response and response.status or "unknown")
        .. ". Body: "
        .. (response and response.body or "empty")
    )
    M.state.ai_gateway_base_url = nil
    M.state.ai_gateway_token = nil
    M.state.ai_gateway_token_expires_at = nil
    M.state.ai_gateway_headers = nil
    vim.g.avante_login = false
    return false
  end

  local ok, decoded_body = pcall(vim.json.decode, response.body)
  if not ok or not decoded_body then
    Utils.warn("GitLab Duo: Failed to parse JSON response from /direct_access: " .. (response.body or "empty"))
    M.state.ai_gateway_base_url = nil
    M.state.ai_gateway_token = nil
    M.state.ai_gateway_token_expires_at = nil
    M.state.ai_gateway_headers = nil
    vim.g.avante_login = false
    return false
  end

  if not (decoded_body.base_url and decoded_body.token and decoded_body.expires_at and decoded_body.headers) then
    Utils.warn(
      "GitLab Duo: /direct_access response is missing one or more required fields (base_url, token, expires_at, headers). Response: "
        .. vim.inspect(decoded_body)
    )
    M.state.ai_gateway_base_url = nil
    M.state.ai_gateway_token = nil
    M.state.ai_gateway_token_expires_at = nil
    M.state.ai_gateway_headers = nil
    vim.g.avante_login = false
    return false
  end

  M.state.ai_gateway_base_url = decoded_body.base_url
  M.state.ai_gateway_token = decoded_body.token
  M.state.ai_gateway_token_expires_at = decoded_body.expires_at
  M.state.ai_gateway_headers = decoded_body.headers

  Utils.info(
    "GitLab Duo: Successfully fetched and stored AI Gateway credentials. "
      .. "Base URL: "
      .. tostring(M.state.ai_gateway_base_url)
      .. ", "
      .. "Token: "
      .. tostring(M.state.ai_gateway_token)
      .. ", "
      .. "Token expires at: "
      .. os.date("%Y-%m-%d %H:%M:%S", M.state.ai_gateway_token_expires_at)
      .. " ("
      .. tostring(M.state.ai_gateway_token_expires_at)
      .. "), "
      .. "Headers: "
      .. vim.inspect(M.state.ai_gateway_headers)
  )

  vim.g.avante_login = true
  return true
end

---@private
---@class AvanteGitlabState
---@field access_token string? -- Stores the GITLAB_TOKEN (legacy, user-provided, for direct SaaS access)
---@field user_gitlab_token string? -- Explicitly user-provided GitLab token (e.g. PAT for SaaS non-AI-gateway)
---@field ai_gateway_base_url string? -- Base URL for the AI Gateway
---@field ai_gateway_token string? -- Token for authenticating with the AI Gateway
---@field ai_gateway_token_expires_at number? -- Timestamp (epoch seconds) when the AI gateway token expires
---@field ai_gateway_headers table<string, string>? -- Additional headers for AI Gateway requests (e.g. for instance ID)
M.state = nil

M.api_key_name = "GITLAB_TOKEN"
M.tokenizer_id = "gpt-4o" -- Placeholder: Actual tokenizer depends on GitLab Duo's models and if client-side counting is needed. Not specified in API docs.
M.role_map = {
  user = "user",
  assistant = "assistant",
  system = "system",
}

function M:is_disable_stream(is_streaming_capability) return not is_streaming_capability end

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
        if type(item) == "string" then
          combined_text = combined_text .. item .. " "
        elseif item.type == "text" and item.text then
          combined_text = combined_text .. item.text .. " "
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
  if prompt_opts.current_file_path then file_name = Path:new(prompt_opts.current_file_path):basename() end

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
  local avante_version = "0.1.0" -- Placeholder for Avante's version (TODO: Investigate a robust way to get plugin version if available)

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
  -- Ensure AI Gateway credentials are valid and up-to-date.
  -- M.is_env_set() will attempt to fetch/refresh them if necessary.
  if not self:is_env_set() then
    Utils.warn("GitLab Duo: AI Gateway credentials not available or failed to fetch. Cannot make API request.")
    return nil
  end

  -- Now M.state should contain valid ai_gateway_base_url, ai_gateway_token, and ai_gateway_headers.

  local provider_conf, request_body_extras = Providers.parse_config(self)

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

  -- Merge extra_request_body from config into the payload part if applicable.
  if
    request_body_extras
    and request_body.prompt_components
    and request_body.prompt_components[1]
    and request_body.prompt_components[1].payload
  then
    for k, v in pairs(request_body_extras) do
      if request_body.prompt_components[1].payload[k] == nil then request_body.prompt_components[1].payload[k] = v end
    end
  end

  -- Construct headers using AI Gateway specific token and additional headers
  local request_headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. M.state.ai_gateway_token,
    ["X-Gitlab-Authentication-Type"] = "oidc", -- Per API docs for AI Gateway calls
  }

  -- Merge dynamic headers from /direct_access response
  if M.state.ai_gateway_headers then
    for k, v in pairs(M.state.ai_gateway_headers) do
      request_headers[k] = v
    end
  end

  return {
    url = Utils.url_join(M.state.ai_gateway_base_url, target_api_path),
    timeout = provider_conf.timeout, -- Inherits Avante's default if not set in provider_conf
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = request_headers,
    body = request_body,
    is_streaming = is_streaming_capability,
  }
end

function M.is_env_set()
  if not M.state then
    -- This case should ideally be handled by M.setup() being called first.
    -- However, if called independently, ensure state is minimally initialized.
    M.state = {}
    Utils.warn("GitLab Duo: M.state was not initialized prior to M.is_env_set(). Running basic setup.")
    -- Attempt to load user_gitlab_token if M.setup() was somehow bypassed
    local user_token_initial = vim.env[M.api_key_name]
    if user_token_initial and user_token_initial ~= "" then
      M.state.user_gitlab_token = user_token_initial
    else
      M.state.user_gitlab_token = nil
    end
  end

  -- Ensure user_gitlab_token is loaded if it wasn't during setup or above emergency init
  if not M.state.user_gitlab_token then
    local user_token_check = vim.env[M.api_key_name]
    if user_token_check and user_token_check ~= "" then
      M.state.user_gitlab_token = user_token_check
      Utils.info("GitLab Duo: User GITLAB_TOKEN found by is_env_set.")
    else
      Utils.warn("GitLab Duo: User GITLAB_TOKEN not set. Cannot contact AI Gateway.")
      vim.g.avante_login = false
      return false
    end
  end

  -- Check validity of AI Gateway credentials
  local current_time = os.time()
  local sixty_sec_buffer = 60
  if
    M.state.ai_gateway_token
    and M.state.ai_gateway_token_expires_at
    and M.state.ai_gateway_token_expires_at > (current_time + sixty_sec_buffer)
  then
    Utils.debug("GitLab Duo: Existing AI Gateway credentials are valid.")
    vim.g.avante_login = true
    return true
  end

  -- If credentials are not valid (missing or expired), try to fetch them.
  if M.state.ai_gateway_token_expires_at then
    Utils.info(
      "GitLab Duo: AI Gateway credentials expired or nearing expiry (Expiry: "
        .. os.date("%c", M.state.ai_gateway_token_expires_at)
        .. ", Now: "
        .. os.date("%c", current_time)
        .. "). Refreshing..."
    )
  else
    Utils.info("GitLab Duo: AI Gateway credentials not found. Fetching...")
  end

  -- H.fetch_and_store_ai_gateway_credentials() updates vim.g.avante_login internally
  return H.fetch_and_store_ai_gateway_credentials()
end

function M.setup()
  if not M.state then M.state = {} end

  local user_token = vim.env[M.api_key_name] -- M.api_key_name is GITLAB_TOKEN

  if user_token and user_token ~= "" then
    M.state.user_gitlab_token = user_token
    Utils.info("GitLab Duo provider: User GITLAB_TOKEN found.")
  else
    M.state.user_gitlab_token = nil
    Utils.warn(
      "GitLab Duo provider: User GITLAB_TOKEN environment variable not found or is empty. AI Gateway features will not be available."
    )
  end

  -- Set login status to false initially. M.is_env_set() will update it after checking/fetching AI Gateway creds.
  vim.g.avante_login = false

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
    if opts.on_stop then opts.on_stop({ reason = "error", message = "Callback configuration error." }) end
    return
  end

  local ok, decoded_data = pcall(vim.json.decode, data)

  if not ok then
    Utils.warn(
      "GitLab Duo (Chat): Failed to decode non-streamed JSON response: "
        .. data
        .. " | Error: "
        .. tostring(decoded_data)
    )
    opts.on_stop({ reason = "error", message = "Failed to parse API response." })
    return
  end

  -- Expected structure: {"response": "full_chat_response_text", "metadata": {...}}
  if decoded_data and decoded_data.response and type(decoded_data.response) == "string" then
    opts.on_chunk(decoded_data.response)
    opts.on_stop({ reason = "complete" })
  else
    Utils.warn(
      "GitLab Duo (Chat): Could not extract text from 'response' field or field is not a string. Decoded data: "
        .. vim.inspect(decoded_data)
    )
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
          Utils.warn(
            "GitLab Duo (Stream): Failed to decode JSON from content_chunk: "
              .. json_str
              .. " | Error: "
              .. tostring(data)
          )
        end
      elseif current_event_type == "stream_end" then
        Utils.debug("GitLab Duo (Stream): Received stream_end. Data: " .. json_str) -- data should be 'null' or empty
        opts.on_stop({ reason = "complete" })
        ctx.buffer = "" -- Clear buffer as stream is complete
        current_event_type = nil
        return -- Explicitly exit after stopping
      else
        Utils.warn(
          "GitLab Duo (Stream): Received data for unknown or unset event type: "
            .. (current_event_type or "nil")
            .. " | Data: "
            .. json_str
        )
      end
    else
      Utils.warn("GitLab Duo (Stream): Received unexpected line: " .. line)
    end

    ::continue_loop::
  end
  ctx.current_event_type = current_event_type -- Save for next invocation if buffer is not fully processed
end

return M
