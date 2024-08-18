local api = vim.api

local curl = require("plenary.curl")

local Utils = require("avante.utils")
local Config = require("avante.config")
local Tiktoken = require("avante.tiktoken")

---@private
---@class AvanteAiBotInternal
local H = {}

---@class avante.AiBot
local M = {}

M.CANCEL_PATTERN = "AvanteAiBotEscape"

---@class EnvironmentHandler: table<[Provider], string>
local E = {
  ---@type table<Provider, string>
  env = {
    openai = "OPENAI_API_KEY",
    claude = "ANTHROPIC_API_KEY",
    azure = "AZURE_OPENAI_API_KEY",
    deepseek = "DEEPSEEK_API_KEY",
    groq = "GROQ_API_KEY",
  },
}

E = setmetatable(E, {
  ---@param k Provider
  __index = function(_, k)
    return os.getenv(E.env[k]) and true or false
  end,
})
E._once = false

--- return the environment variable name for the given provider
---@param provider? Provider
---@return string the envvar key
E.key = function(provider)
  provider = provider or Config.provider
  local var = E.env[provider]
  return type(var) == "table" and var[1] ---@cast var string
    or var
end

---@param provider? Provider
E.value = function(provider)
  provider = provider or Config.provider
  return os.getenv(E.key(provider))
end

--- intialize the environment variable for current neovim session.
--- This will only run once and spawn a UI for users to input the envvar.
--- @param var Provider supported providers
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
          "gitrebase",
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
   - The content regarding line numbers MUST strictly follow the format "Replace lines: {{start_line}}-{{end_line}}". Do not be lazy!
   - The range {{start_line}}-{{end_line}} is INCLUSIVE. Both start_line and end_line are included in the replacement.
   - Count EVERY line, including empty lines and comments lines, comments. Do not be lazy!
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

---@class AvantePromptOptions: table<[string], string>
---@field question string
---@field code_lang string
---@field code_content string
---@field selected_code_content? string
---
---@alias AvanteAiMessageBuilder fun(opts: AvantePromptOptions): {role: "user" | "system", content: string | table<string, any>}[]
---
---@class AvanteCurlOutput: {url: string, body: table<string, any> | string, headers: table<string, string>}
---@alias AvanteCurlArgsBuilder fun(code_opts: AvantePromptOptions): AvanteCurlOutput
---
---@class ResponseParser
---@field event_state string
---@field on_chunk fun(chunk: string): any
---@field on_complete fun(err: string|nil): any
---@field on_error? fun(err_type: string): nil
---@alias AvanteAiResponseParser fun(data_stream: string, opts: ResponseParser): nil

------------------------------Anthropic------------------------------

