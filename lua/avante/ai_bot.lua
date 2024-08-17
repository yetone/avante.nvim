local fn = vim.fn
local api = vim.api

local curl = require("plenary.curl")

local Utils = require("avante.utils")
local Config = require("avante.config")
local Tiktoken = require("avante.tiktoken")

---@class avante.AiBot
local M = {}

---@class Environment: table<[string], any>
---@field [string] string the environment variable name
---@field fallback? string Optional fallback API key environment variable name

---@class EnvironmentHandler: table<[Provider], string>
local E = {
  ---@type table<Provider, Environment | string>
  env = {
    openai = "OPENAI_API_KEY",
    claude = "ANTHROPIC_API_KEY",
    azure = { "AZURE_OPENAI_API_KEY", fallback = "OPENAI_API_KEY" },
  },
  _once = false,
}

E = setmetatable(E, {
  ---@param k Provider
  __index = function(_, k)
    local envvar = E.env[k]
    if type(envvar) == "string" then
      local value = os.getenv(envvar)
      return value and true or false
    elseif type(envvar) == "table" then
      local main_key = envvar[1]
      local value = os.getenv(main_key)
      if value then
        return true
      elseif envvar.fallback then
        return os.getenv(envvar.fallback) and true or false
      end
    end
    return false
  end,
})

--- return the environment variable name for the given provider
---@param provider? Provider
---@return string the envvar key
E.key = function(provider)
  provider = provider or Config.provider
  local var = E.env[provider]
  return type(var) == "table" and var[1] ---@cast var string
    or var
end

E.setup = function(var)
  local Dressing = require("avante.ui.dressing")

  if E._once then
    return
  end

  ---@param value string
  ---@return nil
  local function on_confirm(value)
    if value then
      vim.fn.setenv(var, value)
      E._once = true
    else
      if not E[Config.provider] then
        vim.notify_once("Failed to set " .. var .. ". Avante won't work as expected", vim.log.levels.WARN)
      end
    end
  end

  api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    pattern = "*",
    once = true,
    callback = function()
      vim.defer_fn(function()
        -- only mount if given buffer is not of buftype ministarter, dashboard, alpha, qf
        local exclude_buftypes = { "dashboard", "alpha", "qf", "nofile" }
        local exclude_filetypes = {
          "NvimTree",
          "Outline",
          "help",
          "dashboard",
          "alpha",
          "qf",
          "ministarter",
          "TelescopePrompt",
          "gitcommit",
        }
        if
          not vim.tbl_contains(exclude_buftypes, vim.bo.buftype)
          and not vim.tbl_contains(exclude_filetypes, vim.bo.filetype)
        then
          Dressing.initialize_input_buffer({ opts = { prompt = "Enter " .. var .. ": " }, on_confirm = on_confirm })
        end
      end, 200)
    end,
  })
end

local system_prompt = [[
You are an excellent programming expert.
]]

local base_user_prompt = [[
Your primary task is to suggest code modifications with precise line number ranges. Follow these instructions meticulously:

1. Carefully analyze the original code, paying close attention to its structure and line numbers. Line numbers start from 1 and include ALL lines, even empty ones.

2. When suggesting modifications:
   a. Use the language in the question to reply. If there are non-English parts in the question, use the language of those parts.
   b. Explain why the change is necessary or beneficial.
   c. Provide the exact code snippet to be replaced using this format:

Replace lines: {{start_line}}-{{end_line}}
```{{language}}
{{suggested_code}}
```

3. Crucial guidelines for suggested code snippets:
   - Only apply the change(s) suggested by the most recent assistant message (before your generation).
   - Do not make any unrelated changes to the code.
   - Produce a valid full rewrite of the entire original file without skipping any lines. Do not be lazy!
   - Do not arbitrarily delete pre-existing comments/empty Lines.
   - Do not omit large parts of the original file for no reason.
   - Do not omit any needed changes from the requisite messages/code blocks.
   - If there is a clicked code block, bias towards just applying that (and applying other changes implied).
   - Please keep your suggested code changes minimal, and do not include irrelevant lines in the code snippet.

4. Crucial guidelines for line numbers:
   - The range {{start_line}}-{{end_line}} is INCLUSIVE. Both start_line and end_line are included in the replacement.
   - Count EVERY line, including empty lines, comments, and the LAST line of the file.
   - For single-line changes, use the same number for start and end lines.
   - For multi-line changes, ensure the range covers ALL affected lines, from the very first to the very last.
   - Double-check that your line numbers align perfectly with the original code structure.

5. Final check:
   - Review all suggestions, ensuring each line number is correct, especially the start_line and end_line.
   - Confirm that no unrelated code is accidentally modified or deleted.
   - Verify that the start_line and end_line correctly include all intended lines for replacement.
   - Perform a final alignment check to ensure your line numbers haven't shifted, especially the start_line.
   - Double-check that your line numbers align perfectly with the original code structure.
   - Do not show the full content after these modifications.

Remember: Accurate line numbers are CRITICAL. The range start_line to end_line must include ALL lines to be replaced, from the very first to the very last. Double-check every range before finalizing your response, paying special attention to the start_line to ensure it hasn't shifted down. Ensure that your line numbers perfectly match the original code structure without any overall shift.
]]

