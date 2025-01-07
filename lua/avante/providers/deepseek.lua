-- New file for DeepSeek provider implementation

local Utils = require("avante.utils")
local P = require("avante.providers")

---@class AvanteProviderFunctor
local M = {}

M.api_key_name = "DEEPSEEK_API_KEY"
M.role_map = {
  user = "user",
  assistant = "assistant",
}

-- Helper function to determine if content is code-related
local function is_code_context(content)
  -- Early returns for edge cases
  if not content or content:match("^%s*$") then return false end

  -- Common programming patterns that should immediately identify as code
  local immediate_code_patterns = {
    "^%s*print%s*%b()", -- Matches print('hello') with any content in parentheses
    "^%s*[%w_]+%s*%b()", -- Any function call pattern
    "^%s*[%w_]+%.[%w_]+%s*%b()", -- Method calls like console.log()
  }

  for _, pattern in ipairs(immediate_code_patterns) do
    if content:match(pattern) then
      Utils.debug("DeepSeek: Detected code pattern:", pattern, "in:", content)
      return true
    end
  end

  -- Enhanced code patterns
  local code_patterns = {
    -- Existing patterns...
    "^%s*[%w_]+%s+[%w_]+%s*%(", -- Function definition
    "^%s*class%s+[%w_]+", -- Class definition
    "^%s*import%s+", -- Import statement

    -- New patterns for edge cases
    "[%w_]+%s*=%s*[%w%p]", -- Variable assignment
    "^%s*print%s*%(.*%)", -- Print statements
    "^%s*console%.", -- Console methods
    "%s*<%/?[%w_]+>", -- HTML tags
    "^%s*@[%w_]+", -- Decorators
    "^%s*#include", -- C/C++ includes
    "^%s*package%s+", -- Java/Kotlin packages
    "^%s*using%s+", -- C# using statements
    "^%s*module%s+", -- Node.js modules
    "^%s*require%s*[%(%'\"]", -- Require statements
    "^%s*export%s+", -- Export statements
    "%{%s*[%w_]+%s*:%s*[%w%p]", -- Object literals
    "^%s*async%s+", -- Async functions
    "^%s*await%s+", -- Await statements
    "^%s*try%s*{", -- Try blocks
    "^%s*catch%s*%(", -- Catch blocks
    "^%s*finally%s*{", -- Finally blocks
    "^%s*throw%s+", -- Throw statements
    "^%s*yield%s+", -- Generator functions
  }

  -- Check for code blocks in markdown
  if content:match("```[%w_]*[^`]*```") then return true end

  -- Check for single backtick code that spans the whole line
  if content:match("^%s*`[^`]+`%s*$") then return true end

  for _, pattern in ipairs(code_patterns) do
    if content:match(pattern) then return true end
  end

  -- Check for high concentration of programming symbols
  local symbol_count = 0
  for _ in content:gmatch("[{}%[%]%(%)%+%-%*/%=<>!&|;:]") do
    symbol_count = symbol_count + 1
  end

  -- If more than 15% of content is programming symbols, likely code
  if symbol_count > 0 and symbol_count / #content > 0.15 then return true end

  return false
end

-- Support both chat and coder models with dynamic switching
M.parse_messages = function(opts)
  Utils.debug("DeepSeek: Parsing messages with opts:", vim.inspect(opts))
  local messages = {
    { role = "system", content = opts.system_prompt },
  }

  -- Analyze content to determine model type
  local is_coding = false
  -- Only check the last message for model switching
  if #opts.messages > 0 then
    local last_message = opts.messages[#opts.messages]
    is_coding = is_code_context(last_message.content)
  end

  vim.iter(opts.messages):each(
    function(msg)
      table.insert(messages, {
        role = M.role_map[msg.role],
        content = msg.content,
      })
    end
  )

  -- Set model based on last message content
  opts.model = is_coding and "deepseek-coder" or "deepseek-chat"

  Utils.debug("DeepSeek: Switching to model:", opts.model)

  return messages
end

-- Error handling for DeepSeek-specific errors
M.on_error = function(result)
  if not result.body then
    return Utils.error("API request failed with status " .. result.status, { once = true, title = "Avante" })
  end

  local ok, body = pcall(vim.json.decode, result.body)
  if not (ok and body and body.error) then
    return Utils.error("Failed to parse error response", { once = true, title = "Avante" })
  end

  local error_msg = body.error.message
  local error_code = body.error.code or result.status

  -- DeepSeek-specific error handling
  local error_types = {
    [400] = "Invalid request format",
    [401] = "Authentication failed",
    [402] = "Insufficient balance",
    [422] = "Invalid parameters",
    [429] = "Rate limit exceeded",
    [500] = "Server error",
    [503] = "Service temporarily unavailable",
  }

  local error_type = error_types[error_code] or "Unknown error"
  Utils.error(string.format("%s: %s", error_type, error_msg), { once = true, title = "Avante" })
end

M.parse_response = function(data_stream, _, opts)
  if data_stream:match('"%[DONE%]":') then
    opts.on_complete(nil)
    return
  end

  local ok, json = pcall(vim.json.decode, data_stream)
  if not ok then
    opts.on_complete("Failed to parse response: " .. data_stream)
    return
  end

  if json.choices and json.choices[1] then
    local choice = json.choices[1]
    if choice.finish_reason == "stop" or choice.finish_reason == "length" then
      opts.on_complete(nil)
    elseif choice.delta and choice.delta.content then
      opts.on_chunk(choice.delta.content)
    end
  end
end

M.parse_curl_args = function(provider, code_opts)
  Utils.debug("DeepSeek: Preparing curl args with opts:", vim.inspect(code_opts))
  local base, body_opts = P.parse_config(provider)

  -- Validate API key
  local api_key = provider.parse_api_key()
  if not api_key then error("DeepSeek API key not found. Please set DEEPSEEK_API_KEY environment variable.") end

  -- Use dynamically determined model from parse_messages
  local model = code_opts.model or base.model or "deepseek-chat"
  local endpoint = "/chat/completions"

  Utils.debug("DeepSeek: Using model:", model)

  local url = Utils.url_join(base.endpoint, endpoint)
  local messages = M.parse_messages(code_opts)

  Utils.debug(
    "DeepSeek: Final curl args:",
    vim.inspect({
      url = url,
      model = model,
      messages_count = #messages,
    })
  )

  return {
    url = url,
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key,
    },
    body = vim.tbl_deep_extend("force", {
      model = model,
      messages = messages,
      stream = true,
      max_tokens = base.max_tokens or 8000,
      temperature = base.temperature or 0,
    }, body_opts),
  }
end

return M
