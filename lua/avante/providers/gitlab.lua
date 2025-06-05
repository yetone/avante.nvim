---@class GitlabToken
---@field access_token string
---@field expires_in number
---@field created_at number
---@field refresh_token string?
---@field token_type string
---@field scope string?

local curl = require("plenary.curl")
local Path = require("plenary.path")
local Utils = require("avante.utils")
local Providers = require("avante.providers")

local H = {}
local M = {}

local gitlab_token_path = vim.fn.stdpath("data") .. "/avante/gitlab-duo.json"

H.auth_url = "https://gitlab.com/oauth/token" -- Placeholder
H.gitlab_api_base_url = "https://gitlab.com/api/v4" -- Placeholder

H.chat_completion_url = function(base_url)
  return Utils.url_join(base_url or H.gitlab_api_base_url, "/ai/chat/completions") -- Placeholder
end

---@private
---@class AvanteGitlabState
---@field gitlab_token GitlabToken?
---@field client_id string?
---@field client_secret string?
M.state = nil

M.api_key_name = "GITLAB_DUO_ACCESS_TOKEN"
M.tokenizer_id = "gpt-4o" -- Placeholder, confirm if GitLab has a specific one
M.role_map = {
  user = "user",
  assistant = "assistant",
  system = "system", -- Assuming GitLab supports a system role
}

function M:is_disable_stream()
  return false -- Assuming streaming is supported
end

