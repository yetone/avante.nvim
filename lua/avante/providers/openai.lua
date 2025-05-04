local Utils = require("avante.utils")
local Config = require("avante.config")
local Clipboard = require("avante.clipboard")
local Providers = require("avante.providers")
local HistoryMessage = require("avante.history_message")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "OPENAI_API_KEY"

M.role_map = {
  user = "user",
  assistant = "assistant",
}

function M:is_disable_stream() return false end

---@param tool AvanteLLMTool
---@return AvanteOpenAITool
function M:transform_tool(tool)
  local input_schema_properties, required = Utils.llm_tool_param_fields_to_json_schema(tool.param.fields)
  ---@type AvanteOpenAIToolFunctionParameters
  local parameters = nil
  if not vim.tbl_isempty(input_schema_properties) then
    parameters = {
      type = "object",
      properties = input_schema_properties,
      required = required,
      additionalProperties = false,
    }
  end
  ---@type AvanteOpenAITool
  local res = {
    type = "function",
    ["function"] = {
      name = tool.name,
      description = tool.get_description and tool.get_description() or tool.description,
      parameters = parameters,
    },
  }
  return res
end

function M.is_openrouter(url) return url:match("^https://openrouter%.ai/") end

---@param opts AvantePromptOptions
function M.get_user_message(opts)
  vim.deprecate("get_user_message", "parse_messages", "0.1.0", "avante.nvim")
  return table.concat(
    vim
      .iter(opts.messages)
      :filter(function(_, value) return value == nil or value.role ~= "user" end)
      :fold({}, function(acc, value)
        acc = vim.list_extend({}, acc)
        acc = vim.list_extend(acc, { value.content })
        return acc
      end),
    "\n"
  )
end

function M.is_reasoning_model(model) return model and string.match(model, "^o%d+") ~= nil end

function M.set_allowed_params(provider_conf, request_body)
  if M.is_reasoning_model(provider_conf.model) then
    request_body.temperature = 1
  else
    request_body.reasoning_effort = nil
  end
  -- If max_tokens is set in config, unset max_completion_tokens
  if request_body.max_tokens then request_body.max_completion_tokens = nil end
end

