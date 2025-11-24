---Reference implementation:
---https://github.com/zbirenbaum/copilot.lua/blob/master/lua/copilot/auth.lua config file
---https://github.com/zed-industries/zed/blob/ad43bbbf5eda59eba65309735472e0be58b4f7dd/crates/copilot/src/copilot_chat.rs#L272 for authorization
---
---@class CopilotToken
---@field annotations_enabled boolean
---@field chat_enabled boolean
---@field chat_jetbrains_enabled boolean
---@field code_quote_enabled boolean
---@field codesearch boolean
---@field copilotignore_enabled boolean
---@field endpoints {api: string, ["origin-tracker"]: string, proxy: string, telemetry: string}
---@field expires_at integer
---@field individual boolean
---@field nes_enabled boolean
---@field prompt_8k boolean
---@field public_suggestions string
---@field refresh_in integer
---@field sku string
---@field snippy_load_test_enabled boolean
---@field telemetry string
---@field token string
---@field tracking_id string
---@field vsc_electron_fetcher boolean
---@field xcode boolean
---@field xcode_chat boolean

local curl = require("plenary.curl")

local Path = require("plenary.path")
local Utils = require("avante.utils")
local Providers = require("avante.providers")
local OpenAI = require("avante.providers").openai

local H = {}

---@class AvanteProviderFunctor
local M = {}

local copilot_path = vim.fn.stdpath("data") .. "/avante/github-copilot.json"
local lockfile_path = vim.fn.stdpath("data") .. "/avante/copilot-timer.lock"

-- Lockfile management
local function is_process_running(pid)
  if vim.fn.has("win32") == 1 then
    return vim.fn.system('tasklist /FI "PID eq ' .. pid .. '" 2>NUL | find /I "' .. pid .. '"') ~= ""
  else
    return vim.fn.system("ps -p " .. pid .. " > /dev/null 2>&1; echo $?") == "0\n"
  end
end

local function try_acquire_timer_lock()
  local lockfile = Path:new(lockfile_path)

  local tmp_lockfile = lockfile_path .. ".tmp." .. vim.fn.getpid()

  Path:new(tmp_lockfile):write(tostring(vim.fn.getpid()), "w")

  -- Check existing lock
  if lockfile:exists() then
    local content = lockfile:read()
    local pid = tonumber(content)
    if pid and is_process_running(pid) then
      os.remove(tmp_lockfile)
      return false -- Another instance is already managing
    end
  end

  -- Attempt to take ownership
  local success = os.rename(tmp_lockfile, lockfile_path)
  if not success then
    os.remove(tmp_lockfile)
    return false
  end

  return true
end

local function start_manager_check_timer()
  if M._manager_check_timer then
    M._manager_check_timer:stop()
    M._manager_check_timer:close()
  end

  M._manager_check_timer = vim.uv.new_timer()
  M._manager_check_timer:start(
    30000,
    30000,
    vim.schedule_wrap(function()
      if not M._refresh_timer and try_acquire_timer_lock() then M.setup_timer() end
    end)
  )
end

---@class OAuthToken
---@field user string
---@field oauth_token string
---
---@return string
function H.get_oauth_token()
  local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
  local os_name = Utils.get_os_name()
  ---@type string
  local config_dir

  if xdg_config and vim.fn.isdirectory(xdg_config) > 0 then
    config_dir = xdg_config
  elseif vim.tbl_contains({ "linux", "darwin" }, os_name) then
    config_dir = vim.fn.expand("~/.config")
  else
    config_dir = vim.fn.expand("~/AppData/Local")
  end

  --- hosts.json (copilot.lua), apps.json (copilot.vim)
  ---@type Path[]
  local paths = vim.iter({ "hosts.json", "apps.json" }):fold({}, function(acc, path)
    local yason = Path:new(config_dir):joinpath("github-copilot", path)
    if yason:exists() then table.insert(acc, yason) end
    return acc
  end)
  if #paths == 0 then error("You must setup copilot with either copilot.lua or copilot.vim", 2) end

  local yason = paths[1]
  return vim
    .iter(
      ---@type table<string, OAuthToken>
      ---@diagnostic disable-next-line: param-type-mismatch
      vim.json.decode(yason:read())
    )
    :filter(function(k, _) return k:match("github.com") end)
    ---@param acc {oauth_token: string}
    :fold({}, function(acc, _, v)
      acc.oauth_token = v.oauth_token
      return acc
    end)
    .oauth_token
end

