---@class AvanteBedrockClaudeTextMessage
---@field type "text"
---@field text string
---
---@class AvanteBedrockClaudeMessage
---@field role "user" | "assistant"
---@field content [AvanteBedrockClaudeTextMessage][]

local P = require("avante.providers")
local Claude = require("avante.providers.claude")
local Config = require("avante.config")
local Utils = require("avante.utils")

---@class AvanteBedrockModelHandler
local M = {}

M.support_prompt_caching = true
M.role_map = {
  user = "user",
  assistant = "assistant",
}

---@param message AvanteBedrockClaudeMessage
---@param index integer
---@return boolean
function M:is_static_content(message, index)
  -- System prompts are typically static
  if message.role == "system" then return true end

  -- Consider first user message as static (usually contains context/instructions)
  -- Use the configured static_message_count or default to 2
  local static_message_count = Config.prompt_caching and Config.prompt_caching.static_message_count or 2
  if index <= static_message_count then return true end

  return false
end

---@param messages AvanteBedrockClaudeMessage[]
---@param system_prompt string|table
---@param index integer
---@return integer
function M:count_tokens_before(messages, system_prompt, index)
  local Utils = require("avante.utils")
  local token_count = 0

  -- Count tokens in system prompt
  if system_prompt then
    if type(system_prompt) == "string" then
      token_count = token_count + Utils.tokens.calculate_tokens(system_prompt)
    elseif type(system_prompt) == "table" then
      for _, item in ipairs(system_prompt) do
        if item.type == "text" then token_count = token_count + Utils.tokens.calculate_tokens(item.text) end
      end
    end
  end

  -- Count tokens in messages up to the index
  for i = 1, index do
    local message = messages[i]
    for _, item in ipairs(message.content) do
      if item.type == "text" then token_count = token_count + Utils.tokens.calculate_tokens(item.text) end
    end
  end

  return token_count
end

M.is_disable_stream = Claude.is_disable_stream
M.parse_messages = Claude.parse_messages
M.parse_response = Claude.parse_response
M.transform_tool = Claude.transform_tool
M.transform_anthropic_usage = Claude.transform_anthropic_usage
M.analyze_cache_performance = Claude.analyze_cache_performance

---@param provider AvanteProviderFunctor
---@param prompt_opts AvantePromptOptions
---@param request_body table
---@return table
function M.build_bedrock_payload(provider, prompt_opts, request_body)
  local system_prompt = prompt_opts.system_prompt or ""
  local messages = provider:parse_messages(prompt_opts)
  local max_tokens = request_body.max_tokens or 2000

  local provider_conf, _ = P.parse_config(provider)
  local disable_tools = provider_conf.disable_tools or false
  local tools = {}
  if not disable_tools and prompt_opts.tools then
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, provider:transform_tool(tool))
    end
  end

  -- Check if prompt caching is enabled for this provider
  local prompt_caching_enabled = Config.prompt_caching
    and Config.prompt_caching.enabled
    and Config.prompt_caching.providers.bedrock

  -- Determine minimum token threshold based on model
  local min_tokens = 1024 -- Default
  if Config.prompt_caching and Config.prompt_caching.min_tokens_threshold then
    if
      provider_conf.model:match("claude%-3%-5%-haiku")
      and Config.prompt_caching.min_tokens_threshold["claude-3-5-haiku"]
    then
      min_tokens = Config.prompt_caching.min_tokens_threshold["claude-3-5-haiku"]
    elseif
      provider_conf.model:match("claude%-3%-7%-sonnet")
      and Config.prompt_caching.min_tokens_threshold["claude-3-7-sonnet"]
    then
      min_tokens = Config.prompt_caching.min_tokens_threshold["claude-3-7-sonnet"]
    elseif Config.prompt_caching.min_tokens_threshold.default then
      min_tokens = Config.prompt_caching.min_tokens_threshold.default
    end
  end

  -- Track token count for threshold check
  local current_tokens = 0

  -- Add cache_control to system prompt if prompt caching is supported and enabled
  if M.support_prompt_caching and prompt_caching_enabled and system_prompt ~= "" then
    -- Count tokens in system prompt
    if type(system_prompt) == "string" then current_tokens = Utils.tokens.calculate_tokens(system_prompt) end

    -- Only add cache control if we meet the minimum token threshold
    if current_tokens >= min_tokens then
      system_prompt = {
        {
          type = "text",
          text = system_prompt,
          cache_control = { type = "ephemeral" },
        },
      }
    else
      system_prompt = {
        {
          type = "text",
          text = system_prompt,
        },
      }
    end
  end

  -- Add cache_control to messages if prompt caching is supported and enabled
  if M.support_prompt_caching and prompt_caching_enabled and #messages > 0 then
    -- Get the cache strategy from config
    local cache_strategy = Config.prompt_caching and Config.prompt_caching.strategy or "simplified"

    if cache_strategy == "simplified" then
      -- Simplified approach: place a single cache checkpoint at the end of static content
      -- This allows the model to automatically find the best cache match
      local static_boundary_idx = 0
      for i = 1, #messages do
        if M:is_static_content(messages[i], i) then
          -- Count tokens up to this point to check threshold
          current_tokens = M:count_tokens_before(messages, system_prompt, i)

          -- Only consider this as a boundary if we've reached the token threshold
          if current_tokens >= min_tokens then static_boundary_idx = i end
        else
          break
        end
      end

      -- Add cache checkpoint at the end of static content if we found any
      if static_boundary_idx > 0 then
        local message = vim.deepcopy(messages[static_boundary_idx])
        local content = message.content
        for j = #content, 1, -1 do
          local item = content[j]
          if item.type == "text" then
            item.cache_control = { type = "ephemeral" }
            messages[static_boundary_idx] = message
            break
          end
        end
      end
    else
      -- Manual approach: place cache checkpoints at multiple points
      -- This gives more control but may be less effective than the simplified approach
      for i = 1, #messages do
        if M:is_static_content(messages[i], i) then
          -- Count tokens up to this point to check threshold
          current_tokens = M:count_tokens_before(messages, system_prompt, i)

          -- Only add cache checkpoint if we've reached the minimum token threshold
          if current_tokens >= min_tokens then
            local message = vim.deepcopy(messages[i])
            local content = message.content
            for j = #content, 1, -1 do
              local item = content[j]
              if item.type == "text" then
                item.cache_control = { type = "ephemeral" }
                messages[i] = message
                break
              end
            end
          end
        end
      end
    end
  end


  local payload = {
    anthropic_version = "bedrock-2023-05-31",
    max_tokens = max_tokens,
    messages = messages,
    tools = tools,
    system = system_prompt,
  }
  return vim.tbl_deep_extend("force", payload, request_body or {})
end

return M