function M:parse_messages(opts)
  local messages = {}
  local provider_conf, _ = Providers.parse_config(self)

  -- Add system prompt first, if provided
  if opts.system_prompt and opts.system_prompt ~= "" then
    table.insert(messages, { role = M.role_map.system or "system", content = opts.system_prompt })
  end

  local last_role = nil
  if #messages > 0 then
    last_role = messages[#messages].role
  end

  for _, msg in ipairs(opts.messages) do
    local current_role = M.role_map[msg.role] or msg.role -- Use mapped role or original if not in map
    if current_role == last_role then
      -- If the API requires strictly alternating roles, insert a dummy message.
      -- This depends on GitLab Duo API specifics. For now, mimicking OpenAI's robustness.
      if current_role == (M.role_map.assistant or "assistant") then
        table.insert(messages, { role = M.role_map.user or "user", content = "(Previous message continued)" })
      else -- current_role == user or system
        table.insert(messages, { role = M.role_map.assistant or "assistant", content = "Ok." })
      end
    end

    if type(msg.content) == "string" then
      table.insert(messages, { role = current_role, content = msg.content })
      last_role = current_role
    elseif type(msg.content) == "table" then
      -- Handling for complex content (e.g., images, tool use - placeholders for now)
      -- For now, just concatenate text parts if any.
      local text_content = ""
      for _, item in ipairs(msg.content) do
        if type(item) == "string" then
          text_content = text_content .. item .. "\n"
        elseif item.type == "text" then
          text_content = text_content .. item.text .. "\n"
        -- TODO: Add handling for images or other types if GitLab Duo supports them
        end
      end
      if text_content ~= "" then
        -- Remove trailing newline
        text_content = text_content:sub(1, #text_content - 1) -- Corrected to -1 for single newline
        table.insert(messages, { role = current_role, content = text_content })
        last_role = current_role
      end
    end
  end
  return messages
end

function M:parse_curl_args(prompt_opts)
  if not M.state or not M.state.gitlab_token or not M.state.gitlab_token.access_token then
    Utils.warn("GitLab Duo token is not available. Please check your configuration or ensure GITLAB_DUO_ACCESS_TOKEN is set.")
    return nil
  end

  if M.state.gitlab_token.expires_in and M.state.gitlab_token.created_at and M.state.gitlab_token.refresh_token then
    if (M.state.gitlab_token.created_at + M.state.gitlab_token.expires_in - 60) < math.floor(os.time()) then
      Utils.info("GitLab Duo token is expiring soon, attempting synchronous refresh before API call...")
      local refreshed = H.refresh_token(false, true)
      if not refreshed then
        Utils.warn("Failed to refresh GitLab Duo token before API call. Proceeding with potentially expired token.")
      end
    end
  end

  local provider_conf, request_body_extras = Providers.parse_config(self)
  local effective_api_base_url = provider_conf.endpoint or H.gitlab_api_base_url

  -- IMPORTANT: The model name "gitlab-duo-chat-001" is a placeholder and needs verification.
  local model_to_use = provider_conf.model or "gitlab-duo-chat-001"

  local request_body = {
    model = model_to_use,
    messages = self:parse_messages(prompt_opts),
    stream = not self:is_disable_stream(),
    -- TODO: Add any other GitLab specific parameters from provider_conf.extra_request_body or defaults
  }

  -- Merge extra_request_body from config
  if request_body_extras then
      for k, v in pairs(request_body_extras) do
          if request_body[k] == nil then -- only if not already set by core logic
              request_body[k] = v
          end
      end
  end

  return {
    url = H.chat_completion_url(effective_api_base_url),
    timeout = provider_conf.timeout,
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. M.state.gitlab_token.access_token,
      -- TODO: Add any other GitLab specific headers, e.g., "X-GitLab-Instance-Id" if needed
    },
    body = request_body,
  }
end

function H.refresh_token(async, force)
  if not M.state then
    Utils.warn("GitLab provider state not initialized for token refresh.")
    return false
  end

  if not M.state.gitlab_token or not M.state.gitlab_token.refresh_token then
    Utils.warn("GitLab refresh token is not available. Cannot refresh.")
    return false
  end

  async = async == nil and true or async
  force = force or false

  if not force and M.state.gitlab_token.expires_in and M.state.gitlab_token.created_at then
    if (M.state.gitlab_token.created_at + M.state.gitlab_token.expires_in) > (math.floor(os.time()) + 120) then -- 120s buffer
      return false
    end
  end

  local provider_conf = Providers.get_config("gitlab")
  local client_id = M.state.client_id or vim.env.GITLAB_DUO_CLIENT_ID or "YOUR_CLIENT_ID_PLACEHOLDER"
  local client_secret = M.state.client_secret or vim.env.GITLAB_DUO_CLIENT_SECRET or "YOUR_CLIENT_SECRET_PLACEHOLDER"

  if client_id == "YOUR_CLIENT_ID_PLACEHOLDER" or client_secret == "YOUR_CLIENT_SECRET_PLACEHOLDER" then
    Utils.warn("GitLab Duo client_id or client_secret is not configured with actual values. Token refresh will likely fail.")
  end

  local curl_opts = {
    headers = {
      ["Accept"] = "application/json",
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = Utils.encode_url_params({
      grant_type = "refresh_token",
      refresh_token = M.state.gitlab_token.refresh_token,
      client_id = client_id,
      client_secret = client_secret,
    }),
    timeout = provider_conf.timeout,
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
  }

  local function handle_response(response_body, response_status)
    if response_status == 200 then
      local ok, new_token_data = pcall(vim.json.decode, response_body)
      if ok and new_token_data and new_token_data.access_token then
        M.state.gitlab_token = new_token_data
        M.state.gitlab_token.created_at = math.floor(os.time())
        Path:new(gitlab_token_path):write(vim.json.encode(M.state.gitlab_token), "w")
        if not vim.g.avante_login then vim.g.avante_login = true end
        Utils.info("GitLab Duo token refreshed successfully.")
        return true
      else
        Utils.warn("Failed to decode GitLab token refresh response or token data is invalid: " .. (response_body or "empty response"))
        return false
      end
    else
      Utils.warn("Failed to refresh GitLab token. Status: " .. (response_status or "unknown") .. ". Response: " .. (response_body or "empty"))
      return false
    end
  end

  local effective_auth_url = (provider_conf and provider_conf.auth_url) or H.auth_url


  if async then
    curl.post(effective_auth_url, curl_opts, function(_, body, status)
      vim.schedule(function() handle_response(body, status) end)
    end, function(err)
      vim.schedule(function() Utils.warn("GitLab token refresh HTTP error: " .. vim.inspect(err)) end)
    end)
    return true -- Assuming async call is initiated
  else
    local response = curl.post(effective_auth_url, curl_opts)
    return handle_response(response.body, response.status)
  end
end

local function check_token_validity(token)
  if token and token.access_token then
    if token.expires_in and token.created_at then
      return (token.created_at + token.expires_in) > (math.floor(os.time()) + 60) -- 60s buffer
    end
    return true -- Has access token, but no expiry info (e.g. direct token). Assume valid.
  end
  return false
end

function M.is_env_set()
  if not M.state then M.state = {} end
  if not M.state.client_id then M.state.client_id = vim.env.GITLAB_DUO_CLIENT_ID end
  if not M.state.client_secret then M.state.client_secret = vim.env.GITLAB_DUO_CLIENT_SECRET end

  if check_token_validity(M.state.gitlab_token) then
    vim.g.avante_login = true
    return true
  elseif M.state.gitlab_token and M.state.gitlab_token.refresh_token and M.state.gitlab_token.expires_in and M.state.gitlab_token.created_at then -- Expired but refreshable
    Utils.info("GitLab token in memory expired/nearing expiry. Attempting synchronous refresh for env check.")
    if H.refresh_token(false, true) then
        vim.g.avante_login = true
        return true -- Return true if refresh was successful
    end
    -- If refresh failed, token is still invalid
  end

  local token_file = Path:new(gitlab_token_path)
  if token_file:exists() then
    local ok, token_data = pcall(vim.json.decode, token_file:read())
    if ok and token_data then
      M.state.gitlab_token = token_data
      if not M.state.gitlab_token.created_at and M.state.gitlab_token.expires_in then
         Utils.warn("GitLab token from file missing 'created_at'. Assuming recently created for current check.")
         M.state.gitlab_token.created_at = math.floor(os.time()) - 10
      end
      if check_token_validity(M.state.gitlab_token) then
        vim.g.avante_login = true
        return true
      elseif M.state.gitlab_token.refresh_token and M.state.gitlab_token.expires_in and M.state.gitlab_token.created_at then -- Expired but refreshable
        Utils.info("GitLab token from file expired/nearing expiry. Attempting synchronous refresh for env check.")
        if H.refresh_token(false, true) then
          vim.g.avante_login = true
          return true -- Return true if refresh was successful
        end
        -- If refresh failed, token is still invalid
      end
    end
  end

  local direct_access_token = vim.env[M.api_key_name]
  if direct_access_token then
    M.state.gitlab_token = { access_token = direct_access_token, token_type = "Bearer" }
    Utils.warn("Using direct GitLab Duo access token from env (" .. M.api_key_name .. "). Refresh and expiry are not managed for this token.")
    vim.g.avante_login = true
    return true
  end

  vim.g.avante_login = false
  return false
end

function M.setup()
  if not M.state then M.state = {} end

  M.state.client_id = vim.env.GITLAB_DUO_CLIENT_ID
  M.state.client_secret = vim.env.GITLAB_DUO_CLIENT_SECRET

  local token_file = Path:new(gitlab_token_path)
  local loaded_from_file = false
  if token_file:exists() then
    local ok, token = pcall(vim.json.decode, token_file:read())
    if ok and token and token.access_token then
      M.state.gitlab_token = token
      loaded_from_file = true
      if not M.state.gitlab_token.created_at and M.state.gitlab_token.expires_in then
        Utils.warn("GitLab token from file is missing 'created_at'. Assuming it's recently created for expiry checks.")
        M.state.gitlab_token.created_at = math.floor(os.time()) - 10
      end
    else
      Utils.warn("Failed to load or parse GitLab token from: " .. gitlab_token_path .. ". File might be corrupted or empty.")
    end
  end

  local needs_action = true
  if M.state.gitlab_token and M.state.gitlab_token.access_token then
    if M.state.gitlab_token.expires_in and M.state.gitlab_token.created_at then
      if (M.state.gitlab_token.created_at + M.state.gitlab_token.expires_in) > (math.floor(os.time()) + 120) then -- 120s buffer
        needs_action = false
      else
        Utils.info("GitLab token is expired or nearing expiry. Will attempt refresh if refresh_token is available.")
      end
    else
      needs_action = false -- No expiry info, assume direct token, no refresh possible/needed via this mechanism
      Utils.warn("Loaded GitLab token has no expiry information. Assuming it's a long-lived token or direct access token. Refresh is not possible without refresh_token and expiry details.")
    end
  end

  if needs_action then
    if M.state.gitlab_token and M.state.gitlab_token.refresh_token then
      Utils.info("Attempting to refresh GitLab token during setup (async).")
      H.refresh_token(true, true) -- Async, forced refresh
    elseif vim.env[M.api_key_name] then
      M.state.gitlab_token = { access_token = vim.env[M.api_key_name], token_type = "Bearer" }
      Utils.warn("Using direct GitLab Duo access token from env (" .. M.api_key_name .. ") during setup. Refresh and expiry are not managed.")
    else
      if not loaded_from_file then
         Utils.warn("No GitLab token found in file, no refresh token, and " .. M.api_key_name .. " not set. GitLab Duo provider may not function unless a valid token is manually created at " .. gitlab_token_path .. " or " .. M.api_key_name .. " is set.")
      end
    end
  end

  vim.g.avante_login = (M.state.gitlab_token and M.state.gitlab_token.access_token ~= nil)

  require("avante.tokenizers").setup(M.tokenizer_id)
  M._is_setup = true
end

-- Stream parsing implementation
function M:parse_response(ctx, data_stream, _, opts)
  if not opts or not opts.on_chunk or not opts.on_stop then
    Utils.warn("GitLab Duo: parse_response called without proper opts callbacks.")
    return
  end

  ctx.buffer = (ctx.buffer or "") .. data_stream

  local completed_processing = false
  while true do
    local next_event_boundary = ctx.buffer:find("\n\n", 1, true) -- SSE events are separated by double newlines
    if not next_event_boundary then break end -- No complete event in buffer yet

    local event_str = ctx.buffer:sub(1, next_event_boundary -1)
    ctx.buffer = ctx.buffer:sub(next_event_boundary + 2) -- Consume the event and the separator

    if event_str == "data: [DONE]" then
      Utils.info("GitLab Duo: Received [DONE] marker.")
      opts.on_stop({ reason = "complete" })
      completed_processing = true
      break
    end

    if event_str:match("^data: ") then
      local json_str = event_str:sub(7) -- Skip "data: "
      local ok, data = pcall(vim.json.decode, json_str)

      if ok then
        -- IMPORTANT: This JSON structure is a PLACEHOLDER and needs verification.
        -- Assuming a structure like: { "token": { "text": "chunk" }, "is_final_chunk": false }
        if data.token and data.token.text and data.token.text ~= "" then
          opts.on_chunk(data.token.text)
        end
        if data.is_final_chunk == true then
          Utils.info("GitLab Duo: Received is_final_chunk=true marker.")
          opts.on_stop({ reason = "complete" })
          completed_processing = true
          break
        end
      else
        Utils.warn("GitLab Duo: Failed to decode JSON from stream: " .. json_str .. " | Error: " .. tostring(data))
      end
    elseif event_str ~= "" then -- Non-empty line that isn't a data line or DONE marker
        Utils.warn("GitLab Duo: Received unexpected line in stream: " .. event_str)
    end
  end
  if completed_processing then ctx.buffer = "" end -- Clear buffer if stream ended
end

-- Non-stream parsing implementation
function M:parse_response_without_stream(data, _, opts)
  if not opts or not opts.on_chunk or not opts.on_stop then
    Utils.warn("GitLab Duo: parse_response_without_stream called without proper opts callbacks.")
    if opts.on_stop then opts.on_stop({reason = "error", message = "Callback configuration error."}) end
    return
  end

  local ok, decoded_data = pcall(vim.json.decode, data)

  if not ok then
    Utils.warn("GitLab Duo: Failed to decode non-streamed JSON response: " .. data .. " | Error: " .. tostring(decoded_data))
    opts.on_stop({ reason = "error", message = "Failed to parse API response." })
    return
  end

  -- IMPORTANT: This JSON structure is a PLACEHOLDER and needs verification.
  -- Assuming a structure like: { "full_text": "response content" }
  local response_text = decoded_data.full_text

  if response_text and type(response_text) == "string" then
    opts.on_chunk(response_text)
    opts.on_stop({ reason = "complete" })
  else
    Utils.warn("GitLab Duo: Could not extract text from non-streamed response. Decoded data: " .. vim.inspect(decoded_data))
    opts.on_stop({ reason = "error", message = "Could not extract text from API response." })
  end
end

return M
