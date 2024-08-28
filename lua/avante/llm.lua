local api = vim.api

local curl = require("plenary.curl")

local Utils = require("avante.utils")
local Config = require("avante.config")
local P = require("avante.providers")

---@class avante.LLM
local M = {}

M.CANCEL_PATTERN = "AvanteLLMEscape"

------------------------------Prompt and type------------------------------

---@alias AvanteSystemPrompt string
local system_prompt = [[
You are an excellent programming expert.
]]

---@alias AvanteBasePrompt string
local planning_mode_prompt = [[
Your primary task is to suggest code modifications with precise line number ranges. Follow these instructions meticulously:

1. Carefully analyze the original code, paying close attention to its structure and line numbers. Line numbers start from 1 and include ALL lines, even empty ones.

2. When suggesting modifications:
   a. Use the language in the question to reply. If there are non-English parts in the question, use the language of those parts.
   b. Explain why the change is necessary or beneficial.
   c. If an image is provided, make sure to use the image in conjunction with the code snippet.
   d. Provide the exact code snippet to be replaced using this format:

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
   - Maintain the SAME indentation in the returned code as in the source code

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

local editing_mode_prompt = [[
Your task is to modify the provided code according to the user's request. Follow these instructions precisely:

1. Carefully analyze the original code and the user's request.
2. Make the necessary modifications to the code as requested.
3. Return ONLY the complete modified code.
4. Do not include any explanations, comments, or line numbers in your response.
5. Ensure the returned code is complete and can be directly used as a replacement for the original code.
6. Preserve the original structure, indentation, and formatting of the code as much as possible.
7. Do not omit any parts of the code, even if they are unchanged.
8. Maintain the SAME indentation in the returned code as in the source code
9. Do NOT include three backticks: ```
10. Only return code part, do NOT return the context part!

Remember: Your response should contain nothing but ONLY the modified code, ready to be used as a direct replacement for the original file.
]]

local group = api.nvim_create_augroup("avante_llm", { clear = true })
local active_job = nil

---@param question string
---@param code_lang string
---@param code_content string
---@param selected_content_content string | nil
---@param mode "planning" | "editing"
---@param on_chunk AvanteChunkParser
---@param on_complete AvanteCompleteParser
M.stream = function(question, code_lang, code_content, selected_content_content, mode, on_chunk, on_complete)
  mode = mode or "planning"
  local provider = Config.provider

  -- Check if the question contains an image path
  local image_path = nil
  local original_question = question
  if question:match("image: ") then
    local lines = vim.split(question, "\n")
    for i, line in ipairs(lines) do
      if line:match("^image: ") then
        image_path = line:gsub("^image: ", "")
        table.remove(lines, i)
        original_question = table.concat(lines, "\n")
        break
      end
    end
  end

  ---@type AvantePromptOptions
  local code_opts = {
    base_prompt = mode == "planning" and planning_mode_prompt or editing_mode_prompt,
    system_prompt = system_prompt,
    question = original_question,
    image_path = image_path,
    code_lang = code_lang,
    code_content = code_content,
    selected_code_content = selected_content_content,
  }

  ---@type string
  local current_event_state = nil

  ---@type AvanteProviderFunctor
  local Provider = P[provider]

  ---@type AvanteHandlerOptions
  local handler_opts = { on_chunk = on_chunk, on_complete = on_complete }
  ---@type AvanteCurlOutput
  local spec = Provider.parse_curl_args(Provider, code_opts)

  Utils.debug(spec)

  ---@param line string
  local function parse_stream_data(line)
    local event = line:match("^event: (.+)$")
    if event then
      current_event_state = event
      return
    end
    local data_match = line:match("^data: (.+)$")
    if data_match then
      Provider.parse_response(data_match, current_event_state, handler_opts)
    end
  end

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  local completed = false

  active_job = curl.post(spec.url, {
    headers = spec.headers,
    proxy = spec.proxy,
    insecure = spec.insecure,
    body = vim.json.encode(spec.body),
    stream = function(err, data, _)
      if err then
        completed = true
        on_complete(err)
        return
      end
      if not data then
        return
      end
      vim.schedule(function()
        if Config.options[provider] == nil and Provider.parse_stream_data ~= nil then
          if Provider.parse_response ~= nil then
            Utils.warn(
              "parse_stream_data and parse_response_data are mutually exclusive, and thus parse_response_data will be ignored. Make sure that you handle the incoming data correctly.",
              { once = true }
            )
          end
          Provider.parse_stream_data(data, handler_opts)
        else
          if Provider.parse_stream_data ~= nil then
            Provider.parse_stream_data(data, handler_opts)
          else
            parse_stream_data(data)
          end
        end
      end)
    end,
    on_error = function(err)
      completed = true
      on_complete(err)
    end,
    callback = function(result)
      if result.status >= 400 then
        if Provider.on_error then
          Provider.on_error(result)
        else
          Utils.error("API request failed with status " .. result.status, { once = true, title = "Avante" })
        end
        vim.schedule(function()
          if not completed then
            completed = true
            on_complete("API request failed with status " .. result.status .. ". Body: " .. vim.inspect(result.body))
          end
        end)
      end
      active_job = nil
    end,
  })

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = M.CANCEL_PATTERN,
    callback = function()
      if active_job then
        active_job:shutdown()
        Utils.debug("LLM request cancelled", { title = "Avante" })
        active_job = nil
      end
    end,
  })

  return active_job
end

return M
