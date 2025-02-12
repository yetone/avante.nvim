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
---@field choices? OpenAIResponseChoice[] | OpenAIResponseChoiceComplete[]
---@field usage {prompt_tokens: integer, completion_tokens: integer, total_tokens: integer}
---
---@class OpenAIResponseChoice
---@field index integer
---@field delta OpenAIMessage
---@field logprobs? integer
---@field finish_reason? "stop" | "length"
---
---@class OpenAIResponseChoiceComplete
---@field message OpenAIMessage
---@field finish_reason "stop" | "length" | "eos_token"
---@field index integer
---@field logprobs integer
---
---@class OpenAIMessageToolCallFunction
---@field name string
---@field arguments string
---
---@class OpenAIMessageToolCall
---@field index integer
---@field id string
---@field type "function"
---@field function OpenAIMessageToolCallFunction
---
---@class OpenAIMessage
---@field role? "user" | "system" | "assistant"
---@field content? string
---@field reasoning_content? string
---@field reasoning? string
---@field tool_calls? OpenAIMessageToolCall[]
---
---@class AvanteOpenAITool
---@field type "function"
---@field function AvanteOpenAIToolFunction
---
---@class AvanteOpenAIToolFunction
---@field name string
---@field description string
---@field parameters AvanteOpenAIToolFunctionParameters
---@field strict boolean
---
---@class AvanteOpenAIToolFunctionParameters
---@field type string
---@field properties table<string, AvanteOpenAIToolFunctionParameterProperty>
---@field required string[]
---@field additionalProperties boolean
---
---@class AvanteOpenAIToolFunctionParameterProperty
---@field type string
---@field description string

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "OPENAI_API_KEY"

M.role_map = {
  user = "user",
  assistant = "assistant",
}

---@param tool AvanteLLMTool
---@return AvanteOpenAITool
function M.transform_tool(tool)
  local input_schema_properties = {}
  local required = {}
  for _, field in ipairs(tool.param.fields) do
    input_schema_properties[field.name] = {
      type = field.type,
      description = field.description,
    }
    if not field.optional then table.insert(required, field.name) end
  end
  local res = {
    type = "function",
    ["function"] = {
      name = tool.name,
      description = tool.description,
    },
  }
  if vim.tbl_count(input_schema_properties) > 0 then
    res["function"].parameters = {
      type = "object",
      properties = input_schema_properties,
      required = required,
      additionalProperties = false,
    }
  end
  return res
end

M.is_openrouter = function(url) return url:match("^https://openrouter%.ai/") end

---@param opts AvantePromptOptions
M.get_user_message = function(opts)
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

M.is_o_series_model = function(model) return model and string.match(model, "^o%d+") ~= nil end

M.parse_messages = function(opts)
  local messages = {}
  local provider = P[Config.provider]
  local base, _ = P.parse_config(provider)

  -- NOTE: Handle the case where the selected model is the `o1` model
  -- "o1" models are "smart" enough to understand user prompt as a system prompt in this context
  if M.is_o_series_model(base.model) then
    table.insert(messages, { role = "user", content = opts.system_prompt })
  else
    table.insert(messages, { role = "system", content = opts.system_prompt })
  end

  vim
    .iter(opts.messages)
    :each(function(msg) table.insert(messages, { role = M.role_map[msg.role], content = msg.content }) end)

  if Config.behaviour.support_paste_from_clipboard and opts.image_paths and #opts.image_paths > 0 then
    local message_content = messages[#messages].content
    if type(message_content) ~= "table" then message_content = { type = "text", text = message_content } end
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
    if role == prev_role then
      if role == M.role_map["user"] then
        table.insert(final_messages, { role = M.role_map["assistant"], content = "Ok, I understand." })
      else
        table.insert(final_messages, { role = M.role_map["user"], content = "Ok" })
      end
    end
    prev_role = role
    table.insert(final_messages, { role = M.role_map[role] or role, content = message.content })
  end)

  if opts.tool_histories then
    for _, tool_history in ipairs(opts.tool_histories) do
      table.insert(final_messages, {
        role = M.role_map["assistant"],
        tool_calls = {
          {
            id = tool_history.tool_use.id,
            type = "function",
            ["function"] = {
              name = tool_history.tool_use.name,
              arguments = tool_history.tool_use.input_json,
            },
          },
        },
      })
      local result_content = tool_history.tool_result.content or ""
      table.insert(final_messages, {
        role = "tool",
        tool_call_id = tool_history.tool_result.tool_use_id,
        content = tool_history.tool_result.is_error and "Error: " .. result_content or result_content,
      })
    end
  end

  return final_messages