H.chat_auth_url = "https://api.github.com/copilot_internal/v2/token"
function H.chat_completion_url(base_url) return Utils.url_join(base_url, "/chat/completions") end
function H.response_url(base_url) return Utils.url_join(base_url, "/responses") end

function H.refresh_token(async, force)
  if not M.state then error("internal initialization error") end

  async = async == nil and true or async
  force = force or false

  -- Do not refresh token if not forced or not expired
  if
    not force
    and M.state.github_token
    and M.state.github_token.expires_at
    and M.state.github_token.expires_at > math.floor(os.time())
  then
    return false
  end

  local provider_conf = Providers.get_config("copilot")

  local curl_opts = {
    headers = {
      ["Authorization"] = "token " .. M.state.oauth_token,
      ["Accept"] = "application/json",
    },
    timeout = provider_conf.timeout,
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
  }

  local function handle_response(response)
    if response.status == 200 then
      M.state.github_token = vim.json.decode(response.body)
      local file = Path:new(copilot_path)
      file:write(vim.json.encode(M.state.github_token), "w")
      if not vim.g.avante_login then vim.g.avante_login = true end

      -- If triggered synchronously, reset timer
      if not async and M._refresh_timer then M.setup_timer() end

      return true
    else
      error("Failed to get success response: " .. vim.inspect(response))
      return false
    end
  end

  if async then
    curl.get(
      H.chat_auth_url,
      vim.tbl_deep_extend("force", {
        callback = handle_response,
      }, curl_opts)
    )
  else
    local response = curl.get(H.chat_auth_url, curl_opts)
    handle_response(response)
  end
end

---@private
---@class AvanteCopilotState
---@field oauth_token string
---@field github_token CopilotToken?
M.state = nil

M.api_key_name = ""
M.tokenizer_id = "gpt-4o"
M.support_prompt_caching = true
M.role_map = {
  user = "user",
  assistant = "assistant",
}

---@return boolean
function M:is_claude_model()
  local provider_conf = Providers.parse_config(self)
  local model_name = provider_conf.model:lower()
  return model_name:match("claude") ~= nil
end

function M:is_disable_stream() return false end

---@param usage table | nil
---@return table | nil
function M.transform_copilot_claude_usage(usage)
  if not usage then return nil end

  -- Calculate cache stats
  local cache_hit_tokens = usage.cache_read_input_tokens or 0
  local cache_write_tokens = usage.cache_creation_input_tokens or 0
  local total_input_tokens = usage.input_tokens or 0
  local cache_hit_rate = total_input_tokens > 0 and (cache_hit_tokens / total_input_tokens) or 0

  -- Record stats for visualization
  if not M.cache_stats then M.cache_stats = {} end
  table.insert(M.cache_stats, {
    timestamp = os.time(),
    cache_hit_tokens = cache_hit_tokens,
    cache_write_tokens = cache_write_tokens,
    total_input_tokens = total_input_tokens,
    cache_hit_rate = cache_hit_rate,
  })

  -- Return usage info with cache metrics
  return {
    prompt_tokens = total_input_tokens + cache_write_tokens,
    completion_tokens = usage.output_tokens,
    cache_hit_tokens = cache_hit_tokens,
    cache_write_tokens = cache_write_tokens,
    cache_hit_rate = cache_hit_rate,
  }
end

setmetatable(M, { __index = OpenAI })

function M:list_models()
  if M._model_list_cache then return M._model_list_cache end
  if not M._is_setup then M.setup() end
  -- refresh token synchronously, only if it has expired
  -- (this should rarely happen, as we refresh the token in the background)
  H.refresh_token(false, false)
  local provider_conf = Providers.parse_config(self)
  local headers = self:build_headers()
  local curl_opts = {
    headers = Utils.tbl_override(headers, self.extra_headers),
    timeout = provider_conf.timeout,
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
  }

  local function handle_response(response)
    if response.status == 200 then
      local body = vim.json.decode(response.body)
      -- ref: https://github.com/CopilotC-Nvim/CopilotChat.nvim/blob/16d897fd43d07e3b54478ccdb2f8a16e4df4f45a/lua/CopilotChat/config/providers.lua#L171-L187
      local models = vim
        .iter(body.data)
        :filter(function(model) return model.capabilities.type == "chat" and not vim.endswith(model.id, "paygo") end)
        :map(
          function(model)
            return {
              id = model.id,
              display_name = model.name,
              name = "copilot/" .. model.name .. " (" .. model.id .. ")",
              provider_name = "copilot",
              tokenizer = model.capabilities.tokenizer,
              max_input_tokens = model.capabilities.limits.max_prompt_tokens,
              max_output_tokens = model.capabilities.limits.max_output_tokens,
              policy = not model["policy"] or model["policy"]["state"] == "enabled",
              version = model.version,
            }
          end
        )
        :totable()
      M._model_list_cache = models
      return models
    else
      error("Failed to get success response: " .. vim.inspect(response))
      return {}
    end
  end

  local response = curl.get((M.state.github_token.endpoints.api or "") .. "/models", curl_opts)
  return handle_response(response)
