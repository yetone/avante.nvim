local M = {}

local curl = require("plenary.curl")
local utils = require("avante.utils")
local config = require("avante.config")
local tiktoken = require("avante.tiktoken")

local fn = vim.fn

local system_prompt = [[
You are an excellent programming expert.
]]

local base_user_prompt = [[
Your primary task is to suggest code modifications with precise line number ranges. Follow these instructions meticulously:

1. Carefully analyze the original code, paying close attention to its structure and line numbers. Line numbers start from 1 and include ALL lines, even empty ones.

2. When suggesting modifications:
   a. Explain why the change is necessary or beneficial.
   b. Provide the exact code snippet to be replaced using this format:

Replace lines: {{start_line}}-{{end_line}}
```{{language}}
{{suggested_code}}
```

3. Crucial guidelines for line numbers:
   - The range {{start_line}}-{{end_line}} is INCLUSIVE. Both start_line and end_line are included in the replacement.
   - Count EVERY line, including empty lines, comments, and the LAST line of the file.
   - For single-line changes, use the same number for start and end lines.
   - For multi-line changes, ensure the range covers ALL affected lines, from the very first to the very last.
   - Include the entire block (e.g., complete function) when modifying structured code.
   - Pay special attention to the start_line, ensuring it's not omitted or incorrectly set.
   - Double-check that your start_line is correct, especially for changes at the beginning of the file.
   - Also, be careful with the end_line, especially when it's the last line of the file.
   - Double-check that your line numbers align perfectly with the original code structure.

4. Context and verification:
   - Show 1-2 unchanged lines before and after each modification as context.
   - These context lines are NOT included in the replacement range.
   - After each suggestion, recount the lines to verify the accuracy of your line numbers.
   - Double-check that both the start_line and end_line are correct for each modification.
   - Verify that your suggested changes align perfectly with the original code structure.

5. Final check:
   - Review all suggestions, ensuring each line number is correct, especially the start_line and end_line.
   - Pay extra attention to the start_line of each modification, ensuring it hasn't shifted down.
   - Confirm that no unrelated code is accidentally modified or deleted.
   - Verify that the start_line and end_line correctly include all intended lines for replacement.
   - If a modification involves the first or last line of the file, explicitly state this in your explanation.
   - Perform a final alignment check to ensure your line numbers haven't shifted, especially the start_line.
   - Double-check that your line numbers align perfectly with the original code structure.
   - Do not show the content after these modifications.

Remember: Accurate line numbers are CRITICAL. The range start_line to end_line must include ALL lines to be replaced, from the very first to the very last. Double-check every range before finalizing your response, paying special attention to the start_line to ensure it hasn't shifted down. Ensure that your line numbers perfectly match the original code structure without any overall shift.
]]

local function call_claude_api_stream(question, code_lang, code_content, on_chunk, on_complete)
  local api_key = os.getenv("ANTHROPIC_API_KEY")
  if not api_key then
    error("ANTHROPIC_API_KEY environment variable is not set")
  end

  local user_prompt = base_user_prompt

  local tokens = config.get().claude.max_tokens
  local headers = {
    ["Content-Type"] = "application/json",
    ["x-api-key"] = api_key,
    ["anthropic-version"] = "2023-06-01",
    ["anthropic-beta"] = "prompt-caching-2024-07-31",
  }

  local code_prompt_obj = {
    type = "text",
    text = string.format("<code>```%s\n%s```</code>", code_lang, code_content),
  }

  local user_prompt_obj = {
    type = "text",
    text = user_prompt,
  }

  if tiktoken.count(code_prompt_obj.text) > 1024 then
    code_prompt_obj.cache_control = { type = "ephemeral" }
  end

  if tiktoken.count(user_prompt_obj.text) > 1024 then
    user_prompt_obj.cache_control = { type = "ephemeral" }
  end

  local body = {
    model = config.get().claude.model,
    system = system_prompt,
    messages = {
      {
        role = "user",
        content = {
          code_prompt_obj,
          {
            type = "text",
            text = string.format("<question>%s</question>", question),
          },
          user_prompt_obj,
        },
      },
    },
    stream = true,
    temperature = config.get().claude.temperature,
    max_tokens = tokens,
  }

  local url = utils.trim_suffix(config.get().claude.endpoint, "/") .. "/v1/messages"

  print("Sending request to Claude API...")

  curl.post(url, {
    ---@diagnostic disable-next-line: unused-local
    stream = function(err, data, job)
      if err then
        on_complete(err)
        return
      end
      if not data then
        return
      end
      for line in data:gmatch("[^\r\n]+") do
        if line:sub(1, 6) ~= "data: " then
          return
        end
        vim.schedule(function()
          local success, parsed = pcall(fn.json_decode, line:sub(7))
          if not success then
            error("Error: failed to parse json: " .. parsed)
            return
          end
          if parsed and parsed.type == "content_block_delta" then
            on_chunk(parsed.delta.text)
          elseif parsed and parsed.type == "message_stop" then
            -- Stream request completed
            on_complete(nil)
          elseif parsed and parsed.type == "error" then
            -- Stream request completed
            on_complete(parsed)
          end
        end)
      end
    end,
    headers = headers,
    body = fn.json_encode(body),
  })