function M:parse_messages(opts)
  local messages = {}
  local provider_conf, _ = Providers.parse_config(self)

  if self.is_reasoning_model(provider_conf.model) then
    table.insert(messages, { role = "developer", content = opts.system_prompt })
  else
    table.insert(messages, { role = "system", content = opts.system_prompt })
  end

  local has_tool_use = false

  vim.iter(opts.messages):each(function(msg)
    if type(msg.content) == "string" then
      table.insert(messages, { role = self.role_map[msg.role], content = msg.content })
    elseif type(msg.content) == "table" then
      local content = {}
      local tool_calls = {}
      local tool_results = {}
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
        elseif item.type == "tool_use" then
          has_tool_use = true
          table.insert(tool_calls, {
            id = item.id,
            type = "function",
            ["function"] = { name = item.name, arguments = vim.json.encode(item.input) },
          })
        elseif item.type == "tool_result" and has_tool_use then
          table.insert(
            tool_results,
            { tool_call_id = item.tool_use_id, content = item.is_error and "Error: " .. item.content or item.content }
          )
        end
      end
      if #content > 0 then table.insert(messages, { role = self.role_map[msg.role], content = content }) end
      if not provider_conf.disable_tools then
        if #tool_calls > 0 then
          local last_message = messages[#messages]
          if last_message and last_message.role == self.role_map["assistant"] and last_message.tool_calls then
            last_message.tool_calls = vim.list_extend(last_message.tool_calls, tool_calls)
          else
            table.insert(messages, { role = self.role_map["assistant"], tool_calls = tool_calls })
          end
        end
        if #tool_results > 0 then
          for _, tool_result in ipairs(tool_results) do
            table.insert(
              messages,
              { role = "tool", tool_call_id = tool_result.tool_call_id, content = tool_result.content or "" }
            )
          end
        end
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

function M:finish_pending_messages(ctx, opts)
  if ctx.content ~= nil and ctx.content ~= "" then self:add_text_message(ctx, "", "generated", opts) end
  if ctx.tool_use_list then
    for _, tool_use in ipairs(ctx.tool_use_list) do
      if tool_use.state == "generating" then self:add_tool_use_message(tool_use, "generated", opts) end
    end
  end
end

function M:add_text_message(ctx, text, state, opts)
  if ctx.content == nil then ctx.content = "" end
  ctx.content = ctx.content .. text
  local msg = HistoryMessage:new({
    role = "assistant",
    content = ctx.content,
  }, {
    state = state,
    uuid = ctx.content_uuid,
  })
  ctx.content_uuid = msg.uuid
  if opts.on_messages_add then opts.on_messages_add({ msg }) end
end

function M:add_thinking_message(ctx, text, state, opts)
  if ctx.reasonging_content == nil then ctx.reasonging_content = "" end
  ctx.reasonging_content = ctx.reasonging_content .. text
  local msg = HistoryMessage:new({
    role = "assistant",
    content = {
      {
        type = "thinking",
        thinking = ctx.reasonging_content,
        signature = "",
      },
    },
  }, {
    state = state,
    uuid = ctx.reasonging_content_uuid,
  })
  ctx.reasonging_content_uuid = msg.uuid
  if opts.on_messages_add then opts.on_messages_add({ msg }) end
end

function M:add_tool_use_message(tool_use, state, opts)
  local jsn = nil
  if state == "generated" then jsn = vim.json.decode(tool_use.input_json) end
  local msg = HistoryMessage:new({
    role = "assistant",
    content = {
      {
        type = "tool_use",
        name = tool_use.name,
        id = tool_use.id,
        input = jsn or {},
      },
    },
  }, {
    state = state,
    uuid = tool_use.uuid,
  })
  tool_use.uuid = msg.uuid
  tool_use.state = state
  if opts.on_messages_add then opts.on_messages_add({ msg }) end
end

function M:parse_response(ctx, data_stream, _, opts)
  if data_stream:match('"%[DONE%]":') then
    self:finish_pending_messages(ctx, opts)
    opts.on_stop({ reason = "complete" })
    return
  end
  if not data_stream:match('"delta":') then return end
  ---@type AvanteOpenAIChatResponse
  local jsn = vim.json.decode(data_stream)
  if not jsn.choices or not jsn.choices[1] then return end
  local choice = jsn.choices[1]
  if choice.delta.reasoning_content and choice.delta.reasoning_content ~= vim.NIL then
    if ctx.returned_think_start_tag == nil or not ctx.returned_think_start_tag then
      ctx.returned_think_start_tag = true
      if opts.on_chunk then opts.on_chunk("<think>\n") end
    end
    ctx.last_think_content = choice.delta.reasoning_content
    self:add_thinking_message(ctx, choice.delta.reasoning_content, "generating", opts)
    if opts.on_chunk then opts.on_chunk(choice.delta.reasoning_content) end
  elseif choice.delta.reasoning and choice.delta.reasoning ~= vim.NIL then
    if ctx.returned_think_start_tag == nil or not ctx.returned_think_start_tag then
      ctx.returned_think_start_tag = true
      if opts.on_chunk then opts.on_chunk("<think>\n") end
    end
    ctx.last_think_content = choice.delta.reasoning
    self:add_thinking_message(ctx, choice.delta.reasoning, "generating", opts)
    if opts.on_chunk then opts.on_chunk(choice.delta.reasoning) end
  elseif choice.delta.tool_calls and choice.delta.tool_calls ~= vim.NIL then
    local choice_index = choice.index or 0
    for idx, tool_call in ipairs(choice.delta.tool_calls) do
      --- In Gemini's so-called OpenAI Compatible API, tool_call.index is nil, which is quite absurd! Therefore, a compatibility fix is needed here.
      if tool_call.index == nil then tool_call.index = choice_index + idx - 1 end
      if not ctx.tool_use_list then ctx.tool_use_list = {} end
      if not ctx.tool_use_list[tool_call.index + 1] then
        if tool_call.index > 0 and ctx.tool_use_list[tool_call.index] then
          local prev_tool_use = ctx.tool_use_list[tool_call.index]
          self:add_tool_use_message(prev_tool_use, "generated", opts)
        end
        local tool_use = {
          name = tool_call["function"].name,
          id = tool_call.id,
          input_json = type(tool_call["function"].arguments) == "string" and tool_call["function"].arguments or "",
        }
        ctx.tool_use_list[tool_call.index + 1] = tool_use
        self:add_tool_use_message(tool_use, "generating", opts)
      else
        local tool_use = ctx.tool_use_list[tool_call.index + 1]
        tool_use.input_json = tool_use.input_json .. tool_call["function"].arguments
        self:add_tool_use_message(tool_use, "generating", opts)
      end
    end
  elseif choice.delta.content then
    if
      ctx.returned_think_start_tag ~= nil and (ctx.returned_think_end_tag == nil or not ctx.returned_think_end_tag)
    then
      ctx.returned_think_end_tag = true
      if opts.on_chunk then
        if ctx.last_think_content and ctx.last_think_content ~= vim.NIL and ctx.last_think_content:sub(-1) ~= "\n" then
          opts.on_chunk("\n</think>\n")
        else
          opts.on_chunk("</think>\n")
        end
      end
      self:add_thinking_message(ctx, "", "generated", opts)
    end
    if choice.delta.content ~= vim.NIL then
      if opts.on_chunk then opts.on_chunk(choice.delta.content) end
      self:add_text_message(ctx, choice.delta.content, "generating", opts)
    end
  end
  if choice.finish_reason == "stop" or choice.finish_reason == "eos_token" then
    self:finish_pending_messages(ctx, opts)
    opts.on_stop({ reason = "complete" })
  end
  if choice.finish_reason == "tool_calls" then
    self:finish_pending_messages(ctx, opts)
    opts.on_stop({
      reason = "tool_use",
      usage = jsn.usage,
    })
  end
end

function M:parse_response_without_stream(data, _, opts)
  ---@type AvanteOpenAIChatResponse
  local json = vim.json.decode(data)
  if json.choices and json.choices[1] then
    local choice = json.choices[1]
    if choice.message and choice.message.content then
      opts.on_chunk(choice.message.content)
      vim.schedule(function() opts.on_stop({ reason = "complete" }) end)
    end
  end
end

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = Providers.parse_config(self)
  local disable_tools = provider_conf.disable_tools or false

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if provider_conf.extra_headers then
    for key, value in pairs(provider_conf.extra_headers) do
      headers[key] = value
    end
  end

  if Providers.env.require_api_key(provider_conf) then
    local api_key = self.parse_api_key()
    if api_key == nil then
      error(Config.provider .. " API key is not set, please set it in your environment variable or config file")
    end
    headers["Authorization"] = "Bearer " .. api_key
  end

  if M.is_openrouter(provider_conf.endpoint) then
    headers["HTTP-Referer"] = "https://github.com/yetone/avante.nvim"
    headers["X-Title"] = "Avante.nvim"
    request_body.include_reasoning = true
  end

  self.set_allowed_params(provider_conf, request_body)

  local tools = nil
  if not disable_tools and prompt_opts.tools then
    tools = {}
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, self:transform_tool(tool))
    end
  end

  Utils.debug("endpoint", provider_conf.endpoint)
  Utils.debug("model", provider_conf.model)

  return {
    url = Utils.url_join(provider_conf.endpoint, "/chat/completions"),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = provider_conf.model,
      messages = self:parse_messages(prompt_opts),
      stream = true,
      tools = tools,
    }, request_body),
  }
end

return M
