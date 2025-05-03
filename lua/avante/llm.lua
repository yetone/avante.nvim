local api = vim.api
local fn = vim.fn
local uv = vim.uv

local curl = require("plenary.curl")

local Utils = require("avante.utils")
local Config = require("avante.config")
local Path = require("avante.path")
local Providers = require("avante.providers")
local LLMToolHelpers = require("avante.llm_tools.helpers")
local LLMTools = require("avante.llm_tools")
local HistoryMessage = require("avante.history_message")

---@class avante.LLM
local M = {}

M.CANCEL_PATTERN = "AvanteLLMEscape"

------------------------------Prompt and type------------------------------

local group = api.nvim_create_augroup("avante_llm", { clear = true })

---@param content AvanteLLMMessageContent
---@param cb fun(title: string | nil): nil
function M.summarize_chat_thread_title(content, cb)
  local system_prompt =
    [[Summarize the content as a title for the chat thread. The title should be a concise and informative summary of the conversation, capturing the main points and key takeaways. It should be no longer than 100 words and should be written in a clear and engaging style. The title should be suitable for use as the title of a chat thread on a messaging platform or other communication medium.]]
  local response_content = ""
  local provider = Providers.get_memory_summary_provider()
  M.curl({
    provider = provider,
    prompt_opts = {
      system_prompt = system_prompt,
      messages = {
        { role = "user", content = content },
      },
    },
    handler_opts = {
      on_start = function(_) end,
      on_chunk = function(chunk)
        if not chunk then return end
        response_content = response_content .. chunk
      end,
      on_stop = function(stop_opts)
        if stop_opts.error ~= nil then
          Utils.error(string.format("summarize chat thread title failed: %s", vim.inspect(stop_opts.error)))
          return
        end
        if stop_opts.reason == "complete" then
          response_content = Utils.trim_think_content(response_content)
          response_content = Utils.trim(response_content, { prefix = "\n", suffix = "\n" })
          response_content = Utils.trim(response_content, { prefix = '"', suffix = '"' })
          local title = response_content
          cb(title)
        end
      end,
    },
  })
end

