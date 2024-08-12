local M = {}
local curl = require("plenary.curl")
local Path = require("plenary.path")
local n = require("nui-components")
local diff = require("avante.diff")
local api = vim.api
local fn = vim.fn

local RESULT_BUF_NAME = "AVANTE_RESULT"
local CONFLICT_BUF_NAME = "AVANTE_CONFLICT"

local function create_result_buf()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("swapfile", false, { buf = buf })
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_buf_set_name(buf, RESULT_BUF_NAME)
  return buf
end

local result_buf = create_result_buf()

local function is_code_buf(buf)
  local ignored_filetypes = {
    "dashboard",
    "alpha",
    "neo-tree",
    "NvimTree",
    "TelescopePrompt",
    "Prompt",
    "qf",
    "help",
  }

  if api.nvim_buf_is_valid(buf) and api.nvim_get_option_value("buflisted", { buf = buf }) then
    local buftype = api.nvim_get_option_value("buftype", { buf = buf })
    local filetype = api.nvim_get_option_value("filetype", { buf = buf })

    if buftype == "" and filetype ~= "" and not vim.tbl_contains(ignored_filetypes, filetype) then
      local bufname = api.nvim_buf_get_name(buf)
      if bufname ~= "" and bufname ~= RESULT_BUF_NAME and bufname ~= CONFLICT_BUF_NAME then
        return true
      end
    end
  end

  return false
end

local signal = n.create_signal({
  is_loading = false,
  text = "",
})

local _cur_code_buf = nil

local function get_cur_code_buf()
  return _cur_code_buf
end

local function get_cur_code_buf_name()
  local code_buf = get_cur_code_buf()
  if code_buf == nil then
    print("Error: cannot get code buffer")
    return
  end
  return api.nvim_buf_get_name(code_buf)
end

local function get_cur_code_win()
  local code_buf = get_cur_code_buf()
  if code_buf == nil then
    print("Error: cannot get code buffer")
    return
  end
  return fn.bufwinid(code_buf)
end

local function get_cur_code_buf_content()
  local code_buf = get_cur_code_buf()
  if code_buf == nil then
    print("Error: cannot get code buffer")
    return {}
  end
  return api.nvim_buf_get_lines(code_buf, 0, -1, false)
end

local function prepend_line_number(content)
  local lines = vim.split(content, "\n")
  local result = {}
  for i, line in ipairs(lines) do
    table.insert(result, "L" .. i .. ": " .. line)
  end
  return table.concat(result, "\n")
end

local function extract_code_snippets(content)
  local snippets = {}
  local current_snippet = {}
  local in_code_block = false
  local lang, start_line, end_line
  local explanation = ""

  for line in content:gmatch("[^\r\n]+") do
    local start_line_str, end_line_str = line:match("^Replace lines: (%d+)-(%d+)")
    if start_line_str ~= nil and end_line_str ~= nil then
      start_line = tonumber(start_line_str)
      end_line = tonumber(end_line_str)
    end
    if line:match("^```") then
      if in_code_block then
        if start_line ~= nil and end_line ~= nil then
          table.insert(snippets, {
            range = { start_line, end_line },
            content = table.concat(current_snippet, "\n"),
            lang = lang,
            explanation = explanation,
          })
        end
        current_snippet = {}
        start_line, end_line = nil, nil
        explanation = ""
        in_code_block = false
      else
        lang = line:match("^```(%w+)")
        if not lang or lang == "" then
          lang = "text"
        end
        in_code_block = true
      end
    elseif in_code_block then
      table.insert(current_snippet, line)
    else
      explanation = explanation .. line .. "\n"
    end
  end

  return snippets
end

local system_prompt = [[
You are an excellent programming expert.
]]

local user_prompt_tpl = [[
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
   - L1:, L2:, L3:, ... in the prefix of each line represent line numbers in the original code, you must use these exact numbers, but you must NOT include them in your response.
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

QUESTION: ${{question}}

CODE:
```
${{code}}
```
]]

