local Utils = require("avante.utils")
local Providers = require("avante.providers")
local Clipboard = require("avante.clipboard")
local OpenAI = require("avante.providers").openai

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "GEMINI_API_KEY"
M.role_map = {
  user = "user",
  assistant = "model",
}

function M:is_disable_stream() return false end

---@param tool AvanteLLMTool
function M:transform_to_function_declaration(tool)
  local input_schema_properties, required = Utils.llm_tool_param_fields_to_json_schema(tool.param.fields)
  local parameters = nil
  if not vim.tbl_isempty(input_schema_properties) then
    parameters = {
      type = "object",
      properties = input_schema_properties,
      required = required,
    }
  end
  return {
    name = tool.name,
    description = tool.get_description and tool.get_description() or tool.description,
    parameters = parameters,
  }
end

function M:parse_messages(opts)
  local contents = {}
  local prev_role = nil

  local tool_id_to_name = {}
  vim.iter(opts.messages):each(function(message)
    local role = message.role
    if role == prev_role then
      if role == M.role_map["user"] then
        table.insert(
          contents,
          { role = M.role_map["assistant"], parts = {
            { text = "Ok, I understand." },
          } }
        )
      else
        table.insert(contents, { role = M.role_map["user"], parts = {
          { text = "Ok" },
        } })
      end
    end
    prev_role = role
    local parts = {}
    local content_items = message.content
    if type(content_items) == "string" then
      table.insert(parts, { text = content_items })
    elseif type(content_items) == "table" then
      ---@cast content_items AvanteLLMMessageContentItem[]
      for _, item in ipairs(content_items) do
        if type(item) == "string" then
          table.insert(parts, { text = item })
        elseif type(item) == "table" and item.type == "text" then
          table.insert(parts, { text = item.text })
        elseif type(item) == "table" and item.type == "image" then
          table.insert(parts, {
            inline_data = {
              mime_type = "image/png",
              data = item.source.data,
            },
          })
        elseif type(item) == "table" and item.type == "tool_use" then
          tool_id_to_name[item.id] = item.name
          role = "model"
          table.insert(parts, {
            functionCall = {
              name = item.name,
              args = item.input,
            },
          })
        elseif type(item) == "table" and item.type == "tool_result" then
          role = "function"
          local ok, content = pcall(vim.json.decode, item.content)
          if not ok then content = item.content end
          table.insert(parts, {
            functionResponse = {
              name = tool_id_to_name[item.tool_use_id],
              response = {
                name = tool_id_to_name[item.tool_use_id],
                content = content,
              },
            },
          })
        elseif type(item) == "table" and item.type == "thinking" then
          table.insert(parts, { text = item.thinking })
        elseif type(item) == "table" and item.type == "redacted_thinking" then
          table.insert(parts, { text = item.data })
        end
      end
    end
    table.insert(contents, { role = M.role_map[role] or role, parts = parts })
  end)

  if Clipboard.support_paste_image() and opts.image_paths then
    for _, image_path in ipairs(opts.image_paths) do
      local image_data = {
        inline_data = {
          mime_type = "image/png",
          data = Clipboard.get_base64_content(image_path),
        },
      }

      table.insert(contents[#contents].parts, image_data)
    end
  end

  return {
    systemInstruction = {
      role = "user",
      parts = {
        {
          text = opts.system_prompt,
        },
      },
    },
    contents = contents,
  }
end

function M:parse_response(ctx, data_stream, _, opts)
  local ok, json = pcall(vim.json.decode, data_stream)
  if not ok then opts.on_stop({ reason = "error", error = json }) end
  if json.candidates and #json.candidates > 0 then
    local candidate = json.candidates[1]
    ---@type AvanteLLMToolUse[]
    local tool_use_list = {}
    if candidate.content.parts ~= nil then
      for _, part in ipairs(candidate.content.parts) do
        if part.text then
          if opts.on_chunk then opts.on_chunk(part.text) end
          OpenAI:add_text_message(ctx, part.text, "generating", opts)
        elseif part.functionCall then
          if not ctx.function_call_id then ctx.function_call_id = 0 end
          ctx.function_call_id = ctx.function_call_id + 1
          local tool_use = {
            id = ctx.session_id .. "-" .. tostring(ctx.function_call_id),
            name = part.functionCall.name,
            input_json = vim.json.encode(part.functionCall.args),
          }
          table.insert(tool_use_list, tool_use)
          OpenAI:add_tool_use_message(tool_use, "generated", opts)
        end
      end
    end
    if candidate.finishReason and candidate.finishReason == "STOP" then
      OpenAI:finish_pending_messages(ctx, opts)
      if #tool_use_list > 0 then
        opts.on_stop({ reason = "tool_use", tool_use_list = tool_use_list })
      else
        opts.on_stop({ reason = "complete" })
      end
    end
  else
    OpenAI:finish_pending_messages(ctx, opts)
    opts.on_stop({ reason = "complete" })
  end
end

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = Providers.parse_config(self)
  local disable_tools = provider_conf.disable_tools or false

  request_body = vim.tbl_deep_extend("force", request_body, {
    generationConfig = {
      temperature = request_body.temperature,
      maxOutputTokens = request_body.max_tokens,
    },
  })
  request_body.temperature = nil
  request_body.max_tokens = nil

  local api_key = self.parse_api_key()
  if api_key == nil then error("Cannot get the gemini api key!") end

  local function_declarations = {}
  if not disable_tools and prompt_opts.tools then
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(function_declarations, self:transform_to_function_declaration(tool))
    end
  end

  if #function_declarations > 0 then
    request_body.tools = {
      {
        functionDeclarations = function_declarations,
      },
    }
  end

  return {
    url = Utils.url_join(
      provider_conf.endpoint,
      provider_conf.model .. ":streamGenerateContent?alt=sse&key=" .. api_key
    ),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = { ["Content-Type"] = "application/json" },
    body = vim.tbl_deep_extend("force", {}, self:parse_messages(prompt_opts), request_body),
  }
end

return M