---@type AvanteAiMessageBuilder
H.make_claude_message = function(opts)
  local code_prompt_obj = {
    type = "text",
    text = string.format("<code>```%s\n%s```</code>", opts.code_lang, opts.code_content),
  }

  if Tiktoken.count(code_prompt_obj.text) > 1024 then
    code_prompt_obj.cache_control = { type = "ephemeral" }
  end

  if opts.selected_code_content then
    code_prompt_obj.text = string.format("<code_context>```%s\n%s```</code_context>", opts.code_lang, opts.code_content)
  end

  local message_content = {
    code_prompt_obj,
  }

  if opts.selected_code_content then
    local selected_code_obj = {
      type = "text",
      text = string.format("<code>```%s\n%s```</code>", opts.code_lang, opts.selected_code_content),
    }

    if Tiktoken.count(selected_code_obj.text) > 1024 then
      selected_code_obj.cache_control = { type = "ephemeral" }
    end

    table.insert(message_content, selected_code_obj)
  end

  table.insert(message_content, {
    type = "text",
    text = string.format("<question>%s</question>", opts.question),
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

  return {
    {
      role = "user",
      content = message_content,
    },
  }
end

---@type AvanteAiResponseParser
H.parse_claude_response = function(data_stream, opts)
  if opts.event_state == "content_block_delta" then
    local json = vim.json.decode(data_stream)
    opts.on_chunk(json.delta.text)
  elseif opts.event_state == "message_stop" then
    opts.on_complete(nil)
  elseif opts.event_state == "error" then
    opts.on_complete(vim.json.decode(data_stream))
  end
end

---@type AvanteCurlArgsBuilder
H.make_claude_curl_args = function(code_opts)
  return {
    url = Utils.trim(Config.claude.endpoint, { suffix = "/" }) .. "/v1/messages",
    headers = {
      ["Content-Type"] = "application/json",
      ["x-api-key"] = E.value("claude"),
      ["anthropic-version"] = "2023-06-01",
      ["anthropic-beta"] = "prompt-caching-2024-07-31",
    },
    body = {
      model = Config.claude.model,
      system = system_prompt,
      stream = true,
      messages = H.make_claude_message(code_opts),
      temperature = Config.claude.temperature,
      max_tokens = Config.claude.max_tokens,
    },
  }
end

------------------------------OpenAI------------------------------

---@type AvanteAiMessageBuilder
H.make_openai_message = function(opts)
  local user_prompt = base_user_prompt
    .. "\n\nCODE:\n"
    .. "```"
    .. opts.code_lang
    .. "\n"
    .. opts.code_content
    .. "\n```"
    .. "\n\nQUESTION:\n"
    .. opts.question

  if opts.selected_code_content ~= nil then
    user_prompt = base_user_prompt
      .. "\n\nCODE CONTEXT:\n"
      .. "```"
      .. opts.code_lang
      .. "\n"
      .. opts.code_content
      .. "\n```"
      .. "\n\nCODE:\n"
      .. "```"
      .. opts.code_lang
      .. "\n"
      .. opts.selected_code_content
      .. "\n```"
      .. "\n\nQUESTION:\n"
      .. opts.question
  end

  return {
    { role = "system", content = system_prompt },
    { role = "user", content = user_prompt },
  }
end

---@type AvanteAiResponseParser
H.parse_openai_response = function(data_stream, opts)
  if data_stream:match('"%[DONE%]":') then
    opts.on_complete(nil)
    return
  end
  if data_stream:match('"delta":') then
    local json = vim.json.decode(data_stream)
    if json.choices and json.choices[1] then
      local choice = json.choices[1]
      if choice.finish_reason == "stop" then
        opts.on_complete(nil)
      elseif choice.delta.content then
        opts.on_chunk(choice.delta.content)
      end
    end
  end
end

---@type AvanteCurlArgsBuilder
H.make_openai_curl_args = function(code_opts)
  return {
    url = Utils.trim(Config.openai.endpoint, { suffix = "/" }) .. "/v1/chat/completions",
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. E.value("openai"),
    },
    body = {
      model = Config.openai.model,
      messages = H.make_openai_message(code_opts),
      temperature = Config.openai.temperature,
      max_tokens = Config.openai.max_tokens,
      stream = true,
    },
  }
end

------------------------------Azure------------------------------

---@type AvanteAiMessageBuilder
H.make_azure_message = H.make_openai_message

---@type AvanteAiResponseParser
H.parse_azure_response = H.parse_openai_response

---@type AvanteCurlArgsBuilder
H.make_azure_curl_args = function(code_opts)
  return {
    url = Config.azure.endpoint
      .. "/openai/deployments/"
      .. Config.azure.deployment
      .. "/chat/completions?api-version="
      .. Config.azure.api_version,
    headers = {
      ["Content-Type"] = "application/json",
      ["api-key"] = E.value("azure"),
    },
    body = {
      messages = H.make_openai_message(code_opts),
      temperature = Config.azure.temperature,
      max_tokens = Config.azure.max_tokens,
      stream = true,
    },
  }
end

------------------------------Deepseek------------------------------

---@type AvanteAiMessageBuilder
H.make_deepseek_message = H.make_openai_message

---@type AvanteAiResponseParser
H.parse_deepseek_response = H.parse_openai_response

---@type AvanteCurlArgsBuilder
H.make_deepseek_curl_args = function(code_opts)
  return {
    url = Utils.trim(Config.deepseek.endpoint, { suffix = "/" }) .. "/chat/completions",
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. E.value("deepseek"),
    },
    body = {
      model = Config.deepseek.model,
      messages = H.make_openai_message(code_opts),
      temperature = Config.deepseek.temperature,
      max_tokens = Config.deepseek.max_tokens,
      stream = true,
    },
  }
end

------------------------------Grok------------------------------

---@type AvanteAiMessageBuilder
H.make_groq_message = H.make_openai_message

---@type AvanteAiResponseParser
H.parse_groq_response = H.parse_openai_response

---@type AvanteCurlArgsBuilder
H.make_groq_curl_args = function(code_opts)
  return {
    url = Utils.trim(Config.groq.endpoint, { suffix = "/" }) .. "/openai/v1/chat/completions",
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. E.value("groq"),
    },
    body = {
      model = Config.groq.model,
      messages = H.make_openai_message(code_opts),
      temperature = Config.groq.temperature,
      max_tokens = Config.groq.max_tokens,
      stream = true,
    },
  }
end

------------------------------Logic------------------------------

local group = vim.api.nvim_create_augroup("AvanteAiBot", { clear = true })
local active_job = nil

---@param question string
---@param code_lang string
---@param code_content string
---@param selected_content_content string | nil
---@param on_chunk fun(chunk: string): any
---@param on_complete fun(err: string|nil): any
M.invoke_llm_stream = function(question, code_lang, code_content, selected_content_content, on_chunk, on_complete)
  local provider = Config.provider
  local event_state = nil

  ---@type AvanteCurlOutput
  local spec = H["make_" .. provider .. "_curl_args"]({
    question = question,
    code_lang = code_lang,
    code_content = code_content,
    selected_code_content = selected_content_content,
  })

  ---@param line string
  local function parse_and_call(line)
    local event = line:match("^event: (.+)$")
    if event then
      event_state = event
      return
    end
    local data_match = line:match("^data: (.+)$")
    if data_match then
      H["parse_" .. provider .. "_response"](
        data_match,
        vim.deepcopy({ on_chunk = on_chunk, on_complete = on_complete, event_state = event_state }, true)
      )
    end
  end

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  active_job = curl.post(spec.url, {
    headers = spec.headers,
    body = vim.json.encode(spec.body),
    stream = function(err, data, _)
      if err then
        on_complete(err)
        return
      end
      if not data then
        return
      end
      vim.schedule(function()
        parse_and_call(data)
      end)
    end,
    on_error = function(err)
      on_complete(err)
    end,
    callback = function(_)
      active_job = nil
    end,
  })

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = M.CANCEL_PATTERN,
    callback = function()
      if active_job then
        active_job:shutdown()
        vim.notify("LLM request cancelled", vim.log.levels.DEBUG)
        active_job = nil
      end
    end,
  })

  return active_job
end

function M.setup()
  local has = E[Config.provider]
  if not has then
    E.setup(E.key())
  end
end

return M
