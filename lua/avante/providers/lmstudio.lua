local Utils = require("avante.utils")
local Providers = require("avante.providers")

---@class AvanteProviderFunctor
local M = {}

-- Metatable delegation pattern (same as Ollama).
-- This allows list_models to work despite having no __inherited_from,
-- because model_selector.lua excludes providers with __inherited_from from
-- dynamic list_models. By using metatable instead, we "borrow" OpenAI/Claude
-- functions without triggering the exclusion.
setmetatable(M, {
  __index = function(_, k)
    -- Filter out keys that should not be delegated
    if k == "model" or k == "model_names" or k == "check_endpoint_alive" then return nil end
    -- Read mode from Config.providers (plain table, zero recursion risk)
    local ok, Config = pcall(require, "avante.config")
    if ok then
      local lm_cfg = Config.providers and Config.providers.lmstudio
      local mode = lm_cfg and lm_cfg.mode or "openai"
      if mode == "anthropic" then return Providers.claude[k] end
    end
    return Providers.openai[k]
  end,
})

M.tokenizer_id = "gpt-4o"
M.role_map = {
  user = "user",
  assistant = "assistant",
}

---Parse the LM Studio API key from config
---Returns empty string if not configured (LM Studio auth is optional)
---@return string
function M.parse_api_key()
  local provider_conf = Providers.parse_config(M)
  return provider_conf.api_key or ""
end

---Read the mode from the resolved provider config.
---Safe to call from methods (NOT from __index — use Config.providers there).
---@return LmStudioMode
local function get_mode_safe()
  local ok, provider_conf = pcall(Providers.parse_config, M)
  if not ok then return "openai" end
  local mode = provider_conf.mode or "openai"
  if mode ~= "openai" and mode ~= "anthropic" and mode ~= "lmstudio" then
    Utils.warn("LM Studio: Invalid mode '" .. mode .. "', defaulting to 'openai'")
    mode = "openai"
  end
  return mode
end

---Check if server defaults should be used
---@return boolean
local function use_server_defaults()
  local provider_conf = Providers.parse_config(M)
  ---@diagnostic disable-next-line: undefined-field
  return provider_conf.use_server_defaults == true
end

---Fetch model metadata from LM Studio to get context_length
---@param model_name string
---@param timeout? integer Timeout in milliseconds
---@return table|nil model_info Model metadata including context_length
local function get_model_info(model_name, timeout)
  local curl = require("plenary.curl")
  local models_endpoint = Utils.url_join("http://127.0.0.1:1234", "/api/v1/models")

  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }

  -- Add Authorization header if API key is configured
  local api_key = M.parse_api_key()
  if api_key and api_key ~= "" then headers["Authorization"] = "Bearer " .. api_key end

  local response = {}
  local job = curl.get(models_endpoint, {
    headers = headers,
    callback = function(output) response = output end,
    timeout = timeout or 5000,
  })
  job.wait(job, timeout or 5000)

  if response.status ~= 200 then return nil end

  local ok, res_body = pcall(vim.json.decode, response.body)
  if not ok then return nil end

  local models_list = res_body.models or res_body.data or {}
  for _, model in ipairs(models_list) do
    if (model.id or model.model) == model_name then return model end
  end

  return nil
end

---Strip server-configurable values from request body when use_server_defaults is enabled
---@param body table<string, any>
---@return table<string, any>
local function filter_server_defaults(body)
  local filtered = vim.deepcopy(body)
  filtered.temperature = nil
  filtered.max_tokens = nil
  filtered.max_completion_tokens = nil
  return filtered
end

---Queries the configured endpoint for available models
---@param opts AvanteProviderFunctor Provider settings
---@param timeout? integer Timeout in milliseconds
---@return table[]|nil models List of available models
---@return string|nil error Error message in case of failure
local function query_models(opts, timeout)
  local provider_conf = Providers.parse_config(opts)
  if not provider_conf.endpoint then return nil, "LM Studio requires endpoint configuration" end

  local curl = require("plenary.curl")

  local mode = get_mode_safe()
  local models_endpoint
  if mode == "openai" then
    models_endpoint = Utils.url_join(provider_conf.endpoint, "/v1/models")
  else
    -- For anthropic and native modes, fall back to native endpoint
    -- since LM Studio always exposes /api/v1/models regardless of chat API mode
    models_endpoint = Utils.url_join(provider_conf.endpoint, "/api/v1/models")
  end

  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }

  local api_key = M.parse_api_key()
  if api_key and api_key ~= "" then headers["Authorization"] = "Bearer " .. api_key end

  local response = {}
  local job = curl.get(models_endpoint, {
    headers = headers,
    callback = function(output) response = output end,
    on_error = function(err) response = { exit = err.exit } end,
  })
  local job_ok, error = pcall(job.wait, job, timeout or 10000)
  if not job_ok then
    return nil, "LM Studio: curl command invocation failed: " .. error
  elseif response.exit ~= 0 then
    return nil, "LM Studio: curl returned error: " .. response.exit
  elseif response.status ~= 200 then
    return nil, "Failed to fetch LM Studio models: " .. (response.body or response.status)
  end

  local ok, res_body = pcall(vim.json.decode, response.body)
  if not ok then return nil, "Failed to parse model list query response" end

  -- Handle both response formats: OpenAI ({data: [...]}) and LM Studio native ({models: [...]})
  local models_list = res_body.models or res_body.data or {}

  return models_list
