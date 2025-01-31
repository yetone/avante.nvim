local Utils = require("avante.utils")
local Config = require("avante.config")
local Clipboard = require("avante.clipboard")
local P = require("avante.providers")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "" -- Ollama typically doesn't require API keys for local use

---@param opts AvantePromptOptions
M.parse_messages = function(opts)
  local messages = {}
  local has_images = Config.behaviour.support_paste_from_clipboard and opts.image_paths and #opts.image_paths > 0

  -- Convert avante messages to ollama format
  for _, msg in ipairs(opts.messages) do
    local role = msg.role == "user" and "user" or "assistant"
    local content = msg.content

    -- Handle multimodal content if images are present
    if has_images and role == "user" then
      local message_content = {
        role = role,
        content = content,
        images = {},
      }

      for _, image_path in ipairs(opts.image_paths) do
        table.insert(message_content.images, "data:image/png;base64," .. Clipboard.get_base64_content(image_path))
      end

      table.insert(messages, message_content)
    else
      table.insert(messages, {
        role = role,
        content = content,
      })
    end
  end

  return messages
end

---@param data string
---@param handler_opts AvanteHandlerOptions
M.parse_stream_data = function(data, handler_opts)
  local ok, json_data = pcall(vim.json.decode, data)
  if not ok or not json_data then
    -- Add debug logging
    Utils.debug("Failed to parse JSON: " .. data)
    return
  end

  -- Add debug logging
  Utils.debug("Received data: " .. vim.inspect(json_data))

  if json_data.message and json_data.message.content then
    local content = json_data.message.content
    if content and content ~= "" then
      Utils.debug("Sending chunk: " .. content)
      handler_opts.on_chunk(content)
    end
  end

  if json_data.done then
    Utils.debug("Stream complete")
    handler_opts.on_complete(nil)
    return
  end
end

---@param provider AvanteProvider
---@param prompt_opts AvantePromptOptions
M.parse_curl_args = function(provider, prompt_opts)
  local base, body_opts = P.parse_config(provider)

  if not base.model or base.model == "" then error("Ollama model must be specified in config") end
  if not base.endpoint then error("Ollama requires endpoint configuration") end

  return {
    url = Utils.url_join(base.endpoint, "/api/chat"),
    headers = {
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json",
    },
    body = vim.tbl_deep_extend("force", {
      model = base.model,
      messages = M.parse_messages(prompt_opts),
      stream = true,
      system = prompt_opts.system_prompt,
    }, body_opts),
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

return M
