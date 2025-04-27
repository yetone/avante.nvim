local Providers = require("avante.providers")
local Config = require("avante.config")
local Utils = require("avante.utils")
local Base = require("avante.llm_tools.base")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "dispatch_agent"

M.get_description = function()
  local provider = Providers[Config.provider]
  if Config.provider:match("copilot") and provider.model and provider.model:match("gpt") then
    return [[Launch a new agent that has access to the following tools: `glob`, `grep`, `ls`, `view`. When you are searching for a keyword or file and are not confident that you will find the right match on the first try, use the Agent tool to perform the search for you.]]
  elseif Config.provider:match("gemini") then
    return [[
Launches a new agent with access to file system tools for complex project-wide queries.
- Use this tool when you need to perform multi-step file system operations or complex searches across the entire project.
- Available tools for the agent include: `glob`, `grep`, `ls`, `view`.
- This tool is suitable for tasks like:
    - Finding files related to a specific keyword (e.g., "config", "logger").
    - Performing complex searches across multiple files.
    - Orchestrating a sequence of file system operations.
- For simple file viewing or listing, use the `view` or `ls` tools directly instead.
- For executing bash commands, use the `bash` tool instead.

Example:
To find all files containing the word "logger", you might use the agent tool (though the exact invocation is managed internally).
]]
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
  if not opts or not opts.prompt or opts.prompt == "" then
    if on_complete then on_complete(nil, "Error: Missing required parameter 'prompt' for tool 'dispatch_agent'.") end
    return
  end
  local Llm = require("avante.llm")
  if not on_complete then return false, "on_complete not provided" end
  local prompt = opts.prompt
  local tools = get_available_tools()
  local start_time = os.date("%Y-%m-%d %H:%M:%S")

  if on_log then on_log("prompt: " .. prompt) end

  local system_prompt = ([[You are a helpful assistant with access to various tools.
Your task is to help the user with their request: "${prompt}"
Be thorough and use the tools available to you to find the most relevant information.
When you're done, provide a clear and concise summary of what you found.]]):gsub("${prompt}", prompt)

  local messages = session_ctx and session_ctx.messages or {}
  messages = messages or {}
  table.insert(messages, { role = "user", content = prompt })

  local total_tokens = 0
  local final_response = ""
  Llm._stream({
    ask = true,
    code_lang = "unknown",
    provider = Providers[Config.provider],
    on_tool_log = function(tool_id, tool_name, log, state)
      if on_log then on_log(string.format("[%s] %s", tool_name, log)) end
    end,
    session_ctx = session_ctx,
    prompt_opts = {
      system_prompt = system_prompt,
      tools = tools,
      messages = messages,
    },
    on_start = function(_) end,
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
      local end_time = os.date("%Y-%m-%d %H:%M:%S")
      local elapsed_time = Utils.datetime_diff(tostring(start_time), tostring(end_time))
      local tool_use_count = stop_opts.tool_histories and #stop_opts.tool_histories or 0
      local summary = "Done ("
        .. (tool_use_count <= 1 and "1 tool use" or tool_use_count .. " tool uses")
        .. " · "
        .. math.ceil(total_tokens)
        .. " tokens · "
        .. elapsed_time
        .. "s)"
      Utils.debug("summary", summary)
      local response = string.format("Final response:\n%s\n\nSummary:\n%s", summary, final_response)
      on_complete(response, nil)
    end,
  })
end

return M