end

---List available models using LM Studio's models API
function M:list_models()
  if self._model_list_cache then return self._model_list_cache end

  local result, error = query_models(self)
  if not result then
    assert(error)
    Utils.error(error)
    return {}
  end

  local models = {}
  for _, model in ipairs(result) do
    local model_id = model.id or model.model or ""
    if model_id ~= "" then
      table.insert(models, {
        id = model_id,
        name = "lmstudio/" .. model_id,
        display_name = model_id,
      })
    end
  end

  self._model_list_cache = models
  return models
end

---Parse curl args for the API request based on mode
---@param prompt_opts AvantePromptOptions
---@return AvanteCurlOutput|nil
function M:parse_curl_args(prompt_opts)
  local mode = get_mode_safe()
  local provider_conf, request_body = Providers.parse_config(self)

  if mode == "openai" then
    local openai_args = Providers.openai.parse_curl_args(self, prompt_opts)
    if not openai_args then return nil end
    openai_args.url = Utils.url_join(provider_conf.endpoint, "/v1/chat/completions")
    local api_key = M.parse_api_key()
    if api_key and api_key ~= "" then openai_args.headers["Authorization"] = "Bearer " .. api_key end
    if use_server_defaults() then
      local body = openai_args.body
      if type(body) == "table" then openai_args.body = filter_server_defaults(body) end
    end
    return openai_args
  elseif mode == "anthropic" then
    local claude_args = Providers.claude.parse_curl_args(self, prompt_opts)
    if not claude_args then return nil end
    claude_args.url = Utils.url_join(provider_conf.endpoint, "/v1/messages")
    local api_key = M.parse_api_key()
    if api_key and api_key ~= "" then claude_args.headers["Authorization"] = "Bearer " .. api_key end
    if use_server_defaults() then
      local body = claude_args.body
      if type(body) == "table" then claude_args.body = filter_server_defaults(body) end
    end
    return claude_args
  end

  -- Native mode: build custom curl args for LM Studio's /api/v1/chat
  local headers = {
    ["Content-Type"] = "application/json",
  }

  local api_key = M.parse_api_key()
  if api_key and api_key ~= "" then headers["Authorization"] = "Bearer " .. api_key end

  local messages = {}
  local system_prompt = prompt_opts.system_prompt
  table.insert(messages, { role = "system", content = system_prompt })

  vim.iter(prompt_opts.messages):each(function(msg)
    if type(msg.content) == "string" then
      table.insert(messages, { role = msg.role, content = msg.content })
    elseif type(msg.content) == "table" then
      local text_parts = {}
      for _, item in ipairs(msg.content) do
        if type(item) == "string" then
          table.insert(text_parts, item)
        elseif item.type == "text" and item.text then
          table.insert(text_parts, item.text)
        end
      end
      if #text_parts > 0 then table.insert(messages, { role = msg.role, content = table.concat(text_parts, "\n") }) end
    end
  end)

  local base_body = {
    model = provider_conf.model,
    messages = messages,
    stream = true,
  }

  local body = vim.tbl_deep_extend("force", base_body, request_body)
  if use_server_defaults() then body = filter_server_defaults(body) end

  return {
    url = Utils.url_join(provider_conf.endpoint, "/api/v1/chat"),
    headers = Utils.tbl_override(headers, self.extra_headers),
    body = body,
  }
end

M.on_error = function(result)
  local error_msg = "LM Studio API error"
  if result.body then
    local ok, body = pcall(vim.json.decode, result.body)
    if ok and body.error then error_msg = body.error end
    if ok and body.message then error_msg = body.message end
  end
  Utils.error(error_msg, { title = "LM Studio" })
end

---Get the context window size for the current model.
---If use_server_context_window is enabled, dynamically fetches context_length
---from the LM Studio server's model metadata. Otherwise returns the configured
---context_window value.
---Caches the result to avoid repeated network requests.
---@return integer
function M:get_context_window()
  -- Return cached value if available
  if self._context_window_cache then return self._context_window_cache end

  local provider_conf = Providers.parse_config(self)

  -- If server context window fetching is disabled, return configured default
  ---@diagnostic disable-next-line: undefined-field
  if provider_conf.use_server_context_window ~= true then
    self._context_window_cache = provider_conf.context_window or 128000
    return self._context_window_cache
  end

  -- Dynamically fetch from server
  local model_name = provider_conf.model
  if not model_name or model_name == "" then
    Utils.warn("LM Studio: No model selected, using default context_window")
    self._context_window_cache = provider_conf.context_window or 128000
    return self._context_window_cache
  end

  local model_info = get_model_info(model_name, provider_conf.timeout)
  if model_info and model_info.context_length then
    self._context_window_cache = model_info.context_length
    return self._context_window_cache
  end

  -- Fallback to configured value if fetching fails
  Utils.warn("LM Studio: Failed to fetch context_length for '" .. model_name .. "', using default")
  self._context_window_cache = provider_conf.context_window or 128000
  return self._context_window_cache
end

return M