---@param prev_memory string | nil
---@param history_messages avante.HistoryMessage[]
---@param cb fun(memory: avante.ChatMemory | nil): nil
function M.summarize_memory(prev_memory, history_messages, cb)
  local system_prompt =
    [[You are an expert coding assistant. Your goal is to generate a concise, structured summary of the conversation below that captures all essential information needed to continue development after context replacement. Include tasks performed, code areas modified or reviewed, key decisions or assumptions, test results or errors, and outstanding tasks or next steps.]]
  if #history_messages == 0 then
    cb(nil)
    return
  end
  local latest_timestamp = history_messages[#history_messages].timestamp
  local latest_message_uuid = history_messages[#history_messages].uuid
  local conversation_items = vim
    .iter(history_messages)
    :filter(function(msg)
      if msg.just_for_display then return false end
      if msg.message.role ~= "assistant" and msg.message.role ~= "user" then return false end
      local content = msg.message.content
      if type(content) == "table" and content[1].type == "tool_result" then return false end
      if type(content) == "table" and content[1].type == "tool_use" then return false end
      return true
    end)
    :map(function(msg) return msg.message.role .. ": " .. Utils.message_to_text(msg, history_messages) end)
    :totable()
  local conversation_text = table.concat(conversation_items, "\n")
  local user_prompt = "Here is the conversation so far:\n"
    .. conversation_text
    .. "\n\nPlease summarize this conversation, covering:\n1. Tasks performed and outcomes\n2. Code files, modules, or functions modified or examined\n3. Important decisions or assumptions made\n4. Errors encountered and test or build results\n5. Remaining tasks, open questions, or next steps\nProvide the summary in a clear, concise format."
  if prev_memory then user_prompt = user_prompt .. "\n\nThe previous summary is:\n\n" .. prev_memory end
  local messages = {
    {
      role = "user",
      content = user_prompt,
    },
  }
  local response_content = ""
  local provider = Providers.get_memory_summary_provider()
  M.curl({
    provider = provider,
    prompt_opts = {
      system_prompt = system_prompt,
      messages = messages,
    },
    handler_opts = {
      on_start = function(_) end,
      on_chunk = function(chunk)
        if not chunk then return end
        response_content = response_content .. chunk
      end,
      on_stop = function(stop_opts)
        if stop_opts.error ~= nil then
          Utils.error(string.format("summarize memory failed: %s", vim.inspect(stop_opts.error)))
          return
        end
        if stop_opts.reason == "complete" then
          response_content = Utils.trim_think_content(response_content)
          local memory = {
            content = response_content,
            last_summarized_timestamp = latest_timestamp,
            last_message_uuid = latest_message_uuid,
          }
          cb(memory)
        else
          cb(nil)
        end
      end,
    },
  })
end

---@param opts AvanteGeneratePromptsOptions
---@return AvantePromptOptions
function M.generate_prompts(opts)
  local provider = opts.provider or Providers[Config.provider]
  local mode = opts.mode or Config.mode
  ---@type AvanteProviderFunctor | AvanteBedrockProviderFunctor
  local _, request_body = Providers.parse_config(provider)
  local max_tokens = request_body.max_tokens or 4096

  -- Check if the instructions contains an image path
  local image_paths = {}
  if opts.prompt_opts and opts.prompt_opts.image_paths then
    image_paths = vim.list_extend(image_paths, opts.prompt_opts.image_paths)
  end

  local project_root = Utils.root.get()
  Path.prompts.initialize(Path.prompts.get_templates_dir(project_root))

  local tool_id_to_tool_name = {}
  local tool_id_to_path = {}
  local viewed_files = {}
  if opts.history_messages then
    for _, message in ipairs(opts.history_messages) do
      local content = message.message.content
      if type(content) ~= "table" then goto continue end
      for _, item in ipairs(content) do
        if type(item) ~= "table" then goto continue1 end
        if item.type ~= "tool_use" then goto continue1 end
        local tool_name = item.name
        if tool_name ~= "view" then goto continue1 end
        local path = item.input.path
        tool_id_to_tool_name[item.id] = tool_name
        if path then
          local uniform_path = Utils.uniform_path(path)
          tool_id_to_path[item.id] = uniform_path
          viewed_files[uniform_path] = item.id
        end
        ::continue1::
      end
      ::continue::
    end
    for _, message in ipairs(opts.history_messages) do
      local content = message.message.content
      if type(content) == "table" then
        for _, item in ipairs(content) do
          if type(item) ~= "table" then goto continue end
          if item.type ~= "tool_result" then goto continue end
          local tool_name = tool_id_to_tool_name[item.tool_use_id]
          if tool_name ~= "view" then goto continue end
          local path = tool_id_to_path[item.tool_use_id]
          local latest_tool_id = viewed_files[path]
          if not latest_tool_id then goto continue end
          if latest_tool_id ~= item.tool_use_id then
            item.content =
              string.format("The file %s has been updated. Please use the latest `view` tool result!", path)
          else
            local lines, error = Utils.read_file_from_buf_or_disk(path)
            if error ~= nil then Utils.error("error reading file: " .. error) end
            lines = lines or {}
            item.content = table.concat(lines, "\n")
          end
          ::continue::
        end
      end
    end
  end

  local system_info = Utils.get_system_info()

  local selected_files = opts.selected_files or {}

  if opts.selected_filepaths then
    for _, filepath in ipairs(opts.selected_filepaths) do
      local lines, error = Utils.read_file_from_buf_or_disk(filepath)
      lines = lines or {}
      local filetype = Utils.get_filetype(filepath)
      if error ~= nil then
        Utils.error("error reading file: " .. error)
      else
        local content = table.concat(lines, "\n")
        table.insert(selected_files, { path = filepath, content = content, file_type = filetype })
      end
    end
  end

  selected_files = vim.iter(selected_files):filter(function(file) return viewed_files[file.path] == nil end):totable()

  local template_opts = {
    ask = opts.ask, -- TODO: add mode without ask instruction
    code_lang = opts.code_lang,
    selected_files = selected_files,
    selected_code = opts.selected_code,
    recently_viewed_files = opts.recently_viewed_files,
    project_context = opts.project_context,
    diagnostics = opts.diagnostics,
    system_info = system_info,
    model_name = provider.model or "unknown",
    memory = opts.memory,
  }

  local system_prompt
  if opts.prompt_opts and opts.prompt_opts.system_prompt then
    system_prompt = opts.prompt_opts.system_prompt
  else
    system_prompt = Path.prompts.render_mode(mode, template_opts)
  end

  if Config.system_prompt ~= nil then
    local custom_system_prompt = Config.system_prompt
    if type(custom_system_prompt) == "function" then custom_system_prompt = custom_system_prompt() end
    if custom_system_prompt ~= nil and custom_system_prompt ~= "" and custom_system_prompt ~= "null" then
      system_prompt = system_prompt .. "\n\n" .. custom_system_prompt
    end
  end

  ---@type AvanteLLMMessage[]
  local context_messages = {}
  if opts.prompt_opts and opts.prompt_opts.messages then
    context_messages = vim.list_extend(context_messages, opts.prompt_opts.messages)
  end

  if opts.project_context ~= nil and opts.project_context ~= "" and opts.project_context ~= "null" then
    local project_context = Path.prompts.render_file("_project.avanterules", template_opts)
    if project_context ~= "" then
      table.insert(context_messages, { role = "user", content = project_context, visible = false, is_context = true })
    end
  end

  if opts.diagnostics ~= nil and opts.diagnostics ~= "" and opts.diagnostics ~= "null" then
    local diagnostics = Path.prompts.render_file("_diagnostics.avanterules", template_opts)
    if diagnostics ~= "" then
      table.insert(context_messages, { role = "user", content = diagnostics, visible = false, is_context = true })
    end
  end

  if #selected_files > 0 or opts.selected_code ~= nil then
    local code_context = Path.prompts.render_file("_context.avanterules", template_opts)
    if code_context ~= "" then
      table.insert(context_messages, { role = "user", content = code_context, visible = false, is_context = true })
    end
  end

  if opts.memory ~= nil and opts.memory ~= "" and opts.memory ~= "null" then
    local memory = Path.prompts.render_file("_memory.avanterules", template_opts)
    if memory ~= "" then
      table.insert(context_messages, { role = "user", content = memory, visible = false, is_context = true })
    end
  end

  local remaining_tokens = max_tokens - Utils.tokens.calculate_tokens(system_prompt)

  for _, message in ipairs(context_messages) do
    remaining_tokens = remaining_tokens - Utils.tokens.calculate_tokens(message.content)
  end

  local dropped_history_messages = {}
  if opts.prompt_opts and opts.prompt_opts.dropped_history_messages then
    dropped_history_messages = vim.list_extend(dropped_history_messages, opts.prompt_opts.dropped_history_messages)
  end

  local cleaned_history_messages = opts.history_messages

  local final_history_messages = {}
  if cleaned_history_messages then
    if opts.disable_compact_history_messages then
      final_history_messages = vim.list_extend(final_history_messages, cleaned_history_messages)
    else
      if Config.history.max_tokens > 0 then
        remaining_tokens = math.min(Config.history.max_tokens, remaining_tokens)
      end
      -- Traverse the history in reverse, keeping only the latest history until the remaining tokens are exhausted and the first message role is "user"
      local history_messages = {}
      for i = #cleaned_history_messages, 1, -1 do
        local message = cleaned_history_messages[i]
        local tokens = Utils.tokens.calculate_tokens(message.message.content)
        remaining_tokens = remaining_tokens - tokens
        if remaining_tokens > 0 then
          table.insert(history_messages, 1, message)
        else
          break
        end
      end

      if #history_messages == 0 then
        history_messages =
          vim.list_slice(cleaned_history_messages, #cleaned_history_messages - 1, #cleaned_history_messages)
      end

      dropped_history_messages =
        vim.list_slice(cleaned_history_messages, 1, #cleaned_history_messages - #history_messages)

      -- prepend the history messages to the messages table
      vim.iter(history_messages):each(function(msg) table.insert(final_history_messages, msg) end)
    end
  end

  -- Utils.debug("opts.history_messages", opts.history_messages)
  -- Utils.debug("final_history_messages", final_history_messages)

  ---@type AvanteLLMMessage[]
  local messages = vim.deepcopy(context_messages)
  for _, msg in ipairs(final_history_messages) do
    local message = msg.message
    table.insert(messages, message)
  end

  messages = vim
    .iter(messages)
    :filter(function(msg) return type(msg.content) ~= "string" or msg.content ~= "" end)
    :totable()

  if opts.instructions ~= nil and opts.instructions ~= "" then
    messages = vim.list_extend(messages, { { role = "user", content = opts.instructions } })
  end

  opts.session_ctx = opts.session_ctx or {}
  opts.session_ctx.system_prompt = system_prompt
  opts.session_ctx.messages = messages

  local tools = {}
  if opts.tools then tools = vim.list_extend(tools, opts.tools) end
  if opts.prompt_opts and opts.prompt_opts.tools then tools = vim.list_extend(tools, opts.prompt_opts.tools) end

  ---@type AvantePromptOptions
  return {
    system_prompt = system_prompt,
    messages = messages,
    image_paths = image_paths,
    tools = tools,
    dropped_history_messages = dropped_history_messages,
  }
end

---@param opts AvanteGeneratePromptsOptions
---@return integer
function M.calculate_tokens(opts)
  local prompt_opts = M.generate_prompts(opts)
  local tokens = Utils.tokens.calculate_tokens(prompt_opts.system_prompt)
  for _, message in ipairs(prompt_opts.messages) do
    tokens = tokens + Utils.tokens.calculate_tokens(message.content)
  end
  return tokens
end

local parse_headers = function(headers_file)
  local headers = {}
  local file = io.open(headers_file, "r")
  if file then
    for line in file:lines() do
      line = line:gsub("\r$", "")
      local key, value = line:match("^%s*(.-)%s*:%s*(.*)$")
      if key and value then headers[key] = value end
    end
    file:close()
  end
  return headers
end

---@param opts avante.CurlOpts
function M.curl(opts)
  local provider = opts.provider
  local prompt_opts = opts.prompt_opts
  local handler_opts = opts.handler_opts

  ---@type AvanteCurlOutput
  local spec = provider:parse_curl_args(prompt_opts)

  ---@type string
  local current_event_state = nil
  local resp_ctx = {}
  resp_ctx.session_id = Utils.uuid()

  local response_body = ""
  ---@param line string
  local function parse_stream_data(line)
    local event = line:match("^event:%s*(.+)$")
    if event then
      current_event_state = event
      return
    end
    local data_match = line:match("^data:%s*(.+)$")
    if data_match then
      provider:parse_response(resp_ctx, data_match, current_event_state, handler_opts)
    else
      response_body = response_body .. line
      local ok, jsn = pcall(vim.json.decode, response_body)
      if ok then
        response_body = ""
        if jsn.error then handler_opts.on_stop({ reason = "error", error = jsn.error }) end
      end
    end
  end

  local function parse_response_without_stream(data)
    provider:parse_response_without_stream(data, current_event_state, handler_opts)
  end

  local completed = false

  local active_job

  local temp_file = fn.tempname()
  local curl_body_file = temp_file .. "-request-body.json"
  local resp_body_file = temp_file .. "-response-body.json"
  local json_content = vim.json.encode(spec.body)
  fn.writefile(vim.split(json_content, "\n"), curl_body_file)

  Utils.debug("curl request body file:", curl_body_file)

  Utils.debug("curl response body file:", resp_body_file)

  local headers_file = temp_file .. "-headers.txt"

  Utils.debug("curl headers file:", headers_file)

  local function cleanup()
    if Config.debug then return end
    vim.schedule(function()
      fn.delete(curl_body_file)
      pcall(fn.delete, resp_body_file)
      fn.delete(headers_file)
    end)
  end

  local headers_reported = false

  active_job = curl.post(spec.url, {
    headers = spec.headers,
    proxy = spec.proxy,
    insecure = spec.insecure,
    body = curl_body_file,
    raw = spec.rawArgs,
    dump = { "-D", headers_file },
    stream = function(err, data, _)
      if not headers_reported and opts.on_response_headers then
        headers_reported = true
        opts.on_response_headers(parse_headers(headers_file))
      end
      if err then
        completed = true
        handler_opts.on_stop({ reason = "error", error = err })
        return
      end
      if not data then return end
      if Config.debug then
        if type(data) == "string" then
          local file = io.open(resp_body_file, "a")
          if file then
            file:write(data .. "\n")
            file:close()
          end
        end
      end
      vim.schedule(function()
        if Config[Config.provider] == nil and provider.parse_stream_data ~= nil then
          if provider.parse_response ~= nil then
            Utils.warn(
              "parse_stream_data and parse_response are mutually exclusive, and thus parse_response will be ignored. Make sure that you handle the incoming data correctly.",
              { once = true }
            )
          end
          provider:parse_stream_data(resp_ctx, data, handler_opts)
        else
          if provider.parse_stream_data ~= nil then
            provider:parse_stream_data(resp_ctx, data, handler_opts)
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
      if not completed then
        completed = true
        cleanup()
        handler_opts.on_stop({ reason = "error", error = err })
      end
    end,
    callback = function(result)
      active_job = nil
      cleanup()
      local headers_map = vim.iter(result.headers):fold({}, function(acc, value)
        local pieces = vim.split(value, ":")
        local key = pieces[1]
        local remain = vim.list_slice(pieces, 2)
        if not remain then return acc end
        local val = Utils.trim_spaces(table.concat(remain, ":"))
        acc[key] = val
        return acc
      end)
      if result.status >= 400 then
        if provider.on_error then
          provider.on_error(result)
        else
          Utils.error("API request failed with status " .. result.status, { once = true, title = "Avante" })
        end
        if result.status == 429 then
          Utils.debug("result", result)
          if result.body then
            local ok, jsn = pcall(vim.json.decode, result.body)
            if ok then
              if jsn.error and jsn.error.message then
                handler_opts.on_stop({ reason = "error", error = jsn.error.message })
                return
              end
            end
          end
          Utils.debug("result", result)
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
      if provider:is_disable_stream() and result.status == 200 then
        vim.schedule(function()
          completed = true
          parse_response_without_stream(result.body)
        end)
      end

      if result.status == 200 and spec.url:match("https://openrouter.ai") then
        local content_type = headers_map["content-type"]
        if content_type and content_type:match("text/html") then
          handler_opts.on_stop({
            reason = "error",
            error = "Your openrouter endpoint setting is incorrect, please set it to https://openrouter.ai/api/v1",
          })
        end
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
        -- Mark as completed first to prevent error handler from running
        completed = true

        -- Attempt to shutdown the active job, but ignore any errors
        xpcall(function() active_job:shutdown() end, function(err)
          Utils.debug("Ignored error during job shutdown: " .. vim.inspect(err))
          return err
        end)

        Utils.debug("LLM request cancelled")
        active_job = nil

        -- Clean up and notify of cancellation
        cleanup()
        vim.schedule(function() handler_opts.on_stop({ reason = "cancelled" }) end)
      end
    end,
  })

  return active_job
end

---@param opts AvanteLLMStreamOptions
function M._stream(opts)
  -- Reset the cancellation flag at the start of a new request
  if LLMToolHelpers then LLMToolHelpers.is_cancelled = false end

  local provider = opts.provider or Providers[Config.provider]
  opts.session_ctx = opts.session_ctx or {}

  if not opts.session_ctx.on_messages_add then opts.session_ctx.on_messages_add = opts.on_messages_add end
  if not opts.session_ctx.on_state_change then opts.session_ctx.on_state_change = opts.on_state_change end
  if not opts.session_ctx.on_start then opts.session_ctx.on_start = opts.on_start end
  if not opts.session_ctx.on_chunk then opts.session_ctx.on_chunk = opts.on_chunk end
  if not opts.session_ctx.on_stop then opts.session_ctx.on_stop = opts.on_stop end
  if not opts.session_ctx.on_tool_log then opts.session_ctx.on_tool_log = opts.on_tool_log end
  if not opts.session_ctx.get_history_messages then
    opts.session_ctx.get_history_messages = opts.get_history_messages
  end

  ---@cast provider AvanteProviderFunctor

  local prompt_opts = M.generate_prompts(opts)

  if
    prompt_opts.dropped_history_messages
    and #prompt_opts.dropped_history_messages > 0
    and opts.on_memory_summarize
  then
    opts.on_memory_summarize(prompt_opts.dropped_history_messages)
    return
  end

  local resp_headers = {}

  ---@type AvanteHandlerOptions
  local handler_opts = {
    on_messages_add = opts.on_messages_add,
    on_state_change = opts.on_state_change,
    on_start = opts.on_start,
    on_chunk = opts.on_chunk,
    on_stop = function(stop_opts)
      ---@param tool_use_list AvanteLLMToolUse[]
      ---@param tool_use_index integer
      ---@param tool_results AvanteLLMToolResult[]
      local function handle_next_tool_use(tool_use_list, tool_use_index, tool_results)
        if tool_use_index > #tool_use_list then
          ---@type avante.HistoryMessage[]
          local messages = {}
          for _, tool_result in ipairs(tool_results) do
            messages[#messages + 1] = HistoryMessage:new({
              role = "user",
              content = {
                {
                  type = "tool_result",
                  tool_use_id = tool_result.tool_use_id,
                  content = tool_result.content,
                  is_error = tool_result.is_error,
                },
              },
            })
          end
          opts.on_messages_add(messages)
          local new_opts = vim.tbl_deep_extend("force", opts, {
            history_messages = opts.get_history_messages(),
          })
          if provider.get_rate_limit_sleep_time then
            local sleep_time = provider:get_rate_limit_sleep_time(resp_headers)
            if sleep_time and sleep_time > 0 then
              Utils.info("Rate limit reached. Sleeping for " .. sleep_time .. " seconds ...")
              vim.defer_fn(function() M._stream(new_opts) end, sleep_time * 1000)
              return
            end
          end
          M._stream(new_opts)
          return
        end
        local tool_use = tool_use_list[tool_use_index]
        ---@param result string | nil
        ---@param error string | nil
        local function handle_tool_result(result, error)
          -- Special handling for cancellation signal from tools
          if error == LLMToolHelpers.CANCEL_TOKEN then
            Utils.debug("Tool execution was cancelled by user")
            if opts.on_chunk then opts.on_chunk("\n*[Request cancelled by user during tool execution.]*\n") end
            if opts.on_messages_add then
              local message = HistoryMessage:new({
                role = "assistant",
                content = "\n*[Request cancelled by user during tool execution.]*\n",
              }, {
                just_for_display = true,
              })
              opts.on_messages_add({ message })
            end
            return opts.on_stop({ reason = "cancelled" })
          end

          local tool_result = {
            tool_use_id = tool_use.id,
            content = error ~= nil and error or result,
            is_error = error ~= nil,
          }
          table.insert(tool_results, tool_result)
          return handle_next_tool_use(tool_use_list, tool_use_index + 1, tool_results)
        end
        -- Either on_complete handles the tool result asynchronously or we receive the result and error synchronously when either is not nil
        local result, error = LLMTools.process_tool_use(
          prompt_opts.tools,
          tool_use,
          opts.on_tool_log,
          handle_tool_result,
          opts.session_ctx
        )
        if result ~= nil or error ~= nil then return handle_tool_result(result, error) end
      end
      if stop_opts.reason == "cancelled" then
        if opts.on_chunk then opts.on_chunk("\n*[Request cancelled by user.]*\n") end
        if opts.on_messages_add then
          local message = HistoryMessage:new({
            role = "assistant",
            content = "\n*[Request cancelled by user.]*\n",
          }, {
            just_for_display = true,
          })
          opts.on_messages_add({ message })
        end
        return opts.on_stop({ reason = "cancelled" })
      end
      if stop_opts.reason == "tool_use" then
        local tool_use_list = {} ---@type AvanteLLMToolUse[]
        local tool_result_seen = {}
        local history_messages = opts.get_history_messages and opts.get_history_messages() or {}
        for idx = #history_messages, 1, -1 do
          local message = history_messages[idx]
          local content = message.message.content
          if type(content) ~= "table" or #content == 0 then goto continue end
          if content[1].type == "tool_use" then
            if not tool_result_seen[content[1].id] then
              table.insert(tool_use_list, 1, content[1])
            else
              break
            end
          end
          if content[1].type == "tool_result" then tool_result_seen[content[1].tool_use_id] = true end
          ::continue::
        end
        local sorted_tool_use_list = {} ---@type AvanteLLMToolUse[]
        for _, tool_use in vim.spairs(tool_use_list) do
          table.insert(sorted_tool_use_list, tool_use)
        end
        return handle_next_tool_use(sorted_tool_use_list, 1, {})
      end
      if stop_opts.reason == "rate_limit" then
        local msg_content = "*[Rate limit reached. Retrying in " .. stop_opts.retry_after .. " seconds ...]*"
        if opts.on_chunk then opts.on_chunk("\n" .. msg_content .. "\n") end
        local message
        if opts.on_messages_add then
          message = HistoryMessage:new({
            role = "assistant",
            content = "\n\n" .. msg_content,
          }, {
            just_for_display = true,
          })
          opts.on_messages_add({ message })
        end
        local timer = vim.loop.new_timer()
        if timer then
          local retry_after = stop_opts.retry_after
          local function countdown()
            timer:start(
              1000,
              0,
              vim.schedule_wrap(function()
                if retry_after > 0 then retry_after = retry_after - 1 end
                local msg_content_ = "*[Rate limit reached. Retrying in " .. retry_after .. " seconds ...]*"
                if opts.on_chunk then opts.on_chunk([[\033[1A\033[K]] .. "\n" .. msg_content_ .. "\n") end
                if opts.on_messages_add and message then
                  message.message.content = "\n\n" .. msg_content_
                  opts.on_messages_add({ message })
                end
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

  return M.curl({
    provider = provider,
    prompt_opts = prompt_opts,
    handler_opts = handler_opts,
    on_response_headers = function(headers) resp_headers = headers end,
  })
end

local function _merge_response(first_response, second_response, opts)
  local prompt = "\n" .. Config.dual_boost.prompt
  prompt = prompt
    :gsub("{{[%s]*provider1_output[%s]*}}", function() return first_response end)
    :gsub("{{[%s]*provider2_output[%s]*}}", function() return second_response end)

  prompt = prompt .. "\n"

  if opts.instructions == nil then opts.instructions = "" end

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
    opts.on_tool_log = vim.schedule_wrap(function(...)
      if not original_on_tool_log then return end
      return original_on_tool_log(...)
    end)
  end
  if opts.on_chunk ~= nil then
    local original_on_chunk = opts.on_chunk
    opts.on_chunk = vim.schedule_wrap(function(chunk)
      if is_completed then return end
      if original_on_chunk then return original_on_chunk(chunk) end
    end)
  end
  if opts.on_stop ~= nil then
    local original_on_stop = opts.on_stop
    opts.on_stop = vim.schedule_wrap(function(stop_opts)
      if is_completed then return end
      if stop_opts.reason == "complete" or stop_opts.reason == "error" or stop_opts.reason == "cancelled" then
        is_completed = true
      end
      return original_on_stop(stop_opts)
    end)
  end

  local valid_dual_boost_modes = {
    legacy = true,
  }

  opts.mode = opts.mode or Config.mode

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

function M.cancel_inflight_request()
  if LLMToolHelpers.is_cancelled ~= nil then LLMToolHelpers.is_cancelled = true end
  if LLMToolHelpers.confirm_popup ~= nil then
    LLMToolHelpers.confirm_popup:cancel()
    LLMToolHelpers.confirm_popup = nil
  end

  api.nvim_exec_autocmds("User", { pattern = M.CANCEL_PATTERN })
end

return M
