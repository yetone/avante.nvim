local Config = require("avante.config")
local Utils = require("avante.utils")
local PromptInput = require("avante.ui.prompt_input")

---@class avante.ApiToggle
---@operator call(): boolean
---@field debug ToggleBind.wrap
---@field hint ToggleBind.wrap

---@class avante.Api
---@field toggle avante.ApiToggle
local M = {}

---@param target_provider avante.SelectorProvider
function M.switch_selector_provider(target_provider)
  require("avante.config").override({
    selector = {
      provider = target_provider,
    },
  })
end

---@param target_provider avante.InputProvider
function M.switch_input_provider(target_provider)
  require("avante.config").override({
    input = {
      provider = target_provider,
    },
  })
end

---@param target avante.ProviderName
function M.switch_provider(target) require("avante.providers").refresh(target) end

---@param path string
local function to_windows_path(path)
  local winpath = path:gsub("/", "\\")

  if winpath:match("^%a:") then winpath = winpath:sub(1, 2):upper() .. winpath:sub(3) end

  winpath = winpath:gsub("\\$", "")

  return winpath
end

---@param opts? {source: boolean}
function M.build(opts)
  opts = opts or { source = true }
  local dirname = Utils.trim(string.sub(debug.getinfo(1).source, 2, #"/init.lua" * -1), { suffix = "/" })
  local git_root = vim.fs.find(".git", { path = dirname, upward = true })[1]
  local build_directory = git_root and vim.fn.fnamemodify(git_root, ":h") or (dirname .. "/../../")

  if opts.source and not vim.fn.executable("cargo") then
    error("Building avante.nvim requires cargo to be installed.", 2)
  end

  ---@type string[]
  local cmd
  local os_name = Utils.get_os_name()

  if vim.tbl_contains({ "linux", "darwin" }, os_name) then
    cmd = {
      "sh",
      "-c",
      string.format("make BUILD_FROM_SOURCE=%s -C %s", opts.source == true and "true" or "false", build_directory),
    }
  elseif os_name == "windows" then
    build_directory = to_windows_path(build_directory)
    cmd = {
      "powershell",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      string.format("%s\\Build.ps1", build_directory),
      "-WorkingDirectory",
      build_directory,
      "-BuildFromSource",
      string.format("%s", opts.source == true and "true" or "false"),
    }
  else
    error("Unsupported operating system: " .. os_name, 2)
  end

  ---@type integer
  local pid
  local exit_code = { 0 }

  local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(obj)
    local stderr = obj.stderr and vim.split(obj.stderr, "\n") or {}
    local stdout = obj.stdout and vim.split(obj.stdout, "\n") or {}
    if vim.tbl_contains(exit_code, obj.code) then
      local output = stdout
      if #output == 0 then
        table.insert(output, "")
        Utils.debug("build output:", output)
      else
        Utils.debug("build error:", stderr)
      end
    end
  end)
  if not ok then Utils.error("Failed to build the command: " .. cmd .. "\n" .. job_or_err, { once = true }) end
  pid = job_or_err.pid
  return pid
end

---@class AskOptions
---@field question? string optional questions
---@field win? table<string, any> windows options similar to |nvim_open_win()|
---@field ask? boolean
---@field floating? boolean whether to open a floating input to enter the question
---@field new_chat? boolean whether to open a new chat
---@field without_selection? boolean whether to open a new chat without selection
---@field sidebar_pre_render? fun(sidebar: avante.Sidebar)
---@field sidebar_post_render? fun(sidebar: avante.Sidebar)
---@field project_root? string optional project root
---@field show_logo? boolean whether to show the logo

function M.full_view_ask()
  M.ask({
    show_logo = true,
    sidebar_post_render = function(sidebar)
      sidebar:toggle_code_window()
      -- vim.wo[sidebar.containers.result.winid].number = true
      -- vim.wo[sidebar.containers.result.winid].relativenumber = true
    end,
  })
end

M.zen_mode = M.full_view_ask

---@param opts? AskOptions
function M.ask(opts)
  opts = opts or {}
  Config.ask_opts = opts
  if type(opts) == "string" then
    Utils.warn("passing 'ask' as string is deprecated, do {question = '...'} instead", { once = true })
    opts = { question = opts }
  end

  local has_question = opts.question ~= nil and opts.question ~= ""
  local new_chat = opts.new_chat == true

  if Utils.is_sidebar_buffer(0) and not has_question and not new_chat then
    require("avante").close_sidebar()
    return false
  end

  opts = vim.tbl_extend("force", { selection = Utils.get_visual_selection_and_range() }, opts)

  ---@param input string | nil
  local function ask(input)
    if input == nil or input == "" then input = opts.question end
    local sidebar = require("avante").get()
    if sidebar and sidebar:is_open() and sidebar.code.bufnr ~= vim.api.nvim_get_current_buf() then
      sidebar:close({ goto_code_win = false })
    end
    require("avante").open_sidebar(opts)
    sidebar = require("avante").get()
    if new_chat then sidebar:new_chat() end
    if opts.without_selection then
      sidebar.code.selection = nil
      sidebar.file_selector:reset()
      if sidebar.containers.selected_files then sidebar.containers.selected_files:unmount() end
    end
    if input == nil or input == "" then return true end
    vim.api.nvim_exec_autocmds("User", { pattern = "AvanteInputSubmitted", data = { request = input } })
    return true
  end

  if opts.floating == true or (Config.windows and Config.windows.ask and Config.windows.ask.floating == true and not has_question and opts.floating == nil) then
    local ask_config = (Config.windows and Config.windows.ask) or {}
    local prompt_input = PromptInput:new({
      submit_callback = function(input) ask(input) end,
      close_on_submit = true,
      win_opts = {
        border = ask_config.border or "rounded",
        title = { { "Avante Ask", "FloatTitle" } },
      },
      start_insert = ask_config.start_insert ~= false,
      default_value = opts.question,
    })
    prompt_input:open()
    return true
  end

  return ask()
end

---@param request? string
---@param line1? integer
---@param line2? integer
function M.edit(request, line1, line2)
  local _, selection = require("avante").get()
  if not selection then require("avante")._init(vim.api.nvim_get_current_tabpage()) end
  _, selection = require("avante").get()
  if not selection then return end
  selection:create_editing_input(request, line1, line2)
  if request ~= nil and request ~= "" then
    vim.api.nvim_exec_autocmds("User", { pattern = "AvanteEditSubmitted", data = { request = request } })
  end
end

---@return avante.Suggestion | nil
function M.get_suggestion()
  local _, _, suggestion = require("avante").get()
  return suggestion
end

---@param opts? AskOptions
function M.refresh(opts)
  opts = opts or {}
  local sidebar = require("avante").get()
  if not sidebar then return end
  if not sidebar:is_open() then return end
  local curbuf = vim.api.nvim_get_current_buf()

  local focused = sidebar.containers.result.bufnr == curbuf or sidebar.containers.input.bufnr == curbuf
  if focused or not sidebar:is_open() then return end
  local listed = vim.api.nvim_get_option_value("buflisted", { buf = curbuf })

  if Utils.is_sidebar_buffer(curbuf) or not listed then return end

  local curwin = vim.api.nvim_get_current_win()

  sidebar:close()
  sidebar.code.winid = curwin
  sidebar.code.bufnr = curbuf
  sidebar:render(opts)
end

---@param opts? AskOptions
function M.focus(opts)
  opts = opts or {}
  local sidebar = require("avante").get()
  if not sidebar then return end

  local curbuf = vim.api.nvim_get_current_buf()
  local curwin = vim.api.nvim_get_current_win()

  if sidebar:is_open() then
    if curbuf == sidebar.containers.input.bufnr then
      if sidebar.code.winid and sidebar.code.winid ~= curwin then vim.api.nvim_set_current_win(sidebar.code.winid) end
    elseif curbuf == sidebar.containers.result.bufnr then
      if sidebar.code.winid and sidebar.code.winid ~= curwin then vim.api.nvim_set_current_win(sidebar.code.winid) end
    else
      if sidebar.containers.input.winid and sidebar.containers.input.winid ~= curwin then
        vim.api.nvim_set_current_win(sidebar.containers.input.winid)
      end
    end
  else
    if sidebar.code.winid then vim.api.nvim_set_current_win(sidebar.code.winid) end
    ---@cast opts SidebarOpenOptions
    sidebar:open(opts)
    if sidebar.containers.input.winid then vim.api.nvim_set_current_win(sidebar.containers.input.winid) end
  end
end

function M.select_model() require("avante.model_selector").open() end

function M.select_history()
  local buf = vim.api.nvim_get_current_buf()
  require("avante.history_selector").open(buf, function(filename)
    vim.api.nvim_buf_call(buf, function()
      if not require("avante").is_sidebar_open() then require("avante").open_sidebar({}) end
      local Path = require("avante.path")
      Path.history.save_latest_filename(buf, filename)
      local sidebar = require("avante").get()
      sidebar:update_content_with_history()
      sidebar:create_todos_container()
      sidebar:initialize_token_count()
      vim.schedule(function() sidebar:focus_input() end)
    end)
  end)
end

function M.select_prompt()
  require("avante.prompt_selector").open()
end

function M.view_threads()
  local buf = vim.api.nvim_get_current_buf()
  require("avante.thread_viewer").open(buf, function(filename, external_session_id)
    vim.api.nvim_buf_call(buf, function()
      if not require("avante").is_sidebar_open() then require("avante").open_sidebar({}) end
      local Path = require("avante.path")
      local Utils = require("avante.utils")
      
      -- Handle external ACP sessions (sessions created outside Avante)
      if external_session_id then
        -- Create a new Avante history for this external session
        local sidebar = require("avante").get()
        sidebar:reload_chat_history() -- This will create a new history if none exists
        
        -- Set the ACP session ID to link it with the external session
        sidebar.chat_history.acp_session_id = external_session_id
        
        -- Get the working directory from the external session info
        local thread_viewer = require("avante.thread_viewer")
        local external_info = thread_viewer.get_external_session_info(external_session_id)
        if external_info and external_info.working_directory then
          sidebar.chat_history.working_directory = external_info.working_directory
          if vim.fn.isdirectory(external_info.working_directory) == 1 then
            vim.cmd("cd " .. vim.fn.fnameescape(external_info.working_directory))
            Utils.info("Changed directory to: " .. external_info.working_directory)
          end
        end
        
        -- Save the history with the ACP session ID
        Path.history.save(buf, sidebar.chat_history)
        Path.history.save_latest_filename(buf, sidebar.chat_history.filename)
        
        -- Load the external session to sync its state
        local Config = require("avante.config")
        if Config.acp_providers[Config.provider] then
          Utils.info("Loading external ACP session...")
          
          sidebar.acp_client = nil -- Force reconnection
          sidebar._on_session_load_complete = function()
            sidebar:reload_chat_history()
            sidebar:update_content_with_history()
            sidebar:create_todos_container()
            sidebar:initialize_token_count()
            vim.schedule(function() sidebar:focus_input() end)
            sidebar._on_session_load_complete = nil
          end
          
          vim.schedule(function()
            sidebar._load_existing_session = true
            sidebar:handle_submit("")
          end)
        else
          sidebar:update_content_with_history()
          sidebar:create_todos_container()
          sidebar:initialize_token_count()
          vim.schedule(function() sidebar:focus_input() end)
        end
        
        return
      end
      
      -- Handle regular Avante history
      Path.history.save_latest_filename(buf, filename)
      local sidebar = require("avante").get()
      
      -- Reload chat history to get the latest state from disk
      sidebar:reload_chat_history()
      
      -- If there's an ACP session, sync it with external changes
      local history = sidebar.chat_history
      if history and history.acp_session_id then
        local Utils = require("avante.utils")
        local Config = require("avante.config")
        
        -- Change to the working directory of the thread FIRST
        if history.working_directory and vim.fn.isdirectory(history.working_directory) == 1 then
          vim.cmd("cd " .. vim.fn.fnameescape(history.working_directory))
          Utils.info("Changed directory to: " .. history.working_directory)
        end
        
        -- Restore selected files from history
        if history.selected_files and sidebar.file_selector then
          -- Clear existing selected files
          sidebar.file_selector.selected_files = {}
          -- Add files from history
          for _, filepath in ipairs(history.selected_files) do
            sidebar.file_selector:add_selected_file(filepath)
          end
        end
        
        -- Load the ACP session to sync state from external changes
        if Config.acp_providers[Config.provider] then
          Utils.info("Loading ACP session to sync external changes...")
          
          -- Force reconnection and session loading
          sidebar.acp_client = nil -- Clear existing client to force reconnection
          
          -- Set callback to update UI after session load completes
          sidebar._on_session_load_complete = function()
            -- Reload history to pick up any changes synced from ACP
            sidebar:reload_chat_history()
            sidebar:update_content_with_history()
            sidebar:create_todos_container()
            sidebar:initialize_token_count()
            vim.schedule(function() 
              sidebar:focus_input()
            end)
            -- Clear the callback
            sidebar._on_session_load_complete = nil
          end
          
          -- Trigger a new connection with session loading
          vim.schedule(function()
            sidebar._load_existing_session = true
            sidebar:handle_submit("")
          end)
        else
          -- For non-ACP providers, just update the content
          sidebar:update_content_with_history()
          sidebar:create_todos_container()
          sidebar:initialize_token_count()
          vim.schedule(function() sidebar:focus_input() end)
        end
      else
        -- No ACP session, just update normally
        sidebar:update_content_with_history()
        sidebar:create_todos_container()
        sidebar:initialize_token_count()
        vim.schedule(function() sidebar:focus_input() end)
      end
    end)
  end)
end

--- Request agent to enter plan mode (for ACP agents like claude-code)
function M.request_plan_mode()
  local Utils = require("avante.utils")
  local sidebar = require("avante").get()
  if not sidebar then
    Utils.warn("Sidebar not available")
    return
  end
  
  local message = "Please enter plan mode to explore the codebase and design an implementation approach before making changes."
  sidebar:add_message(message)
  Utils.info("Requested agent to enter plan mode")
end

-- Session management functions
function M.save_session()
  local sidebar = require("avante").get()
  if not sidebar then
    require("avante.utils").warn("No active sidebar to save")
    return
  end
  local SessionManager = require("avante.session_manager")
  if SessionManager.save_session(sidebar) then
    require("avante.utils").info("Session saved successfully")
  else
    require("avante.utils").error("Failed to save session")
  end
end

function M.restore_session()
  local sidebar = require("avante").get()
  if not sidebar then
    require("avante.api").ask()
    sidebar = require("avante").get()
  end

  local SessionManager = require("avante.session_manager")
  local session_state = SessionManager.load_session(sidebar.code.bufnr)
  if not session_state then
    require("avante.utils").warn("No saved session found for this project")
    return
  end

  SessionManager.restore_session(sidebar, session_state)
end

function M.delete_session()
  local bufnr = vim.api.nvim_get_current_buf()
  local SessionManager = require("avante.session_manager")
  if SessionManager.delete_session(bufnr) then
    require("avante.utils").info("Session deleted")
  else
    require("avante.utils").warn("No session found to delete")
  end
end

function M.list_sessions()
  local SessionManager = require("avante.session_manager")
  local sessions = SessionManager.list_sessions()

  if vim.tbl_count(sessions) == 0 then
    require("avante.utils").info("No saved sessions")
    return
  end

  print("Saved sessions:")
  for project_root, session in pairs(sessions) do
    print(string.format("  %s - %s (%s)",
      vim.fn.fnamemodify(project_root, ":t"),
      session.timestamp,
      session.provider
    ))
  end
end

function M.add_buffer_files()
  local sidebar = require("avante").get()
  if not sidebar then
    require("avante.api").ask()
    sidebar = require("avante").get()
  end
  if not sidebar:is_open() then sidebar:open({}) end
  sidebar.file_selector:add_buffer_files()
end

function M.add_selected_file(filepath)
  local rel_path = Utils.uniform_path(filepath)

  local sidebar = require("avante").get()
  if not sidebar then
    require("avante.api").ask()
    sidebar = require("avante").get()
  end
  if not sidebar:is_open() then sidebar:open({}) end
  sidebar.file_selector:add_selected_file(rel_path)
end

function M.remove_selected_file(filepath)
  ---@diagnostic disable-next-line: undefined-field
  local stat = vim.uv.fs_stat(filepath)
  local files
  if stat and stat.type == "directory" then
    files = Utils.scan_directory({ directory = filepath, add_dirs = true })
  else
    files = { filepath }
  end

  local sidebar = require("avante").get()
  if not sidebar then
    require("avante.api").ask()
    sidebar = require("avante").get()
  end
  if not sidebar:is_open() then sidebar:open({}) end

  for _, file in ipairs(files) do
    local rel_path = Utils.uniform_path(file)
    sidebar.file_selector:remove_selected_file(rel_path)
  end
end

function M.stop() require("avante.llm").cancel_inflight_request() end

return setmetatable(M, {
  __index = function(t, k)
    local module = require("avante")
    ---@class AvailableApi: ApiCaller
    ---@field api? boolean
    local has = module[k]
    if type(has) ~= "table" or not has.api then
      Utils.warn(k .. " is not a valid avante's API method", { once = true })
      return
    end
    t[k] = has
    return t[k]
  end,
}) --[[@as avante.Api]]