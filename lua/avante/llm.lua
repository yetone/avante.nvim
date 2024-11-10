local api = vim.api
local fn = vim.fn
local uv = vim.uv

local curl = require("plenary.curl")

local Utils = require("avante.utils")
local Config = require("avante.config")
local Path = require("avante.path")
local P = require("avante.providers")

---@class avante.LLM
local M = {}

M.CANCEL_PATTERN = "AvanteLLMEscape"

------------------------------Prompt and type------------------------------

local group = api.nvim_create_augroup("avante_llm", { clear = true })

---@alias LlmMode "planning" | "editing" | "suggesting"
---
---@class TemplateOptions
---@field use_xml_format boolean
---@field ask boolean
---@field question string
---@field code_lang string
---@field file_content string
---@field selected_code string | nil
---@field project_context string | nil
---@field history_messages AvanteLLMMessage[]
---
---@class StreamOptions: TemplateOptions
---@field ask boolean
---@field bufnr integer
---@field instructions string
---@field mode LlmMode
---@field provider AvanteProviderFunctor | nil
---@field on_chunk AvanteChunkParser
---@field on_complete AvanteCompleteParser

---@param opts StreamOptions
M.stream = function(opts)
  local mode = opts.mode or "planning"
  ---@type AvanteProviderFunctor
  local Provider = opts.provider or P[Config.provider]
  local _, body_opts = P.parse_config(Provider)
  local max_tokens = body_opts.max_tokens or 4096

  -- Check if the instructions contains an image path
  local image_paths = {}
  local instructions = opts.instructions
  if opts.instructions:match("image: ") then
    local lines = vim.split(opts.instructions, "\n")
    for i, line in ipairs(lines) do
      if line:match("^image: ") then
        local image_path = line:gsub("^image: ", "")
        table.insert(image_paths, image_path)
        table.remove(lines, i)
      end
    end
    instructions = table.concat(lines, "\n")
  end

  Path.prompts.initialize(Path.prompts.get(opts.bufnr))

  local filepath = Utils.relative_path(api.nvim_buf_get_name(opts.bufnr))

  local template_opts = {
    use_xml_format = Provider.use_xml_format,
    ask = opts.ask, -- TODO: add mode without ask instruction
    code_lang = opts.code_lang,
    filepath = filepath,
    file_content = opts.file_content,
    selected_code = opts.selected_code,
    project_context = opts.project_context,
  }

  local system_prompt = Path.prompts.render_mode(mode, template_opts)

  ---@type AvanteLLMMessage[]
  local messages = {}

  if opts.project_context ~= nil and opts.project_context ~= "" and opts.project_context ~= "null" then
    local project_context = Path.prompts.render_file("_project.avanterules", template_opts)
    if project_context ~= "" then table.insert(messages, { role = "user", content = project_context }) end
  end

  local code_context = Path.prompts.render_file("_context.avanterules", template_opts)
  if code_context ~= "" then table.insert(messages, { role = "user", content = code_context }) end

  if opts.use_xml_format then
    table.insert(messages, { role = "user", content = string.format("<question>%s</question>", instructions) })
  else
    table.insert(messages, { role = "user", content = string.format("QUESTION:\n%s", instructions) })
  end

  local remaining_tokens = max_tokens - Utils.tokens.calculate_tokens(system_prompt)

  for _, message in ipairs(messages) do
    remaining_tokens = remaining_tokens - Utils.tokens.calculate_tokens(message.content)
  end

  if opts.history_messages then
    if Config.history.max_tokens > 0 then remaining_tokens = math.min(Config.history.max_tokens, remaining_tokens) end
    -- Traverse the history in reverse, keeping only the latest history until the remaining tokens are exhausted and the first message role is "user"
    local history_messages = {}
    for i = #opts.history_messages, 1, -1 do
      local message = opts.history_messages[i]
      local tokens = Utils.tokens.calculate_tokens(message.content)
      remaining_tokens = remaining_tokens - tokens
      if remaining_tokens > 0 then
        table.insert(history_messages, message)
      else
        break
      end
    end
    if #history_messages > 0 and history_messages[1].role == "assistant" then table.remove(history_messages, 1) end
    -- prepend the history messages to the messages table
    vim.iter(history_messages):each(function(msg) table.insert(messages, 1, msg) end)
  end

  ---@type AvantePromptOptions
  local code_opts = {
    system_prompt = system_prompt,
    messages = messages,
    image_paths = image_paths,
  }

  ---@type string
  local current_event_state = nil

  ---@type AvanteHandlerOptions
  local handler_opts = { on_chunk = opts.on_chunk, on_complete = opts.on_complete }
  ---@type AvanteCurlOutput
  local spec = Provider.parse_curl_args(Provider, code_opts)

  ---@param line string
  local function parse_stream_data(line)
    local event = line:match("^event: (.+)$")
    if event then
      current_event_state = event
      return
    end
    local data_match = line:match("^data: (.+)$")
    if data_match then Provider.parse_response(data_match, current_event_state, handler_opts) end
  end

  local function parse_response_without_stream(data)
    Provider.parse_response_without_stream(data, current_event_state, handler_opts)
  end

  local completed = false

  local active_job

  local curl_body_file = fn.tempname() .. ".json"
  local json_content = vim.json.encode(spec.body)
  fn.writefile(vim.split(json_content, "\n"), curl_body_file)

  Utils.debug("curl body file:", curl_body_file)

  local function cleanup()
    if Config.debug then return end
    vim.schedule(function() fn.delete(curl_body_file) end)
  end

  active_job = curl.post(spec.url, {
    headers = spec.headers,
    proxy = spec.proxy,
    insecure = spec.insecure,
    body = curl_body_file,
    stream = function(err, data, _)
      if err then
        completed = true
        opts.on_complete(err)
        return
      end
      if not data then return end
      vim.schedule(function()
        if Config.options[Config.provider] == nil and Provider.parse_stream_data ~= nil then
          if Provider.parse_response ~= nil then
            Utils.warn(
              "parse_stream_data and parse_response are mutually exclusive, and thus parse_response will be ignored. Make sure that you handle the incoming data correctly.",
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
      if err.exit == 23 then
        local xdg_runtime_dir = os.getenv("XDG_RUNTIME_DIR")
        if not xdg_runtime_dir or fn.isdirectory(xdg_runtime_dir) == 0 then
          Utils.error(
            "$XDG_RUNTIME_DIR="
              .. xdg_runtime_dir
              .. " is set but does not exist. curl could not write output. Please make sure it exists, or unset.",
            { title = "Avante" }
          )
        elseif not uv.fs_access(xdg_runtime_dir, "w") then
          Utils.error(
            "$XDG_RUNTIME_DIR="
              .. xdg_runtime_dir
              .. " exists but is not writable. curl could not write output. Please make sure it is writable, or unset.",
            { title = "Avante" }
          )
        end
      end
      active_job = nil
      completed = true
      cleanup()
      opts.on_complete(nil)
    end,
    callback = function(result)
      active_job = nil
      cleanup()
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

      -- If stream is not enabled, then handle the response here
      if spec.body.stream == false and result.status == 200 then
        vim.schedule(function()
          completed = true
          parse_response_without_stream(result.body)
        end)
      end
    end,
  })

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = M.CANCEL_PATTERN,
    once = true,
    callback = function()
      -- Error: cannot resume dead coroutine
      if active_job then
        xpcall(function() active_job:shutdown() end, function(err) return err end)
        Utils.debug("LLM request cancelled")
        active_job = nil
      end
    end,
  })

  return active_job
end

function M.cancel_inflight_request() api.nvim_exec_autocmds("User", { pattern = M.CANCEL_PATTERN }) end

return M