end

function M:build_headers()
  return {
    ["Authorization"] = "Bearer " .. M.state.github_token.token,
    ["User-Agent"] = "GitHubCopilotChat/0.26.7",
    ["Editor-Version"] = "vscode/1.105.1",
    ["Editor-Plugin-Version"] = "copilot-chat/0.26.7",
    ["Copilot-Integration-Id"] = "vscode-chat",
    ["Openai-Intent"] = "conversation-edits",
  }
end

function M:parse_curl_args(prompt_opts)
  -- refresh token synchronously, only if it has expired
  -- (this should rarely happen, as we refresh the token in the background)
  H.refresh_token(false, false)

  local provider_conf, request_body = Providers.parse_config(self)
  local use_response_api = Providers.resolve_use_response_api(provider_conf, prompt_opts)
  local disable_tools = provider_conf.disable_tools or false

  -- Apply OpenAI's set_allowed_params for Response API compatibility
  OpenAI.set_allowed_params(provider_conf, request_body)

  -- Check if this is a Claude model and if prompt caching is enabled
  local is_claude = self:is_claude_model()
  local Config = require("avante.config")
  local prompt_caching_enabled = Config.prompt_caching
    and Config.prompt_caching.enabled
    and Config.prompt_caching.providers
    and Config.prompt_caching.providers.copilot

  local use_ReAct_prompt = provider_conf.use_ReAct_prompt == true

  local tools = nil
  if not disable_tools and prompt_opts.tools and not use_ReAct_prompt then
    tools = {}
    for _, tool in ipairs(prompt_opts.tools) do
      local transformed_tool = OpenAI:transform_tool(tool)
      -- Response API uses flattened tool structure
      if use_response_api then
        if transformed_tool.type == "function" and transformed_tool["function"] then
          transformed_tool = {
            type = "function",
            name = transformed_tool["function"].name,
            description = transformed_tool["function"].description,
            parameters = transformed_tool["function"].parameters,
          }
        end
      end
      table.insert(tools, transformed_tool)
    end
  end

  local headers = self:build_headers()

  -- Add Claude-specific headers for prompt caching if applicable
  if is_claude and prompt_caching_enabled then headers["anthropic-beta"] = "prompt-caching-2024-07-31" end

  if prompt_opts.messages and #prompt_opts.messages > 0 then
    local last_message = prompt_opts.messages[#prompt_opts.messages]
    local initiator = last_message.role == "user" and "user" or "agent"
    headers["X-Initiator"] = initiator
  end

  local parsed_messages = self:parse_messages(prompt_opts)

  -- Build base body
  local base_body = {
    model = provider_conf.model,
    stream = true,
    tools = tools,
  }
  --
  -- Process messages for Claude prompt caching
  -- Add cache_control to messages if prompt caching is enabled for Claude models
  if is_claude and self.support_prompt_caching and prompt_caching_enabled and #parsed_messages > 0 then
    local found = false
    for i = #parsed_messages, 1, -1 do
      local message = parsed_messages[i]
      message = vim.deepcopy(message)
      -- Handle content differently based on whether it's a string or array
      if type(message.content) == "string" then
        -- For string content, convert to object with cache_control
        if message.role == "user" then
          message.content = {
            { type = "text", text = message.content, cache_control = { type = "ephemeral" } },
          }
          found = true
          break
        end
      elseif type(message.content) == "table" then
        -- For array content, add cache_control to the last text item
        for j = #message.content, 1, -1 do
          local item = message.content[j]
          if type(item) == "table" and item.type == "text" then
            item.cache_control = { type = "ephemeral" }
            found = true
            break
          end
        end
      end
      if found then
        parsed_messages[i] = message
        break
      end
    end
  end

  -- Add cache_control to tools if prompt caching is enabled for Claude models
  if is_claude and self.support_prompt_caching and prompt_caching_enabled and #tools > 0 then
    local last_tool = vim.deepcopy(tools[#tools])
    last_tool.cache_control = { type = "ephemeral" }
    tools[#tools] = last_tool
  end

  -- Response API uses 'input' instead of 'messages'
  -- NOTE: Copilot doesn't support previous_response_id, always send full history
  if use_response_api then
    base_body.input = parsed_messages

    -- Response API uses max_output_tokens instead of max_tokens/max_completion_tokens
    if request_body.max_completion_tokens then
      request_body.max_output_tokens = request_body.max_completion_tokens
      request_body.max_completion_tokens = nil
    end
    if request_body.max_tokens then
      request_body.max_output_tokens = request_body.max_tokens
      request_body.max_tokens = nil
    end
    -- Response API doesn't use stream_options
    base_body.stream_options = nil
    base_body.include = { "reasoning.encrypted_content" }
    base_body.reasoning = {
      summary = "detailed",
    }
    base_body.truncation = "disabled"
  else
    base_body.messages = parsed_messages
    base_body.stream_options = {
      include_usage = true,
    }
  end

  local base_url = M.state.github_token.endpoints.api or provider_conf.endpoint
  local build_url = use_response_api and H.response_url or H.chat_completion_url

  return {
    url = build_url(base_url),
    timeout = provider_conf.timeout,
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = Utils.tbl_override(headers, self.extra_headers),
    body = vim.tbl_deep_extend("force", base_body, request_body),
  }
end

M._refresh_timer = nil

function M.setup_timer()
  if M._refresh_timer then
    M._refresh_timer:stop()
    M._refresh_timer:close()
  end

  -- Calculate time until token expires
  local now = math.floor(os.time())
  local expires_at = M.state.github_token and M.state.github_token.expires_at or now
  local time_until_expiry = math.max(0, expires_at - now)
  -- Refresh 2 minutes before expiration
  local initial_interval = math.max(0, (time_until_expiry - 120) * 1000)
  -- Regular interval of 28 minutes after the first refresh
  local repeat_interval = 28 * 60 * 1000

  M._refresh_timer = vim.uv.new_timer()
  M._refresh_timer:start(
    initial_interval,
    repeat_interval,
    vim.schedule_wrap(function() H.refresh_token(true, true) end)
  )
end

function M.setup_file_watcher()
  if M._file_watcher then return end

  local copilot_token_file = Path:new(copilot_path)
  M._file_watcher = vim.uv.new_fs_event()

  M._file_watcher:start(
    copilot_path,
    {},
    vim.schedule_wrap(function()
      -- Reload token from file
      if copilot_token_file:exists() then
        local ok, token = pcall(vim.json.decode, copilot_token_file:read())
        if ok then M.state.github_token = token end
      end
    end)
  )
end

M._is_setup = false

function M.is_env_set()
  local ok = pcall(function() H.get_oauth_token() end)
  return ok
end

function M.setup()
  local copilot_token_file = Path:new(copilot_path)

  if not M.state then M.state = {
    github_token = nil,
    oauth_token = H.get_oauth_token(),
  } end

  -- Load and validate existing token
  if copilot_token_file:exists() then
    local ok, token = pcall(vim.json.decode, copilot_token_file:read())
    if ok and token.expires_at and token.expires_at > math.floor(os.time()) then M.state.github_token = token end
  end

  -- Setup timer management
  local timer_lock_acquired = try_acquire_timer_lock()
  if timer_lock_acquired then
    M.setup_timer()
  else
    vim.schedule(function() H.refresh_token(true, false) end)
  end

  M.setup_file_watcher()

  start_manager_check_timer()

  require("avante.tokenizers").setup(M.tokenizer_id)
  vim.g.avante_login = true
  M._is_setup = true
end

function M.cleanup()
  -- Cleanup refresh timer
  if M._refresh_timer then
    M._refresh_timer:stop()
    M._refresh_timer:close()
    M._refresh_timer = nil

    -- Remove lockfile if we were the manager
    local lockfile = Path:new(lockfile_path)
    if lockfile:exists() then
      local content = lockfile:read()
      local pid = tonumber(content)
      if pid and pid == vim.fn.getpid() then lockfile:rm() end
    end
  end

  -- Cleanup manager check timer
  if M._manager_check_timer then
    M._manager_check_timer:stop()
    M._manager_check_timer:close()
    M._manager_check_timer = nil
  end

  -- Cleanup file watcher
  if M._file_watcher then
    ---@diagnostic disable-next-line: param-type-mismatch
    M._file_watcher:stop()
    M._file_watcher = nil
  end
end

-- Register cleanup on Neovim exit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function() M.cleanup() end,
})

return M
