local api = vim.api

local curl = require("plenary.curl")

local Utils = require("avante.utils")
local Config = require("avante.config")
local P = require("avante.providers")

---@class avante.LLM
local M = {}

M.CANCEL_PATTERN = "AvanteLLMEscape"

------------------------------Prompt and type------------------------------

-- Copy from: https://github.com/Doriandarko/claude-engineer/blob/15c94963cbf9d01b8ae7bbb5d42d7025aa0555d5/main.py#L276
---@alias AvanteBasePrompt string
local planning_mode_system_prompt_tpl = [[
You are an AI coding agent that generates code according to the instructions. Follow these steps:

1. Review the entire file content to understand the context:
${file_content}

2. Carefully analyze the selected code:
${selected_code}

3. Carefully analyze the specific instructions:
${instructions}

4. Take into account the overall project context:
${project_context}

5. Consider the memory of previous edits:
${memory_context}

6. Consider the full context of all files in the project:
${full_file_contents_context}

7. Generate SEARCH/REPLACE blocks for each necessary change. Each block should:
   - Include enough context to uniquely identify the code to be changed
   - Provide the exact replacement code, maintaining correct INDENTATION and FORMATTING
   - Focus on specific, targeted changes rather than large, sweeping modifications
   - The content in the SEARCH tag MUST NOT contain any of your generated content
   - The content in the SEARCH tag MUST be based on the original content of the source file
   - The content in the SEARCH tag needs to ensure a certain context to guarantee its UNIQUENESS
   - The content in the REPLACE tag should also correspond to the context of the SEARCH tag
   - There should be NO OVERLAP between the code of each SEARCH tag.
   - DO NOT use ``` to wrap code blocks

8. Ensure that your SEARCH/REPLACE blocks:
   - Address all relevant aspects of the instructions
   - Maintain or enhance code readability and efficiency
   - Consider the overall structure and purpose of the code
   - Follow best practices and coding standards for the language
   - Maintain consistency with the project context and previous edits
   - Take into account the full context of all files in the project

IMPORTANT: MUST TO ADD EXPLANATIONS BEFORE AND AFTER EACH SEARCH/REPLACE BLOCK.
USE THE FOLLOWING FORMAT FOR EACH BLOCK:

<SEARCH>
Code to be replaced
</SEARCH>
<REPLACE>
New code to insert
</REPLACE>

If no changes are needed, return an empty list.
]]

local editing_mode_system_prompt_tpl = [[
You are an AI coding agent that generates code according to the instructions. Follow these steps:

1. Review the entire file content to understand the context:
${file_content}

2. Carefully analyze the selected code:
${selected_code}

3. Carefully analyze the specific instructions:
${instructions}

4. Take into account the overall project context:
${project_context}

5. Consider the memory of previous edits:
${memory_context}

6. Consider the full context of all files in the project:
${full_file_contents_context}

7. Return ONLY the complete modified code.

8. Do not include any explanations, comments, or line numbers in your response.

9. Ensure the returned code is complete and can be directly used as a replacement for the original code.

11. Preserve the original structure, indentation, and formatting of the code as much as possible.

12. Do not omit any parts of the code, even if they are unchanged.

13. Maintain the SAME indentation in the returned code as in the source code

14. Do NOT include three backticks: ```

15. Only return code part, do NOT return the context part!

Remember: Your response should contain nothing but ONLY the modified code, ready to be used as a direct replacement for the original file.
]]

local group = api.nvim_create_augroup("avante_llm", { clear = true })
local active_job = nil

---@class StreamOptions
---@field file_content string
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

  local system_prompt_tpl = mode == "planning" and planning_mode_system_prompt_tpl or editing_mode_system_prompt_tpl

  -- Check if the question contains an image path
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

  local system_prompt =
    system_prompt_tpl:gsub("%${(.-)}", vim.tbl_deep_extend("force", opts, { instructions = original_instructions }))

  ---@type AvantePromptOptions
  local code_opts = {
    system_prompt = system_prompt,
    user_prompt = opts.selected_code and "Please suggest modifications to the selected code."
      or "Please suggest modifications to the file coontent.",
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
