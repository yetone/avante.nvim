local Utils = require("avante.utils")
local Providers = require("avante.providers")
local Config = require("avante.config")
local Clipboard = require("avante.clipboard")
local HistoryMessage = require("avante.history.message")
local Prompts = require("avante.utils.prompts")

---@class AvanteProviderFunctor
local M = {}

setmetatable(M, { __index = Providers.openai })

M.api_key_name = "" -- Ollama typically doesn't require API keys for local use

M.role_map = {
  user = "user",
  assistant = "assistant",
}

function M.is_env_set() return false end

function M:parse_messages(opts)
  local messages = {}
  local provider_conf, _ = Providers.parse_config(self)

  local system_prompt = Prompts.get_ReAct_system_prompt(provider_conf, opts)

  if self.is_reasoning_model(provider_conf.model) then
    table.insert(messages, { role = "developer", content = system_prompt })
  else
    table.insert(messages, { role = "system", content = system_prompt })
  end

  vim.iter(opts.messages):each(function(msg)
    if type(msg.content) == "string" then
      table.insert(messages, { role = self.role_map[msg.role], content = msg.content })
    elseif type(msg.content) == "table" then
      local content = {}
      for _, item in ipairs(msg.content) do
        if type(item) == "string" then
          table.insert(content, { type = "text", text = item })
        elseif item.type == "text" then
          table.insert(content, { type = "text", text = item.text })
        elseif item.type == "image" then
          table.insert(content, {
            type = "image_url",
            image_url = {
              url = "data:" .. item.source.media_type .. ";" .. item.source.type .. "," .. item.source.data,
            },
          })
        end
      end
      if not provider_conf.disable_tools then
        if msg.content[1].type == "tool_result" then
          local tool_use = nil
          for _, msg_ in ipairs(opts.messages) do
            if type(msg_.content) == "table" and #msg_.content > 0 then
              if msg_.content[1].type == "tool_use" and msg_.content[1].id == msg.content[1].tool_use_id then
                tool_use = msg_
                break
              end
            end
          end
          if tool_use then
            msg.role = "user"
            table.insert(content, {
              type = "text",
              text = "["
                .. tool_use.content[1].name
                .. " for '"
                .. (tool_use.content[1].input.path or tool_use.content[1].input.rel_path or "")
                .. "'] Result:",
            })
            table.insert(content, {
              type = "text",
              text = msg.content[1].content,
            })
          end
        end
      end
      if #content > 0 then
        local text_content = {}
        for _, item in ipairs(content) do
          if type(item) == "table" and item.type == "text" then table.insert(text_content, item.text) end
        end
        table.insert(messages, { role = self.role_map[msg.role], content = table.concat(text_content, "\n\n") })
      end
    end
  end)

  if Config.behaviour.support_paste_from_clipboard and opts.image_paths and #opts.image_paths > 0 then
    local message_content = messages[#messages].content
    if type(message_content) ~= "table" or message_content[1] == nil then
      message_content = { { type = "text", text = message_content } }
    end
    for _, image_path in ipairs(opts.image_paths) do
      table.insert(message_content, {
        type = "image_url",
        image_url = {
          url = "data:image/png;base64," .. Clipboard.get_base64_content(image_path),
        },
      })
    end
    messages[#messages].content = message_content
  end

  local final_messages = {}
  local prev_role = nil

  vim.iter(messages):each(function(message)
    local role = message.role
    if role == prev_role and role ~= "tool" then
      if role == self.role_map["assistant"] then
        table.insert(final_messages, { role = self.role_map["user"], content = "Ok" })
      else
        table.insert(final_messages, { role = self.role_map["assistant"], content = "Ok, I understand." })
      end
    end
    prev_role = role
    table.insert(final_messages, message)
  end)

  return final_messages
end

function M:is_disable_stream() return false end

---@class avante.OllamaFunction
---@field name string
---@field arguments table

---@class avante.OllamaToolCall
---@field function avante.OllamaFunction

---@param tool_calls avante.OllamaToolCall[]
---@param opts AvanteLLMStreamOptions
function M:add_tool_use_messages(tool_calls, opts)
  if opts.on_messages_add then
    local msgs = {}
    for _, tool_call in ipairs(tool_calls) do
      local id = Utils.uuid()
      local func = tool_call["function"]
      local msg = HistoryMessage:new("assistant", {
        type = "tool_use",
        name = func.name,
        id = id,
        input = func.arguments,
      }, {
        state = "generated",
        uuid = id,
      })
      table.insert(msgs, msg)
    end
    opts.on_messages_add(msgs)
  end
end

function M:parse_stream_data(ctx, data, opts)
  local ok, jsn = pcall(vim.json.decode, data)
  if not ok or not jsn then
    -- Add debug logging
    Utils.debug("Failed to parse JSON", data)
    return
  end

  if jsn.message then
    if jsn.message.content then
      local content = jsn.message.content
      if content and content ~= "" then
        Providers.openai:add_text_message(ctx, content, "generating", opts)
        if opts.on_chunk then opts.on_chunk(content) end
      end
    end
    if jsn.message.tool_calls then
      ctx.has_tool_use = true
      local tool_calls = jsn.message.tool_calls
      self:add_tool_use_messages(tool_calls, opts)
    end
  end

  if jsn.done then
    Providers.openai:finish_pending_messages(ctx, opts)
    if ctx.has_tool_use or (ctx.tool_use_list and #ctx.tool_use_list > 0) then
      opts.on_stop({ reason = "tool_use" })
    else
      opts.on_stop({ reason = "complete" })
    end
    return
  end
end

---@param prompt_opts AvantePromptOptions
function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = Providers.parse_config(self)
  local keep_alive = provider_conf.keep_alive or "5m"

  if not provider_conf.model or provider_conf.model == "" then error("Ollama model must be specified in config") end
  if not provider_conf.endpoint then error("Ollama requires endpoint configuration") end
  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }

  if Providers.env.require_api_key(provider_conf) then
    local api_key = self.parse_api_key()
    if api_key and api_key ~= "" then
      headers["Authorization"] = "Bearer " .. api_key
    else
      Utils.info((Config.provider or "Provider") .. ": API key not set, continuing without authentication")
    end
  end

  return {
    url = Utils.url_join(provider_conf.endpoint, "/api/chat"),
    headers = Utils.tbl_override(headers, self.extra_headers),
    body = vim.tbl_deep_extend("force", {
      model = provider_conf.model,
      messages = self:parse_messages(prompt_opts),
      stream = true,
      keep_alive = keep_alive,
    }, request_body),
  }
end

---@param result table
M.on_error = function(result)
  local error_msg = "Ollama API error"
  if result.body then
    local ok, body = pcall(vim.json.decode, result.body)
    if ok and body.error then error_msg = body.error end
  end
  Utils.error(error_msg, { title = "Ollama" })
end

-- List available models using Ollama's tags API
function M:list_models()
  -- Return cached models if available
  if self._model_list_cache then return self._model_list_cache end

  -- Parse provider config and construct tags endpoint URL
  local provider_conf = Providers.parse_config(self)
  if not provider_conf.endpoint then error("Ollama requires endpoint configuration") end

  local curl = require("plenary.curl")
  local tags_url = Utils.url_join(provider_conf.endpoint, "/api/tags")
  local base_headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }
  local headers = Utils.tbl_override(base_headers, self.extra_headers)

  -- Request the model tags from Ollama
  local response = curl.get(tags_url, { headers = headers })
  if response.status ~= 200 then
    Utils.error("Failed to fetch Ollama models: " .. (response.body or response.status))
    return {}
  end

  -- Parse the response body
  local ok, res_body = pcall(vim.json.decode, response.body)
  if not ok or not res_body.models then return {} end

  -- Helper to format model display string from its details
  local function format_display_name(details)
    local parts = {}
    for _, key in ipairs({ "family", "parameter_size", "quantization_level" }) do
      if details[key] then table.insert(parts, details[key]) end
    end
    return table.concat(parts, ", ")
  end

  -- Format the models list
  local models = {}
  for _, model in ipairs(res_body.models) do
    local details = model.details or {}
    local display = format_display_name(details)
    table.insert(models, {
      id = model.name,
      name = string.format("ollama/%s (%s)", model.name, display),
      display_name = model.name,
      provider_name = "ollama",
      version = model.digest,
    })
  end

  self._model_list_cache = models
  return models
end

return M
