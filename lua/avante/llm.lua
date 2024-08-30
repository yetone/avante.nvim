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
local default_system_prompt = [[
You are an excellent programming expert.
]]

-- Copy from: https://github.com/Doriandarko/claude-engineer/blob/15c94963cbf9d01b8ae7bbb5d42d7025aa0555d5/main.py#L276
---@alias AvanteBasePrompt string
local planning_mode_user_prompt_tpl = [[
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
   - DO NOT return the complete modified code with applied changes!

Remember: Accurate line numbers are CRITICAL. The range start_line to end_line must include ALL lines to be replaced, from the very first to the very last. Double-check every range before finalizing your response, paying special attention to the start_line to ensure it hasn't shifted down. Ensure that your line numbers perfectly match the original code structure without any overall shift.
]]

local editing_mode_user_prompt_tpl = [[
Your task is to modify the provided code according to the user's request. Follow these instructions precisely:

1. Return ONLY the complete modified code.

2. Do not include any explanations, comments, or line numbers in your response.

3. Ensure the returned code is complete and can be directly used as a replacement for the original code.

4. Preserve the original structure, indentation, and formatting of the code as much as possible.

5. Do not omit any parts of the code, even if they are unchanged.

6. Maintain the SAME indentation in the returned code as in the source code

7. Do NOT include three backticks: ```

8. Only return the new code snippets to be updated, DO NOT return the entire file content.

Remember: Your response should contain nothing but ONLY the modified code, ready to be used as a direct replacement for the original file.
]]

local group = api.nvim_create_augroup("avante_llm", { clear = true })
local active_job = nil

---@class StreamOptions
---@field file_content string
---@field code_lang string
---@field selected_code string | nil
---@field instructions string
---@field project_context string | nil
---@field memory_context string | nil
---@field full_file_contents_context string | nil
---@field mode "planning" | "editing"
---@field on_chunk AvanteChunkParser
---@field on_complete AvanteCompleteParser

---@param opts StreamOptions
M.stream = function(opts)
  local mode = opts.mode or "planning"
  local provider = Config.provider

  local system_prompt = Config.llm.system_prompt or default_system_prompt
  local user_prompt_tpl = mode == "planning"
      and (Config.llm.planning_mode_user_prompt_tpl or planning_mode_user_prompt_tpl)
    or (Config.llm.editing_mode_user_prompt_tpl or editing_mode_user_prompt_tpl)

  -- Check if the instructions contains an image path
  local image_paths = {}
  local original_instructions = opts.instructions
  if opts.instructions:match("image: ") then
    local lines = vim.split(opts.instructions, "\n")
    for i, line in ipairs(lines) do
      if line:match("^image: ") then
        local image_path = line:gsub("^image: ", "")
        table.insert(image_paths, image_path)
        table.remove(lines, i)
      end
    end
    original_instructions = table.concat(lines, "\n")
  end

  local user_prompts = {}

  if opts.selected_code and opts.selected_code ~= "" then
    table.insert(
      user_prompts,
      string.format("<code_context>```%s\n%s\n```</code_context>", opts.code_lang, opts.file_content)
    )
    table.insert(user_prompts, string.format("<code>```%s\n%s\n```</code>", opts.code_lang, opts.selected_code))
  else
    table.insert(user_prompts, string.format("<code>```%s\n%s\n```</code>", opts.code_lang, opts.file_content))
  end

  if opts.project_context then
    table.insert(user_prompts, string.format("<project_context>%s</project_context>", opts.project_context))
  end

  if opts.memory_context then
    table.insert(user_prompts, string.format("<memory_context>%s</memory_context>", opts.memory_context))
  end

  if opts.full_file_contents_context then
    table.insert(
      user_prompts,
      string.format("<full_file_contents_context>%s</full_file_contents_context>", opts.full_file_contents_context)
    )
  end

  table.insert(user_prompts, "<question>" .. original_instructions .. "</question>")

  local user_prompt = user_prompt_tpl:gsub("%${(.-)}", opts)

  table.insert(user_prompts, user_prompt)

  ---@type AvantePromptOptions
  local code_opts = {
    system_prompt = system_prompt,
    user_prompts = user_prompts,
    image_paths = image_paths,
  }

  ---@type string
  local current_event_state = nil

  ---@type AvanteProviderFunctor
  local Provider = P[provider]

  ---@type AvanteHandlerOptions
  local handler_opts = { on_chunk = opts.on_chunk, on_complete = opts.on_complete }
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
        opts.on_complete(err)
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
      opts.on_complete(err)
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
            opts.on_complete(
              "API request failed with status " .. result.status .. ". Body: " .. vim.inspect(result.body)
            )
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
