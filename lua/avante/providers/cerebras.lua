local OpenAI = require("avante.providers").openai

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "CEREBRAS_API_KEY"
M.tokenizer_id = "gpt-4o"
M.role_map = {
  user = "user",
  assistant = "assistant",
}

function M:is_disable_stream() return false end

setmetatable(M, { __index = OpenAI })

---Override parse_messages to rename reasoning_content to reasoning in outgoing messages
function M:parse_messages(opts)
  local messages = OpenAI.parse_messages(self, opts)

  -- Deep function to rename reasoning_content to reasoning in all message types
  local function rename_reasoning_content_to_reasoning(obj)
    if type(obj) ~= "table" then return obj end

    -- Check if this is an array (sequential numeric keys)
    local is_array = true
    local max_index = 0
    for key, _ in pairs(obj) do
      if type(key) ~= "number" or key <= 0 or math.floor(key) ~= key then
        is_array = false
        break
      end
      max_index = math.max(max_index, key)
    end

    -- Check if the array is dense (no gaps)
    if is_array and max_index > 0 then
      for i = 1, max_index do
        if obj[i] == nil then
          is_array = false
          break
        end
      end
    end

    -- If it's an array, process each element but keep the array structure
    if is_array and max_index > 0 then
      local result = {}
      for i = 1, max_index do
        result[i] = rename_reasoning_content_to_reasoning(obj[i])
      end
      return result
    end

    -- If it's an object, rename keys and process values
    local result = {}
    for key, value in pairs(obj) do
      -- Rename reasoning_content to reasoning
      if key == "reasoning_content" then
        result["reasoning"] = rename_reasoning_content_to_reasoning(value)
      else
        result[key] = rename_reasoning_content_to_reasoning(value)
      end
    end

    return result
  end

  -- Process all messages
  local processed_messages = {}
  for _, msg in ipairs(messages) do
    table.insert(processed_messages, rename_reasoning_content_to_reasoning(msg))
  end

  return processed_messages
end

---Override parse_response to rename reasoning to reasoning_content in incoming messages
function M:parse_response(ctx, data_stream, chunk_content, opts)
  -- First rename reasoning to reasoning_content in the incoming data_stream
  local function rename_reasoning_to_reasoning_content(str)
    -- Handle JSON field renaming for streaming responses
    return str:gsub('"reasoning"%s*:%s*', '"reasoning_content":')
  end

  local processed_stream = rename_reasoning_to_reasoning_content(data_stream)

  -- Call parent parse_response with the processed stream
  return OpenAI.parse_response(self, ctx, processed_stream, chunk_content, opts)
end

---Override parse_response_without_stream to handle reasoning field renaming
function M:parse_response_without_stream(data, chunk_content, opts)
  -- Rename reasoning to reasoning_content in the response
  local function rename_reasoning_to_reasoning_content(obj)
    if type(obj) ~= "table" then return obj end

    local result = {}
    for key, value in pairs(obj) do
      -- Rename reasoning to reasoning_content
      if key == "reasoning" then
        result["reasoning_content"] = rename_reasoning_to_reasoning_content(value)
      else
        result[key] = rename_reasoning_to_reasoning_content(value)
      end
    end

    return result
  end

  -- Parse the JSON response
  local ok, json = pcall(vim.json.decode, data)
  if not ok then
    -- If parsing fails, try calling parent method directly
    return OpenAI.parse_response_without_stream(self, data, chunk_content, opts)
  end

  -- Rename reasoning to reasoning_content in the parsed JSON
  local processed_json = rename_reasoning_to_reasoning_content(json)

  -- Encode back to JSON and call parent method
  local processed_data = vim.json.encode(processed_json)
  return OpenAI.parse_response_without_stream(self, processed_data, chunk_content, opts)
end

return M