local function call_claude_api_stream(question, code_lang, code_content, selected_code_content, on_chunk, on_complete)
  local api_key = os.getenv(E.key("claude"))

  local tokens = Config.claude.max_tokens
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

  if Tiktoken.count(code_prompt_obj.text) > 1024 then
    code_prompt_obj.cache_control = { type = "ephemeral" }
  end

  if selected_code_content then
    code_prompt_obj.text = string.format("<code_context>```%s\n%s```</code_context>", code_lang, code_content)
  end

  local message_content = {
    code_prompt_obj,
  }

  if selected_code_content then
    local selected_code_obj = {
      type = "text",
      text = string.format("<code>```%s\n%s```</code>", code_lang, selected_code_content),
    }

    if Tiktoken.count(selected_code_obj.text) > 1024 then
      selected_code_obj.cache_control = { type = "ephemeral" }
    end

    table.insert(message_content, selected_code_obj)
  end

  table.insert(message_content, {
    type = "text",
    text = string.format("<question>%s</question>", question),
  })

  local user_prompt = base_user_prompt

  local user_prompt_obj = {
    type = "text",
    text = user_prompt,
  }

  if Tiktoken.count(user_prompt_obj.text) > 1024 then
    user_prompt_obj.cache_control = { type = "ephemeral" }
  end

  table.insert(message_content, user_prompt_obj)

  local body = {
    model = Config.claude.model,
    system = system_prompt,
    messages = {
      {
        role = "user",
        content = message_content,
      },
    },
    stream = true,
    temperature = Config.claude.temperature,
    max_tokens = tokens,
  }

  local url = Utils.trim_suffix(Config.claude.endpoint, "/") .. "/v1/messages"

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
      for _, line in ipairs(vim.split(data, "\n")) do
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

local function call_openai_api_stream(question, code_lang, code_content, selected_code_content, on_chunk, on_complete)
  local api_key = os.getenv(E.key("openai"))
  local user_prompt = base_user_prompt
    .. "\n\nCODE:\n"
    .. "```"
    .. code_lang
    .. "\n"
    .. code_content
    .. "\n```"
    .. "\n\nQUESTION:\n"
    .. question

  if selected_code_content then
    user_prompt = base_user_prompt
      .. "\n\nCODE CONTEXT:\n"
      .. "```"
      .. code_lang
      .. "\n"
      .. code_content
      .. "\n```"
      .. "\n\nCODE:\n"
      .. "```"
      .. code_lang
      .. "\n"
      .. selected_code_content
      .. "\n```"
      .. "\n\nQUESTION:\n"
      .. question
  end

  local url, headers, body
  if Config.provider == "azure" then
    api_key = os.getenv(E.key("azure"))
    url = Config.azure.endpoint
      .. "/openai/deployments/"
      .. Config.azure.deployment
      .. "/chat/completions?api-version="
      .. Config.azure.api_version
    headers = {
      ["Content-Type"] = "application/json",
      ["api-key"] = api_key,
    }
    body = {
      messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = user_prompt },
      },
      temperature = Config.azure.temperature,
      max_tokens = Config.azure.max_tokens,
      stream = true,
    }
  else
    url = Utils.trim_suffix(Config.openai.endpoint, "/") .. "/v1/chat/completions"
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key,
    }
    body = {
      model = Config.openai.model,
      messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = user_prompt },
      },
      temperature = Config.openai.temperature,
      max_tokens = Config.openai.max_tokens,
      stream = true,
    }
  end

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
      for _, line in ipairs(vim.split(data, "\n")) do
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
          if parsed and parsed.choices and parsed.choices[1] then
            local choice = parsed.choices[1]
            if choice.finish_reason == "stop" then
              on_complete(nil)
            elseif choice.delta and choice.delta.content then
              on_chunk(choice.delta.content)
            end
          end
        end)
      end
    end,
    headers = headers,
    body = fn.json_encode(body),
  })
end

---@param question string
---@param code_lang string
---@param code_content string
---@param selected_content_content string | nil
---@param on_chunk fun(chunk: string): any
---@param on_complete fun(err: string|nil): any
function M.call_ai_api_stream(question, code_lang, code_content, selected_content_content, on_chunk, on_complete)
  if Config.provider == "openai" or Config.provider == "azure" then
    call_openai_api_stream(question, code_lang, code_content, selected_content_content, on_chunk, on_complete)
  elseif Config.provider == "claude" then
    call_claude_api_stream(question, code_lang, code_content, selected_content_content, on_chunk, on_complete)
  end
end

function M.setup()
  local has = E[Config.provider]
  if not has then
    E.setup(E.key())
  end
end

return M
