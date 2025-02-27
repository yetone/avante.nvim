local Utils = require("avante.utils")
local Clipboard = require("avante.clipboard")
local P = require("avante.providers")

---@param tool AvanteLLMTool
---@return AvanteClaudeTool
local function transform_tool(tool)
  local input_schema_properties = {}
  local required = {}
  for _, field in ipairs(tool.param.fields) do
    input_schema_properties[field.name] = {
      type = field.type,
      description = field.description,
    }
    if not field.optional then table.insert(required, field.name) end
  end
  return {
    name = tool.name,
    description = tool.description,
    input_schema = {
      type = "object",
      properties = input_schema_properties,
      required = required,
    },
  }
end

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "ANTHROPIC_API_KEY"
M.use_xml_format = true

M.role_map = {
  user = "user",
  assistant = "assistant",
}

function M.parse_messages(opts)
  ---@type AvanteClaudeMessage[]
  local messages = {}

  ---@type {idx: integer, length: integer}[]
  local messages_with_length = {}
  for idx, message in ipairs(opts.messages) do
    table.insert(messages_with_length, { idx = idx, length = Utils.tokens.calculate_tokens(message.content) })
  end

  table.sort(messages_with_length, function(a, b) return a.length > b.length end)

  ---@type table<integer, boolean>
  local top_three = {}
  for i = 1, math.min(3, #messages_with_length) do
    top_three[messages_with_length[i].idx] = true
  end

  for idx, message in ipairs(opts.messages) do
    table.insert(messages, {
      role = M.role_map[message.role],
      content = {
        {
          type = "text",
          text = message.content,
          cache_control = top_three[idx] and { type = "ephemeral" } or nil,
        },
      },
    })
  end

  if Clipboard.support_paste_image() and opts.image_paths and #opts.image_paths > 0 then
    local message_content = messages[#messages].content
    for _, image_path in ipairs(opts.image_paths) do
      table.insert(message_content, {
        type = "image",
        source = {
          type = "base64",
          media_type = "image/png",
          data = Clipboard.get_base64_content(image_path),
        },
      })
    end
    messages[#messages].content = message_content
  end

  if opts.tool_histories then
    for _, tool_history in ipairs(opts.tool_histories) do
      if tool_history.tool_use then
        local msg = {
          role = "assistant",
          content = {},
        }
        if tool_history.tool_use.thinking_contents then
          for _, thinking_content in ipairs(tool_history.tool_use.thinking_contents) do
            msg.content[#msg.content + 1] = {
              type = "thinking",
              thinking = thinking_content.content,
              signature = thinking_content.signature,
            }
          end
        end
        if tool_history.tool_use.response_contents then
          for _, response_content in ipairs(tool_history.tool_use.response_contents) do
            msg.content[#msg.content + 1] = {
              type = "text",
              text = response_content,
            }
          end
        end
        msg.content[#msg.content + 1] = {
          type = "tool_use",
          id = tool_history.tool_use.id,
          name = tool_history.tool_use.name,
          input = vim.json.decode(tool_history.tool_use.input_json),
        }
        messages[#messages + 1] = msg
      end

      if tool_history.tool_result then
        messages[#messages + 1] = {
          role = "user",
          content = {
            {
              type = "tool_result",
              tool_use_id = tool_history.tool_result.tool_use_id,
              content = tool_history.tool_result.content,
              is_error = tool_history.tool_result.is_error,
            },
          },
        }
      end
    end
  end

  return messages
end

function M.parse_response(ctx, data_stream, event_state, opts)
  if event_state == nil then
    if data_stream:match('"message_start"') then
      event_state = "message_start"
    elseif data_stream:match('"message_delta"') then
      event_state = "message_delta"
    elseif data_stream:match('"message_stop"') then
      event_state = "message_stop"
    elseif data_stream:match('"content_block_start"') then
      event_state = "content_block_start"
    elseif data_stream:match('"content_block_delta"') then
      event_state = "content_block_delta"
    elseif data_stream:match('"content_block_stop"') then
      event_state = "content_block_stop"
    end
  end
  if ctx.content_blocks == nil then ctx.content_blocks = {} end
  if event_state == "message_start" then
    local ok, jsn = pcall(vim.json.decode, data_stream)
    if not ok then return end
    opts.on_start(jsn.message.usage)
  elseif event_state == "content_block_start" then
    local ok, jsn = pcall(vim.json.decode, data_stream)
    if not ok then return end
    local content_block = jsn.content_block
    content_block.stoppped = false
    ctx.content_blocks[jsn.index + 1] = content_block
    if content_block.type == "thinking" then opts.on_chunk("<think>\n") end
  elseif event_state == "content_block_delta" then
    local ok, jsn = pcall(vim.json.decode, data_stream)
    if not ok then return end
    local content_block = ctx.content_blocks[jsn.index + 1]
    if jsn.delta.type == "input_json_delta" then
      if not content_block.input_json then content_block.input_json = "" end
      content_block.input_json = content_block.input_json .. jsn.delta.partial_json
      return
    elseif jsn.delta.type == "thinking_delta" then
      content_block.thinking = content_block.thinking .. jsn.delta.thinking
      opts.on_chunk(jsn.delta.thinking)
    elseif jsn.delta.type == "text_delta" then
      content_block.text = content_block.text .. jsn.delta.text
      opts.on_chunk(jsn.delta.text)
    elseif jsn.delta.type == "signature_delta" then
      if ctx.content_blocks[jsn.index + 1].signature == nil then ctx.content_blocks[jsn.index + 1].signature = "" end
      ctx.content_blocks[jsn.index + 1].signature = ctx.content_blocks[jsn.index + 1].signature .. jsn.delta.signature
    end
  elseif event_state == "content_block_stop" then
    local ok, jsn = pcall(vim.json.decode, data_stream)
    if not ok then return end
    local content_block = ctx.content_blocks[jsn.index + 1]
    content_block.stoppped = true
    if content_block.type == "thinking" then
      if content_block.thinking and content_block.thinking ~= vim.NIL and content_block.thinking:sub(-1) ~= "\n" then
        opts.on_chunk("\n</think>\n\n")
      else
        opts.on_chunk("</think>\n\n")
      end
    end
  elseif event_state == "message_delta" then
    local ok, jsn = pcall(vim.json.decode, data_stream)
    if not ok then return end
    if jsn.delta.stop_reason == "end_turn" then
      opts.on_stop({ reason = "complete", usage = jsn.usage })
    elseif jsn.delta.stop_reason == "tool_use" then
      ---@type AvanteLLMToolUse[]
      local tool_use_list = vim
        .iter(ctx.content_blocks)
        :filter(function(content_block) return content_block.stoppped and content_block.type == "tool_use" end)
        :map(function(content_block)
          local response_contents = vim
            .iter(ctx.content_blocks)
            :filter(function(content_block_) return content_block_.stoppped and content_block_.type == "text" end)
            :map(function(content_block_) return content_block_.text end)
            :totable()
          local thinking_contents = vim
            .iter(ctx.content_blocks)
            :filter(function(content_block_) return content_block_.stoppped and content_block_.type == "thinking" end)
            :map(
              function(content_block_)
                return { content = content_block_.thinking, signature = content_block_.signature }
              end
            )
            :totable()
          return {
            name = content_block.name,
            id = content_block.id,
            input_json = content_block.input_json,
            response_contents = response_contents,
            thinking_contents = thinking_contents,
          }
        end)
        :totable()
      opts.on_stop({
        reason = "tool_use",
        usage = jsn.usage,
        tool_use_list = tool_use_list,
      })
    end
    return
  elseif event_state == "error" then
    opts.on_stop({ reason = "error", error = vim.json.decode(data_stream) })
  end
end

---@param provider AvanteProviderFunctor
---@param prompt_opts AvantePromptOptions
---@return table
function M.parse_curl_args(provider, prompt_opts)
  local provider_conf, request_body = P.parse_config(provider)
  local disable_tools = provider_conf.disable_tools or false

  local headers = {
    ["Content-Type"] = "application/json",
    ["anthropic-version"] = "2023-06-01",
    ["anthropic-beta"] = "prompt-caching-2024-07-31",
  }

  if P.env.require_api_key(provider_conf) then headers["x-api-key"] = provider.parse_api_key() end

  local messages = M.parse_messages(prompt_opts)

  local tools = {}
  if not disable_tools and prompt_opts.tools then
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, transform_tool(tool))
    end
  end

  return {
    url = Utils.url_join(provider_conf.endpoint, "/v1/messages"),
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = provider_conf.model,
      system = {
        {
          type = "text",
          text = prompt_opts.system_prompt,
          cache_control = { type = "ephemeral" },
        },
      },
      messages = messages,
      tools = tools,
      stream = true,
    }, request_body),
  }
end

function M.on_error(result)
  if result.status == 429 then return end
  if not result.body then
    return Utils.error("API request failed with status " .. result.status, { once = true, title = "Avante" })
  end

  local ok, body = pcall(vim.json.decode, result.body)
  if not (ok and body and body.error) then
    return Utils.error("Failed to parse error response", { once = true, title = "Avante" })
  end

  local error_msg = body.error.message
  local error_type = body.error.type

  if error_type == "insufficient_quota" then
    error_msg = "You don't have any credits or have exceeded your quota. Please check your plan and billing details."
  elseif error_type == "invalid_request_error" and error_msg:match("temperature") then
    error_msg = "Invalid temperature value. Please ensure it's between 0 and 1."
  end

  Utils.error(error_msg, { once = true, title = "Avante" })
end

return M
