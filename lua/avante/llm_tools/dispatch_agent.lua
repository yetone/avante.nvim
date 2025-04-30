local Providers = require("avante.providers")
local Config = require("avante.config")
local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")
local HistoryMessage = require("avante.history_message")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "dispatch_agent"

M.get_description = function()
  local provider = Providers[Config.provider]
  if Config.provider:match("copilot") and provider.model and provider.model:match("gpt") then
    return [[Launch a new agent that has access to the following tools: `glob`, `grep`, `ls`, `view`. When you are searching for a keyword or file and are not confident that you will find the right match on the first try, use the Agent tool to perform the search for you.]]
  end

  return [[Launch a new agent that has access to the following tools: `glob`, `grep`, `ls`, `view`. When you are searching for a keyword or file and are not confident that you will find the right match on the first try, use the Agent tool to perform the search for you. For example:

- If you are searching for a keyword like "config" or "logger", the Agent tool is appropriate
- If you want to read a specific file path, use the `view` or `glob` tool instead of the `dispatch_agent` tool, to find the match more quickly
- If you are searching for a specific class definition like "class Foo", use the `glob` tool instead, to find the match more quickly

Usage notes:
1. Launch multiple agents concurrently whenever possible, to maximize performance; to do that, use a single message with multiple tool uses
2. When the agent is done, it will return a single message back to you. The result returned by the agent is not visible to the user. To show the user the result, you should send a text message back to the user with a concise summary of the result.
3. Each agent invocation is stateless. You will not be able to send additional messages to the agent, nor will the agent be able to communicate with you outside of its final report. Therefore, your prompt should contain a highly detailed task description for the agent to perform autonomously and you should specify exactly what information the agent should return back to you in its final and only message to you.
4. The agent's outputs should generally be trusted
5. IMPORTANT: The agent can not use `bash`, `write`, `str_replace`, so can not modify files. If you want to use these tools, use them directly instead of going through the agent.]]
end

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "prompt",
      description = "The task for the agent to perform",
      type = "string",
    },
  },
  required = { "prompt" },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "result",
    description = "The result of the agent",
    type = "string",
  },
  {
    name = "error",
    description = "The error message if the agent fails",
    type = "string",
    optional = true,
  },
}

local function get_available_tools()
  return {
    require("avante.llm_tools.ls"),
    require("avante.llm_tools.grep"),
    require("avante.llm_tools.glob"),
    require("avante.llm_tools.view"),
  }
end

---@type AvanteLLMToolFunc<{ prompt: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  local Llm = require("avante.llm")
  if not on_complete then return false, "on_complete not provided" end
  local prompt = opts.prompt
  local tools = get_available_tools()
  local start_time = Utils.get_timestamp()

  if on_log then on_log("prompt: " .. prompt) end

  local system_prompt = ([[You are a helpful assistant with access to various tools.
Your task is to help the user with their request: "${prompt}"
Be thorough and use the tools available to you to find the most relevant information.
When you're done, provide a clear and concise summary of what you found.]]):gsub("${prompt}", prompt)

  local messages = {}
  table.insert(messages, { role = "user", content = "go!" })

  local tool_use_messages = {}

  local total_tokens = 0
  local final_response = ""

  local memory_content = nil
  local history_messages = {}

  local stream_options = {
    ask = true,
    disable_compact_history_messages = true,
    memory = memory_content,
    code_lang = "unknown",
    provider = Providers[Config.provider],
    get_history_messages = function() return history_messages end,
    on_tool_log = session_ctx.on_tool_log,
    on_messages_add = function(msgs)
      msgs = vim.islist(msgs) and msgs or { msgs }
      for _, msg in ipairs(msgs) do
        local content = msg.message.content
        if type(content) == "table" and #content > 0 and content[1].type == "tool_use" then
          tool_use_messages[msg.uuid] = true
        end
      end
      for _, msg in ipairs(msgs) do
        local idx = nil
        for i, m in ipairs(history_messages) do
          if m.uuid == msg.uuid then
            idx = i
            break
          end
        end
        if idx ~= nil then
          history_messages[idx] = msg
        else
          table.insert(history_messages, msg)
        end
      end
      if session_ctx.on_messages_add then session_ctx.on_messages_add(msgs) end
    end,
    session_ctx = session_ctx,
    prompt_opts = {
      system_prompt = system_prompt,
      tools = tools,
      messages = messages,
    },
    on_start = session_ctx.on_start,
    on_chunk = function(chunk)
      if not chunk then return end
      final_response = final_response .. chunk
      total_tokens = total_tokens + (#vim.split(chunk, " ") * 1.3)
    end,
    on_stop = function(stop_opts)
      if stop_opts.error ~= nil then
        local err = string.format("dispatch_agent failed: %s", vim.inspect(stop_opts.error))
        on_complete(err, nil)
        return
      end
      local end_time = Utils.get_timestamp()
      local elapsed_time = Utils.datetime_diff(start_time, end_time)
      local tool_use_count = vim.tbl_count(tool_use_messages)
      local summary = "dispatch_agent Done ("
        .. (tool_use_count <= 1 and "1 tool use" or tool_use_count .. " tool uses")
        .. " · "
        .. math.ceil(total_tokens)
        .. " tokens · "
        .. elapsed_time
        .. "s)"
      if session_ctx.on_messages_add then
        local message = HistoryMessage:new({
          role = "assistant",
          content = "\n\n" .. summary,
        }, {
          just_for_display = true,
        })
        session_ctx.on_messages_add({ message })
      end
      local response = string.format("Final response:\n%s\n\nSummary:\n%s", summary, final_response)
      on_complete(response, nil)
    end,
  }

  local function on_memory_summarize(dropped_history_messages)
    Llm.summarize_memory(memory_content, dropped_history_messages or {}, function(memory)
      if memory then stream_options.memory = memory.content end
      local new_history_messages = {}
      for _, msg in ipairs(history_messages) do
        if vim.iter(dropped_history_messages):find(function(dropped_msg) return dropped_msg.uuid == msg.uuid end) then
          goto continue
        end
        table.insert(new_history_messages, msg)
        ::continue::
      end
      history_messages = new_history_messages
      Llm._stream(stream_options)
    end)
  end

  stream_options.on_memory_summarize = on_memory_summarize

  Llm._stream(stream_options)
end

return M