local function call_claude_api_stream(prompt, original_content, on_chunk, on_complete)
  local api_key = os.getenv("ANTHROPIC_API_KEY")
  if not api_key then
    error("ANTHROPIC_API_KEY environment variable is not set")
  end

  local user_prompt = user_prompt_tpl:gsub("${{question}}", prompt):gsub("${{code}}", original_content)

  print("Sending request to Claude API...")

  local tokens = M.config.claude.model == "claude-3-5-sonnet-20240620" and 8192 or 4096
  local headers = {
    ["Content-Type"] = "application/json",
    ["x-api-key"] = api_key,
    ["anthropic-version"] = "2023-06-01",
    ["anthropic-beta"] = "messages-2023-12-15",
  }

  if M.config.claude.model == "claude-3-5-sonnet-20240620" then
    headers["anthropic-beta"] = "max-tokens-3-5-sonnet-2024-07-15"
  end

  local url = "https://api.anthropic.com/v1/messages"
  curl.post(url, {
    ---@diagnostic disable-next-line: unused-local
    stream = function(err, data, job)
      if err then
        error("Error: " .. vim.inspect(err))
        return
      end
      if data then
        for line in data:gmatch("[^\r\n]+") do
          if line:sub(1, 6) == "data: " then
            vim.schedule(function()
              local success, parsed = pcall(fn.json_decode, line:sub(7))
              if success and parsed and parsed.type == "content_block_delta" then
                on_chunk(parsed.delta.text)
              elseif success and parsed and parsed.type == "message_stop" then
                -- Stream request completed
                on_complete()
              elseif success and parsed and parsed.type == "error" then
                print("Error: " .. vim.inspect(parsed))
                -- Stream request completed
                on_complete()
              end
            end)
          end
        end
      end
    end,
    headers = headers,
    body = fn.json_encode({
      model = M.config.claude.model,
      system = system_prompt,
      messages = {
        { role = "user", content = user_prompt },
      },
      stream = true,
      temperature = M.config.claude.temperature,
      max_tokens = tokens,
    }),
  })
end

local function call_openai_api_stream(prompt, original_content, on_chunk, on_complete)
  local api_key = os.getenv("OPENAI_API_KEY")
  if not api_key then
    error("OPENAI_API_KEY environment variable is not set")
  end

  local user_prompt = user_prompt_tpl:gsub("${{question}}", prompt):gsub("${{code}}", original_content)

  print("Sending request to OpenAI API...")

  curl.post("https://api.openai.com/v1/chat/completions", {
    ---@diagnostic disable-next-line: unused-local
    stream = function(err, data, job)
      if err then
        error("Error: " .. vim.inspect(err))
        return
      end
      if data then
        for line in data:gmatch("[^\r\n]+") do
          if line:sub(1, 6) == "data: " then
            vim.schedule(function()
              local success, parsed = pcall(fn.json_decode, line:sub(7))
              if success and parsed and parsed.choices and parsed.choices[1].delta.content then
                on_chunk(parsed.choices[1].delta.content)
              elseif success and parsed and parsed.choices and parsed.choices[1].finish_reason == "stop" then
                -- Stream request completed
                on_complete()
              end
            end)
          end
        end
      end
    end,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key,
    },
    body = fn.json_encode({
      model = M.config.openai.model,
      messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = user_prompt },
      },
      temperature = M.config.openai.temperature,
      max_tokens = M.config.openai.max_tokens,
      stream = true,
    }),
  })
end

local function call_ai_api_stream(prompt, original_content, on_chunk, on_complete)
  if M.config.provider == "openai" then
    call_openai_api_stream(prompt, original_content, on_chunk, on_complete)
  elseif M.config.provider == "claude" then
    call_claude_api_stream(prompt, original_content, on_chunk, on_complete)
  end
end

local function update_result_buf_content(content)
  local current_win = api.nvim_get_current_win()
  local result_win = fn.bufwinid(result_buf)

  vim.defer_fn(function()
    api.nvim_set_option_value("modifiable", true, { buf = result_buf })
    api.nvim_buf_set_lines(result_buf, 0, -1, false, vim.split(content, "\n"))
    api.nvim_set_option_value("filetype", "markdown", { buf = result_buf })
    if result_win ~= -1 then
      -- Move to the bottom
      api.nvim_win_set_cursor(result_win, { api.nvim_buf_line_count(result_buf), 0 })
      api.nvim_set_option_value("modifiable", false, { buf = result_buf })
      api.nvim_set_current_win(current_win)
    end
  end, 0)
end

-- Add a new function to display notifications
local function show_notification(message)
  vim.notify(message, vim.log.levels.INFO, {
    title = "AI Assistant",
    timeout = 3000,
  })