end

M.parse_response = function(ctx, data_stream, _, opts)
  if data_stream:match('"%[DONE%]":') then
    opts.on_stop({ reason = "complete" })
    return
  end
  if data_stream:match('"delta":') then
    ---@type OpenAIChatResponse
    local jsn = vim.json.decode(data_stream)
    if jsn.choices and jsn.choices[1] then
      local choice = jsn.choices[1]
      if choice.finish_reason == "stop" or choice.finish_reason == "eos_token" then
        opts.on_stop({ reason = "complete" })
      elseif choice.finish_reason == "tool_calls" then
        opts.on_stop({
          reason = "tool_use",
          usage = jsn.usage,
          tool_use_list = ctx.tool_use_list,
        })
      elseif choice.delta.reasoning_content and choice.delta.reasoning_content ~= vim.NIL then
        if ctx.returned_think_start_tag == nil or not ctx.returned_think_start_tag then
          ctx.returned_think_start_tag = true
          opts.on_chunk("<think>\n")
        end
        ctx.last_think_content = choice.delta.reasoning_content
        opts.on_chunk(choice.delta.reasoning_content)
      elseif choice.delta.reasoning and choice.delta.reasoning ~= vim.NIL then
        if ctx.returned_think_start_tag == nil or not ctx.returned_think_start_tag then
          ctx.returned_think_start_tag = true
          opts.on_chunk("<think>\n")
        end
        ctx.last_think_content = choice.delta.reasoning
        opts.on_chunk(choice.delta.reasoning)
      elseif choice.delta.tool_calls then
        local tool_call = choice.delta.tool_calls[1]
        if not ctx.tool_use_list then ctx.tool_use_list = {} end
        if not ctx.tool_use_list[tool_call.index + 1] then
          local tool_use = {
            name = tool_call["function"].name,
            id = tool_call.id,
            input_json = "",
          }
          ctx.tool_use_list[tool_call.index + 1] = tool_use
        else
          local tool_use = ctx.tool_use_list[tool_call.index + 1]
          tool_use.input_json = tool_use.input_json .. tool_call["function"].arguments
        end
      elseif choice.delta.content then
        if
          ctx.returned_think_start_tag ~= nil and (ctx.returned_think_end_tag == nil or not ctx.returned_think_end_tag)
        then
          ctx.returned_think_end_tag = true
          if
            ctx.last_think_content
            and ctx.last_think_content ~= vim.NIL
            and ctx.last_think_content:sub(-1) ~= "\n"
          then
            opts.on_chunk("\n</think>\n")
          else
            opts.on_chunk("</think>\n")
          end
        end
        if choice.delta.content ~= vim.NIL then opts.on_chunk(choice.delta.content) end
      end
    end
  end
end

M.parse_response_without_stream = function(data, _, opts)
  ---@type OpenAIChatResponse
  local json = vim.json.decode(data)
  if json.choices and json.choices[1] then
    local choice = json.choices[1]
    if choice.message and choice.message.content then
      opts.on_chunk(choice.message.content)
      vim.schedule(function() opts.on_stop({ reason = "complete" }) end)
    end
  end
end

M.parse_curl_args = function(provider, prompt_opts)
  local provider_conf, request_body = P.parse_config(provider)
  local disable_tools = provider_conf.disable_tools or false

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if P.env.require_api_key(provider_conf) then
    local api_key = provider.parse_api_key()
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

  -- NOTE: When using "o" series set the supported parameters only
  local stream = true
  if M.is_o_series_model(provider_conf.model) then
    request_body.max_completion_tokens = request_body.max_tokens
    request_body.max_tokens = nil
    request_body.temperature = 1
  end

  local tools = nil
  if not disable_tools and prompt_opts.tools then
    tools = {}
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, M.transform_tool(tool))
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
      messages = M.parse_messages(prompt_opts),
      stream = stream,
      tools = tools,
    }, request_body),
  }
end

return M
