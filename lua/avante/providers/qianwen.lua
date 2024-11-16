local Utils = require("avante.utils")
local Config = require("avante.config")
local Clipboard = require("avante.clipboard")
local P = require("avante.providers")

---@class QianwenChatResponse
---@field id string
---@field object "chat.completion" | "chat.completion.chunk"
---@field created integer
---@field model string
---@field system_fingerprint string?
---@field choices QianwenResponseChoice[] | QianwenResponseChoiceStream[]
---@field usage {prompt_tokens: integer, completion_tokens: integer, total_tokens: integer}

---@class QianwenResponseChoice
---@field message QianwenMessage
---@field finish_reason "stop" | "length"
---@field index integer
---@field logprobs any

---@class QianwenResponseChoiceStream
---@field delta QianwenMessage
---@field finish_reason? "stop" | "length"| "eos_token"
---@field index integer
---@field logprobs any

---@class QianwenMessage
---@field role? "user" | "system" | "assistant"
---@field content string

---@class QianwenProviderFunctor
local M = {}

M.api_key_name = "DASHSCOPE_API_KEY"

M.role_map = {
  user = "user",
  assistant = "assistant",
}

-- 解析消息
M.parse_messages = function(opts)
  local messages = {}

  -- 添加系统提示 (Add system prompt)
  table.insert(messages, { role = "system", content = opts.system_prompt })

  -- 添加对话消息 (Add conversation messages)
  vim.iter(opts.messages):each(
    function(msg)
      table.insert(messages, {
        role = M.role_map[msg.role],
        content = msg.content,
      })
    end
  )

  return messages
end

-- 添加文件路径配置 (Add file path configuration)
local log_file = vim.fn.stdpath("cache") .. "/qianwen_chat.log"

-- 确保日志目录存在 (Ensure log directory exists)
local function ensure_log_dir()
  local dir = vim.fn.fnamemodify(log_file, ":h")
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
end

-- 写入日志文件 (Write to log file)
---@param data string 要写入的数据 (Data to be written)
---@param append? boolean 是否追加模式 (Append mode)
local function write_log(data, append)
  ensure_log_dir()
  local mode = append and "a" or "w"
  local file = io.open(log_file, mode)
  if file then
    file:write(data .. "\n")
    file:close()
  end
end

-- 解析流式响应 (Parse streaming response)
M.parse_response = function(data_stream, _, opts)
  write_log(string.format("[%s] Raw data: %s", os.date("%Y-%m-%d %H:%M:%S"), data_stream), true)

  if string.match(data_stream, ".*%[DONE%].*") then
    opts.on_complete(nil)
    return
  end

  ---@type QianwenChatResponse
  local json = vim.json.decode(data_stream)
  if json.choices and json.choices[1] then
    local choice = json.choices[1]
    if choice.finish_reason == "stop" or choice.finish_reason == "eos_token" then
      opts.on_complete(nil)
    elseif choice.delta and choice.delta.content then
      if choice.delta.content ~= vim.NIL then opts.on_chunk(choice.delta.content) end
    end
  end
end

-- 解析非流式响应 (Parse non-streaming response)
M.parse_response_without_stream = function(data, _, opts)
  ---@type QianwenChatResponse
  local json = vim.json.decode(data)
  if json.choices and json.choices[1] then
    local choice = json.choices[1]
    if choice.message and choice.message.content then
      opts.on_chunk(choice.message.content)
      vim.schedule(function() opts.on_complete(nil) end)
    end
  end
end

-- 构建curl参数 (Build curl arguments)
M.parse_curl_args = function(provider, code_opts)
  local base, body_opts = P.parse_config(provider)

  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. provider.parse_api_key(),
  }

  -- 支持stream模式 (Support stream mode)
  local stream = true
  if body_opts.stream ~= nil then stream = body_opts.stream end

  return {
    url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
    headers = headers,
    body = vim.tbl_deep_extend("force", {
      model = base.model or "qwen-coder-plus-latest",
      messages = M.parse_messages(code_opts),
      stream = stream,
    }, body_opts),
  }
end

return M
