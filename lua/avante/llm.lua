local api = vim.api
local fn = vim.fn
local uv = vim.uv

local curl = require("plenary.curl")

local Utils = require("avante.utils")
local Config = require("avante.config")
local Path = require("avante.path")
local Providers = require("avante.providers")
local LLMTools = require("avante.llm_tools")

---@class avante.LLM
local M = {}

M.CANCEL_PATTERN = "AvanteLLMEscape"

------------------------------Prompt and type------------------------------

local group = api.nvim_create_augroup("avante_llm", { clear = true })

---@param opts AvanteGeneratePromptsOptions
---@return AvantePromptOptions
function M.generate_prompts(opts)
  local provider = opts.provider or Providers[Config.provider]
  local mode = opts.mode or "planning"
  ---@type AvanteProviderFunctor | AvanteBedrockProviderFunctor
  local _, request_body = Providers.parse_config(provider)
  local max_tokens = request_body.max_tokens or 4096

  -- Check if the instructions contains an image path
  local image_paths = {}
  local instructions = opts.instructions
  if instructions and instructions:match("image: ") then
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

  local project_root = Utils.root.get()
  Path.prompts.initialize(Path.prompts.get_templates_dir(project_root))

  local system_info = Utils.get_system_info()

  local template_opts = {
    use_xml_format = provider.use_xml_format,
    ask = opts.ask, -- TODO: add mode without ask instruction
    code_lang = opts.code_lang,
    selected_files = opts.selected_files,
    selected_code = opts.selected_code,
    project_context = opts.project_context,
    diagnostics = opts.diagnostics,
    system_info = system_info,
    model_name = provider.model or "unknown",
  }

  local system_prompt = Path.prompts.render_mode(mode, template_opts)

  ---@type AvanteLLMMessage[]
  local messages = {}

  if opts.project_context ~= nil and opts.project_context ~= "" and opts.project_context ~= "null" then
    local project_context = Path.prompts.render_file("_project.avanterules", template_opts)
    if project_context ~= "" then
      table.insert(messages, { role = "user", content = { { type = "text", text = project_context } } })
    end
  end

  if opts.diagnostics ~= nil and opts.diagnostics ~= "" and opts.diagnostics ~= "null" then
    local diagnostics = Path.prompts.render_file("_diagnostics.avanterules", template_opts)
    if diagnostics ~= "" then
      table.insert(messages, { role = "user", content = { { type = "text", text = diagnostics } } })
    end
  end

  if (opts.selected_files and #opts.selected_files > 0 or false) or opts.selected_code ~= nil then
    local code_context = Path.prompts.render_file("_context.avanterules", template_opts)
    if code_context ~= "" then
      table.insert(messages, { role = "user", content = { { type = "text", text = code_context } } })
    end
  end

  if instructions then
    if opts.use_xml_format then
      table.insert(messages, {
        role = "user",
        content = { { type = "text", text = string.format("<question>%s</question>", instructions) } },
      })
    else
      table.insert(
        messages,
        { role = "user", content = { { type = "text", text = string.format("QUESTION:\n%s", instructions) } } }
      )
    end
  end

  local remaining_tokens = max_tokens - Utils.tokens.calculate_tokens(system_prompt)

  for _, message in ipairs(messages) do
    remaining_tokens = remaining_tokens - Utils.tokens.calculate_message_content_tokens(message.content)
  end

  if opts.history_messages then
    if Config.history.max_tokens > 0 then remaining_tokens = math.min(Config.history.max_tokens, remaining_tokens) end
    -- Traverse the history in reverse, keeping only the latest history until the remaining tokens are exhausted and the first message role is "user"
    local history_messages = {}
    for i = #opts.history_messages, 1, -1 do
      local message = opts.history_messages[i]
      local tokens = Utils.tokens.calculate_message_content_tokens(message.content)
      remaining_tokens = remaining_tokens - tokens
      if remaining_tokens > 0 then
        table.insert(history_messages, message)
      else
        break
      end
    end
    -- prepend the history messages to the messages table
    vim.iter(history_messages):each(function(msg) table.insert(messages, 1, msg) end)
    if #messages > 0 and messages[1].role == "assistant" then table.remove(messages, 1) end
  end

  if opts.mode == "cursor-applying" then
    local user_prompt = [[
Merge all changes from the <update> snippet into the <code> below.
- Preserve the code's structure, order, comments, and indentation exactly.
- Output only the updated code, enclosed within <updated-code> and </updated-code> tags.
- Do not include any additional text, explanations, placeholders, ellipses, or code fences.

]]
    user_prompt = user_prompt .. string.format("<code>\n%s\n</code>\n", opts.original_code)
    for _, snippet in ipairs(opts.update_snippets) do
      user_prompt = user_prompt .. string.format("<update>\n%s\n</update>\n", snippet)
    end
    user_prompt = user_prompt .. "Provide the complete updated code."
    table.insert(messages, { role = "user", content = { { type = "text", text = user_prompt } } })
  end

  ---@type AvantePromptOptions
  return {
    system_prompt = system_prompt,
    messages = messages,
    image_paths = image_paths,
    tools = opts.tools,
    tool_histories = opts.tool_histories,
  }
end

---@param opts AvanteGeneratePromptsOptions
---@return integer
function M.calculate_tokens(opts)
  local prompt_opts = M.generate_prompts(opts)
  local tokens = Utils.tokens.calculate_tokens(prompt_opts.system_prompt)
  for _, message in ipairs(prompt_opts.messages) do
    tokens = tokens + Utils.tokens.calculate_message_content_tokens(message.content)
  end
  return tokens
end

---@param opts AvanteLLMStreamOptions
function M._stream(opts)
  local provider = opts.provider or Providers[Config.provider]

  local prompt_opts = M.generate_prompts(opts)

  ---@type string
  local current_event_state = nil

  ---@type AvanteHandlerOptions
  local handler_opts = {
    on_start = opts.on_start,
    on_chunk = opts.on_chunk,
    on_stop = function(stop_opts)
      ---@param tool_use_list AvanteLLMToolUse[]
      ---@param tool_use_index integer
      ---@param tool_histories AvanteLLMToolHistory[]
      local function handle_next_tool_use(tool_use_list, tool_use_index, tool_histories)
        if tool_use_index > #tool_use_list then
          local new_opts = vim.tbl_deep_extend("force", opts, {
            tool_histories = tool_histories,
          })
          return M._stream(new_opts)
        end
        local tool_use = tool_use_list[tool_use_index]
        ---@param result string | nil
        ---@param error string | nil
        local function handle_tool_result(result, error)
          local tool_result = {
            tool_use_id = tool_use.id,
            content = error ~= nil and error or result,
            is_error = error ~= nil,
          }
          table.insert(tool_histories, { tool_result = tool_result, tool_use = tool_use })
          return handle_next_tool_use(tool_use_list, tool_use_index + 1, tool_histories)
        end
        -- Either on_complete handles the tool result asynchronously or we receive the result and error synchronously when either is not nil
        local result, error = LLMTools.process_tool_use(opts.tools, tool_use, opts.on_tool_log, handle_tool_result)
        if result ~= nil or error ~= nil then return handle_tool_result(result, error) end
      end
      if stop_opts.reason == "tool_use" and stop_opts.tool_use_list then
        local old_tool_histories = vim.deepcopy(opts.tool_histories) or {}
        local sorted_tool_use_list = {} ---@type AvanteLLMToolUse[]
        for _, tool_use in vim.spairs(stop_opts.tool_use_list) do
          table.insert(sorted_tool_use_list, tool_use)
        end
        return handle_next_tool_use(sorted_tool_use_list, 1, old_tool_histories)
      end
      if stop_opts.reason == "rate_limit" then
        local msg = "Rate limit reached. Retrying in " .. stop_opts.retry_after .. " seconds ..."
        opts.on_chunk("\n*[" .. msg .. "]*\n")
        local timer = vim.loop.new_timer()
        if timer then
          local retry_after = stop_opts.retry_after
          local function countdown()
            timer:start(
              1000,
              0,
              vim.schedule_wrap(function()
                if retry_after > 0 then retry_after = retry_after - 1 end
                local msg_ = "Rate limit reached. Retrying in " .. retry_after .. " seconds ..."
                opts.on_chunk([[\033[1A\033[K]] .. "\n*[" .. msg_ .. "]*\n")
                countdown()
              end)
            )
          end
          countdown()
        end
        Utils.info("Rate limit reached. Retrying in " .. stop_opts.retry_after .. " seconds", { title = "Avante" })
        vim.defer_fn(function()
          if timer then timer:stop() end
          M._stream(opts)
        end, stop_opts.retry_after * 1000)
        return
      end
      return opts.on_stop(stop_opts)
    end,
  }

  ---@type AvanteCurlOutput
  local spec = provider.parse_curl_args(provider, prompt_opts)

  local resp_ctx = {}

  ---@param line string
  local function parse_stream_data(line)
    local event = line:match("^event: (.+)$")
    if event then
      current_event_state = event
      return
    end
    local data_match = line:match("^data: (.+)$")
    if data_match then provider.parse_response(resp_ctx, data_match, current_event_state, handler_opts) end
  end

  local function parse_response_without_stream(data)
    provider.parse_response_without_stream(data, current_event_state, handler_opts)
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
    raw = spec.rawArgs,
    stream = function(err, data, _)
      if err then
        completed = true
        handler_opts.on_stop({ reason = "error", error = err })
        return
      end
      if not data then return end
      vim.schedule(function()
        if Config[Config.provider] == nil and provider.parse_stream_data ~= nil then
          if provider.parse_response ~= nil then
            Utils.warn(
              "parse_stream_data and parse_response are mutually exclusive, and thus parse_response will be ignored. Make sure that you handle the incoming data correctly.",
              { once = true }
            )
          end
          provider.parse_stream_data(data, handler_opts)
        else
          if provider.parse_stream_data ~= nil then
            provider.parse_stream_data(data, handler_opts)
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
      handler_opts.on_stop({ reason = "error", error = err })
    end,
    callback = function(result)
      active_job = nil
      cleanup()
      if result.status >= 400 then
        if provider.on_error then
          provider.on_error(result)
        else
          Utils.error("API request failed with status " .. result.status, { once = true, title = "Avante" })
        end
        if result.status == 429 then
          local headers_map = vim.iter(result.headers):fold({}, function(acc, value)
            local pieces = vim.split(value, ":")
            local key = pieces[1]
            local remain = vim.list_slice(pieces, 2)
            if not remain then return acc end
            local val = Utils.trim_spaces(table.concat(remain, ":"))
            acc[key] = val
            return acc
          end)
          local retry_after = 10
          if headers_map["retry-after"] then retry_after = tonumber(headers_map["retry-after"]) or 10 end
          handler_opts.on_stop({ reason = "rate_limit", retry_after = retry_after })
          return
        end
        vim.schedule(function()
          if not completed then
            completed = true
            handler_opts.on_stop({
              reason = "error",
              error = "API request failed with status " .. result.status .. ". Body: " .. vim.inspect(result.body),
            })
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

local function _merge_response(first_response, second_response, opts)
  local prompt = "\n" .. Config.dual_boost.prompt
  prompt = prompt
    :gsub("{{[%s]*provider1_output[%s]*}}", function() return first_response end)
    :gsub("{{[%s]*provider2_output[%s]*}}", function() return second_response end)

  prompt = prompt .. "\n"

  -- append this reference prompt to the prompt_opts messages at last
  opts.instructions = opts.instructions .. prompt

  M._stream(opts)
end

local function _collector_process_responses(collector, opts)
  if not collector[1] or not collector[2] then
    Utils.error("One or both responses failed to complete")
    return
  end
  _merge_response(collector[1], collector[2], opts)
end

local function _collector_add_response(collector, index, response, opts)
  collector[index] = response
  collector.count = collector.count + 1

  if collector.count == 2 then
    collector.timer:stop()
    _collector_process_responses(collector, opts)
  end
end

function M._dual_boost_stream(opts, Provider1, Provider2)
  Utils.debug("Starting Dual Boost Stream")

  local collector = {
    count = 0,
    responses = {},
    timer = uv.new_timer(),
    timeout_ms = Config.dual_boost.timeout,
  }

  -- Setup timeout
  collector.timer:start(
    collector.timeout_ms,
    0,
    vim.schedule_wrap(function()
      if collector.count < 2 then
        Utils.warn("Dual boost stream timeout reached")
        collector.timer:stop()
        -- Process whatever responses we have
        _collector_process_responses(collector, opts)
      end
    end)
  )

  -- Create options for both streams
  local function create_stream_opts(index)
    local response = ""
    return vim.tbl_extend("force", opts, {
      on_chunk = function(chunk)
        if chunk then response = response .. chunk end
      end,
      on_stop = function(stop_opts)
        if stop_opts.error then
          Utils.error(string.format("Stream %d failed: %s", index, stop_opts.error))
          return
        end
        Utils.debug(string.format("Response %d completed", index))
        _collector_add_response(collector, index, response, opts)
      end,
    })
  end

  -- Start both streams
  local success, err = xpcall(function()
    local opts1 = create_stream_opts(1)
    opts1.provider = Provider1
    M._stream(opts1)
    local opts2 = create_stream_opts(2)
    opts2.provider = Provider2
    M._stream(opts2)
  end, function(err) return err end)
  if not success then Utils.error("Failed to start dual_boost streams: " .. tostring(err)) end
end

---@param opts AvanteLLMStreamOptions
function M.stream(opts)
  local is_completed = false
  if opts.on_tool_log ~= nil then
    local original_on_tool_log = opts.on_tool_log
    opts.on_tool_log = vim.schedule_wrap(function(tool_name, log)
      if not original_on_tool_log then return end
      return original_on_tool_log(tool_name, log)
    end)
  end
  if opts.on_chunk ~= nil then
    local original_on_chunk = opts.on_chunk
    opts.on_chunk = vim.schedule_wrap(function(chunk)
      if is_completed then return end
      return original_on_chunk(chunk)
    end)
  end
  if opts.on_stop ~= nil then
    local original_on_stop = opts.on_stop
    opts.on_stop = vim.schedule_wrap(function(stop_opts)
      if is_completed then return end
      if stop_opts.reason == "complete" or stop_opts.reason == "error" then is_completed = true end
      return original_on_stop(stop_opts)
    end)
  end

  local valid_dual_boost_modes = {
    planning = true,
    ["cursor-planning"] = true,
  }

  opts.mode = opts.mode or "planning"

  if Config.dual_boost.enabled and valid_dual_boost_modes[opts.mode] then
    M._dual_boost_stream(
      opts,
      Providers[Config.dual_boost.first_provider],
      Providers[Config.dual_boost.second_provider]
    )
  else
    M._stream(opts)
  end
end

function M.cancel_inflight_request() api.nvim_exec_autocmds("User", { pattern = M.CANCEL_PATTERN }) end

return M
