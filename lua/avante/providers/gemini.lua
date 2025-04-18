local Utils = require("avante.utils")
local P = require("avante.providers")
local Clipboard = require("avante.clipboard")
---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "GEMINI_API_KEY"
M.role_map = {
  user = "user",
  assistant = "model",
}
-- M.tokenizer_id = "google/gemma-2b"

---@param tool AvanteLLMTool
---@return AvanteGeminiToolFunction
function M:transform_tool(tool)
  local input_schema_properties, required = Utils.llm_tool_param_fields_to_json_schema(tool.param.fields)
  ---@type AvanteGeminiToolFunctionParameters
  local parameters = nil
  if not vim.tbl_isempty(input_schema_properties) then
    parameters = {
      type = "object",
      properties = input_schema_properties,
      required = required,
    }
  end
  ---@type AvanteGeminiToolFunction
  local res = {
    name = tool.name,
    description = tool.get_description and tool.get_description() or tool.description,
    parameters = parameters,
  }
  return res
end

function M:is_disable_stream() return false end

function M:parse_messages(opts)
  local contents = {}
  local prev_role = nil

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
          role = "assistant"
          table.insert(parts, { functionCall = { name = item.name, id = item.id, args = item.input } })
        elseif type(item) == "table" and item.type == "tool_result" then
          role = "user"
          table.insert(parts, {
            functionResponse = {
              name = item.tool_name,
              id = item.tool_use_id,
              response = item.is_error and { error = item.content } or { result = item.content },
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
  if opts.tool_histories then
    for _, item in ipairs(opts.tool_histories) do
      if item.tool_use ~= nil then
        local parts = {}
        table.insert(parts, {
          functionCall = {
            name = item.tool_use.name,
            id = item.tool_use.id,
            args = vim.json.decode(item.tool_use.input_json or "{}"),
          },
        })
        table.insert(contents, {
          role = M.role_map["assistant"],
          parts = parts,
        })
      end
      if item.tool_result ~= nil then
        local parts = {}
        table.insert(parts, {
          functionResponse = {
            name = item.tool_result.tool_name,
            id = item.tool_result.tool_use_id,
            response = item.tool_result.is_error and { error = item.tool_result.content }
              or { result = item.tool_result.content },
          },
        })
        table.insert(contents, {
          role = M.role_map["user"],
          parts = parts,
        })
      end
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
  if json.candidates then
    local has_tool_use = false
    if #json.candidates > 0 then
      local candidate = json.candidates[1]
      for _, part in ipairs(candidate.content.parts) do
        if part.text then opts.on_chunk(part.text) end
        if part.functionCall then
          if not ctx.tool_use_list then ctx.tool_use_list = {} end
          local tool_use = {
            id = Utils.random_string(16),
            name = part.functionCall.name,
            input_json = vim.json.encode(part.functionCall.args),
          }
          table.insert(ctx.tool_use_list, tool_use)
          has_tool_use = true
        end
      end
      if candidate.finishReason then
        local reason = candidate.finishReason
        Utils.debug("Gemini: Finish Reason:", reason)
        if reason == "STOP" then
          if has_tool_use then
            opts.on_stop({ reason = "tool_use", tool_use_list = ctx.tool_use_list })
          else
            opts.on_stop({ reason = "complete" })
          end
        elseif reason == "MAX_TOKENS" then
          opts.on_stop({ reason = "error", error = "Gemini stream stopped due to MAX_TOKENS." })
        elseif reason == "SAFETY" then
          local safety_ratings = vim.inspect(candidate.safetyRatings)
          local error_msg = "Gemini API Error: Stopped due to SAFETY. Ratings: " .. safety_ratings
          Utils.error(error_msg)
          opts.on_stop({ reason = "error", error = error_msg })
        elseif reason == "RECITATION" then
          local error_msg = "Gemini API Error: Stopped due to RECITATION."
          Utils.error(error_msg)
          opts.on_stop({ reason = "error", error = error_msg })
        elseif reason == "TOOL_CODE_EXECUTING" or reason == "TOOL_CODE" or has_tool_use then -- Gemini might use TOOL_CODE_EXECUTING or just TOOL_CODE
          -- Stop because the model wants to use a tool
          opts.on_stop({ reason = "tool_use", tool_use_list = ctx.tool_use_list })
        else -- OTHER, UNSPECIFIED, etc.
          opts.on_stop({ reason = "error", error = "Gemini stream stopped with reason: " .. reason })
        end
      end
    else
      opts.on_stop({ reason = "complete" })
    end
  end
end

function M:parse_curl_args(prompt_opts)
  local provider_conf, request_body = P.parse_config(self)
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

  local tools = {}
  if not disable_tools and prompt_opts.tools then
    local functionDeclarations = {}
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(functionDeclarations, self:transform_tool(tool))
    end
    table.insert(tools, {
      functionDeclarations = functionDeclarations,
    })
  end
  request_body = vim.tbl_deep_extend("force", request_body, {
    tools = tools,
  })
  Utils.debug("endpoint", provider_conf.endpoint)
  Utils.debug("model", provider_conf.model)
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
