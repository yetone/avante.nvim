local Utils = require("avante.utils")
local Config = require("avante.config")
local Clipboard = require("avante.clipboard")
local P = require("avante.providers")

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
end

function M:parse_messages(opts)
  local messages = {}
  local provider_conf, _ = P.parse_config(self)

  if self.is_reasoning_model(provider_conf.model) then
    table.insert(messages, { role = "developer", content = opts.system_prompt })
  else
    table.insert(messages, { role = "system", content = opts.system_prompt })
  end

  local has_tool_use = false

  vim.iter(opts.messages):each(function(msg)
    if type(msg.content) == "string" then
      table.insert(messages, { role = self.role_map[msg.role], content = msg.content })
    else
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
          table.insert(messages, { role = self.role_map["assistant"], tool_calls = tool_calls })
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
      if role == self.role_map["assistant"] then
        table.insert(final_messages, { role = self.role_map["user"], content = "Ok" })
      else
        table.insert(final_messages, { role = self.role_map["assistant"], content = "Ok, I understand." })
      end
    end
    prev_role = role
    table.insert(final_messages, message)
  end)

  if opts.tool_histories then
    for _, tool_history in ipairs(opts.tool_histories) do
      table.insert(final_messages, {
        role = self.role_map["assistant"],
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

function M:parse_response(ctx, data_stream, _, opts)
  if data_stream:match('"%[DONE%]":') then
    opts.on_stop({ reason = "complete" })
    return
  end
  if data_stream:match('"delta":') then
    ---@type AvanteOpenAIChatResponse
    local jsn = vim.json.decode(data_stream)
    if jsn.choices and jsn.choices[1] then
      local choice = jsn.choices[1]
      if choice.finish_reason == "stop" or choice.finish_reason == "eos_token" then
        if choice.delta.content and choice.delta.content ~= vim.NIL then opts.on_chunk(choice.delta.content) end
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
      elseif choice.delta.tool_calls and choice.delta.tool_calls ~= vim.NIL then
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
  local provider_conf, request_body = P.parse_config(self)
  local disable_tools = provider_conf.disable_tools or false

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if provider_conf.extra_headers then
    for key, value in pairs(provider_conf.extra_headers) do
      headers[key] = value
    end
  end

  if P.env.require_api_key(provider_conf) then
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