end

local function call_openai_api_stream(question, code_lang, code_content, on_chunk, on_complete)
  local api_key = os.getenv("OPENAI_API_KEY")
  if not api_key then
    error("OPENAI_API_KEY environment variable is not set")
  end

  local user_prompt = base_user_prompt
    .. "\n\nQUESTION:\n"
    .. question
    .. "\n\nCODE:\n"
    .. "```"
    .. code_lang
    .. "\n"
    .. code_content
    .. "\n```"

  local url, headers, body
  if config.get().provider == "azure" then
    api_key = os.getenv("AZURE_OPENAI_API_KEY") or os.getenv("OPENAI_API_KEY")
    if not api_key then
      error("Azure OpenAI API key is not set. Please set AZURE_OPENAI_API_KEY or OPENAI_API_KEY environment variable.")
    end
    url = config.get().azure.endpoint
      .. "/openai/deployments/"
      .. config.get().azure.deployment
      .. "/chat/completions?api-version="
      .. config.get().azure.api_version
    headers = {
      ["Content-Type"] = "application/json",
      ["api-key"] = api_key,
    }
    body = {
      messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = user_prompt },
      },
      temperature = config.get().azure.temperature,
      max_tokens = config.get().azure.max_tokens,
      stream = true,
    }
  else
    url = utils.trim_suffix(config.get().openai.endpoint, "/") .. "/v1/chat/completions"
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key,
    }
    body = {
      model = config.get().openai.model,
      messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = user_prompt },
      },
      temperature = config.get().openai.temperature,
      max_tokens = config.get().openai.max_tokens,
      stream = true,
    }
  end

  print("Sending request to " .. (config.get().provider == "azure" and "Azure OpenAI" or "OpenAI") .. " API...")

  curl.post(url, {
    ---@diagnostic disable-next-line: unused-local
    stream = function(err, data, job)
      if err then
        on_complete(err)
        return
      end
      if not data then
        return
      end
      for line in data:gmatch("[^\r\n]+") do
        if line:sub(1, 6) ~= "data: " then
          return
        end
        vim.schedule(function()
          local piece = line:sub(7)
          local success, parsed = pcall(fn.json_decode, piece)
          if not success then
            if piece == "[DONE]" then
              on_complete(nil)
              return
            end
            error("Error: failed to parse json: " .. parsed)
            return
          end
          if parsed and parsed.choices and parsed.choices[1].delta.content then
            on_chunk(parsed.choices[1].delta.content)
          elseif parsed and parsed.choices and parsed.choices[1].finish_reason == "stop" then
            -- Stream request completed
            on_complete(nil)
          end
        end)
      end
    end,
    headers = headers,
    body = fn.json_encode(body),
  })
end

function M.call_ai_api_stream(question, code_lang, code_content, on_chunk, on_complete)
  if config.get().provider == "openai" or config.get().provider == "azure" then
    call_openai_api_stream(question, code_lang, code_content, on_chunk, on_complete)
  elseif config.get().provider == "claude" then
    call_claude_api_stream(question, code_lang, code_content, on_chunk, on_complete)
  end
end

return M