end

-- Function to get the current project root directory
local function get_project_root()
  local current_file = fn.expand("%:p")
  local current_dir = fn.fnamemodify(current_file, ":h")
  local git_root = fn.systemlist("git -C " .. fn.shellescape(current_dir) .. " rev-parse --show-toplevel")[1]
  return git_root or current_dir
end

local function get_chat_history_filename()
  local code_buf_name = get_cur_code_buf_name()
  if code_buf_name == nil then
    print("Error: cannot get code buffer name")
    return
  end
  local relative_path = fn.fnamemodify(code_buf_name, ":~:.")
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(relative_path, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  return fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g")
end

-- Function to get the chat history file path
local function get_chat_history_file()
  local project_root = get_project_root()
  local filename = get_chat_history_filename()
  local history_dir = Path:new(project_root, ".avante_chat_history")
  return history_dir:joinpath(filename .. ".json")
end

-- Function to get current timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- Function to load chat history
local function load_chat_history()
  local history_file = get_chat_history_file()
  if history_file:exists() then
    local content = history_file:read()
    return fn.json_decode(content)
  end
  return {}
end

-- Function to save chat history
local function save_chat_history(history)
  local history_file = get_chat_history_file()
  local history_dir = history_file:parent()

  -- Create the directory if it doesn't exist
  if not history_dir:exists() then
    history_dir:mkdir({ parents = true })
  end

  history_file:write(fn.json_encode(history), "w")
end

local function update_result_buf_with_history(history)
  local content = ""
  for _, entry in ipairs(history) do
    content = content .. "## " .. entry.timestamp .. "\n\n"
    content = content .. "> " .. entry.requirement:gsub("\n", "\n> ") .. "\n\n"
    content = content .. entry.response .. "\n\n"
    content = content .. "---\n\n"
  end
  update_result_buf_content(content)
end

local function get_conflict_content(content, snippets)
  -- sort snippets by start_line
  table.sort(snippets, function(a, b)
    return a.range[1] < b.range[1]
  end)

  local lines = vim.split(content, "\n")
  local result = {}
  local current_line = 1

  for _, snippet in ipairs(snippets) do
    local start_line, end_line = unpack(snippet.range)

    while current_line < start_line do
      table.insert(result, lines[current_line])
      current_line = current_line + 1
    end

    table.insert(result, "<<<<<<< HEAD")
    for i = start_line, end_line do
      table.insert(result, lines[i])
    end
    table.insert(result, "=======")

    for _, line in ipairs(vim.split(snippet.content, "\n")) do
      table.insert(result, line)
    end

    table.insert(result, ">>>>>>> Snippet")

    current_line = end_line + 1
  end

  while current_line <= #lines do
    table.insert(result, lines[current_line])
    current_line = current_line + 1
  end

  return result
end

local renderer_width = math.ceil(vim.o.columns * 0.3)

local renderer = n.create_renderer({
  width = renderer_width,
  height = vim.o.lines,
  position = vim.o.columns - renderer_width,
  relative = "editor",
})

function M.render_sidebar()
  local chat_history = load_chat_history()
  update_result_buf_with_history(chat_history)

  local function handle_submit()
    local state = signal:get_value()
    local user_input = state.text

    local timestamp = get_timestamp()
    update_result_buf_content(
      "\n\n## " .. timestamp .. "\n\n> " .. user_input:gsub("\n", "\n> ") .. "\n\nGenerating response...\n"
    )

    local code_buf = get_cur_code_buf()
    if code_buf == nil then
      error("Error: cannot get code buffer")
      return
    end
    local content = table.concat(get_cur_code_buf_content(), "\n")
    local content_with_line_numbers = prepend_line_number(content)
    local full_response = ""

    signal.is_loading = true

    call_ai_api_stream(user_input, content_with_line_numbers, function(chunk)
      full_response = full_response .. chunk
      update_result_buf_content(
        "## " .. timestamp .. "\n\n> " .. user_input:gsub("\n", "\n> ") .. "\n\n" .. full_response
      )
      vim.schedule(function()
        vim.cmd("redraw")
      end)
    end, function()
      signal.is_loading = false
      -- Execute when the stream request is actually completed
      update_result_buf_content(
        "## "
          .. timestamp
          .. "\n\n> "
          .. user_input:gsub("\n", "\n> ")
          .. "\n\n"
          .. full_response
          .. "\n\n**Generation complete!** Please review the code suggestions above.\n\n\n\n"
      )

      -- Display notification
      show_notification("Content generation complete!")

      -- Save chat history
      table.insert(chat_history or {}, { timestamp = timestamp, requirement = user_input, response = full_response })
      save_chat_history(chat_history)

      local snippets = extract_code_snippets(full_response)
      local conflict_content = get_conflict_content(content, snippets)

      vim.defer_fn(function()
        api.nvim_buf_set_lines(code_buf, 0, -1, false, conflict_content)
        local code_win = get_cur_code_win()
        if code_win == nil then
          error("Error: cannot get code window")
          return
        end
        api.nvim_set_current_win(code_win)
        api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
        diff.add_visited_buffer(code_buf)
        diff.process(code_buf)
        api.nvim_feedkeys("gg", "n", false)
        vim.defer_fn(function()
          vim.cmd("AvanteConflictNextConflict")
          api.nvim_feedkeys("zz", "n", false)
        end, 1000)
      end, 10)
    end)
  end

  local body = function()
    local code_buf = get_cur_code_buf()
    if code_buf == nil then
      error("Error: cannot get code buffer")
      return
    end
    local filetype = api.nvim_get_option_value("filetype", { buf = code_buf })
    local icon = require("nvim-web-devicons").get_icon_by_filetype(filetype, {})
    local code_file_fullpath = api.nvim_buf_get_name(code_buf)
    local code_filename = fn.fnamemodify(code_file_fullpath, ":t")

    return n.rows(
      { flex = 0 },
      n.box(
        {
          direction = "column",
          size = vim.o.lines - 3,
        },
        n.buffer({
          id = "response",
          flex = 1,
          buf = result_buf,
          autoscroll = true,
          border_label = {
            text = "💬 Avante Chat",
            align = "center",
          },
        })
      ),
      n.gap(1),
      n.columns(
        { flex = 0 },
        n.text_input({
          id = "text-input",
          border_label = {
            text = string.format(" 🙋 Your question (with %s %s): ", icon, code_filename),
          },
          autofocus = true,
          wrap = true,
          flex = 1,
          on_change = function(value)
            local state = signal:get_value()
            local is_enter = value:sub(-1) == "\n" and #state.text < #value
            if is_enter then
              value = value:sub(1, -2)
            end
            signal.text = value
            if is_enter and #value > 0 then
              handle_submit()
            end
          end,
        }),
        n.gap(1),
        n.spinner({
          is_loading = signal.is_loading,
          padding = { top = 1, left = 1 },
          ---@diagnostic disable-next-line: undefined-field
          hidden = signal.is_loading:negate(),
        })
      )
    )
  end

  renderer:render(body)
end

M.config = {
  provider = "claude",
  openai = {
    model = "gpt-4o",
    temperature = 0,
    max_tokens = 4096,
  },
  claude = {
    model = "claude-3-5-sonnet-20240620",
    temperature = 0,
    max_tokens = 4096,
  },
  mappings = {
    show_sidebar = "<leader>aa",
    apply = "co",
    reject = "ct",
    next = "]x",
    prev = "[x",
  },
}

function M.setup(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  if is_code_buf(bufnr) then
    _cur_code_buf = bufnr
  end
  diff.setup({
    debug = false, -- log output to console
    default_mappings = true, -- disable buffer local mapping created by this plugin
    default_commands = true, -- disable commands created by this plugin
    disable_diagnostics = true, -- This will disable the diagnostics in a buffer whilst it is conflicted
    list_opener = "copen",
    highlights = {
      incoming = "DiffAdded",
      current = "DiffRemoved",
    },
  })
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local function on_buf_enter()
    bufnr = vim.api.nvim_get_current_buf()
    if is_code_buf(bufnr) then
      _cur_code_buf = bufnr
    end
  end

  api.nvim_create_autocmd("BufEnter", {
    callback = on_buf_enter,
  })

  api.nvim_create_user_command("AvanteAsk", function()
    M.render_sidebar()
  end, {
    nargs = 0,
  })

  api.nvim_set_keymap("n", M.config.mappings.show_sidebar, "<cmd>AvanteAsk<CR>", { noremap = true, silent = true })
end

return M
