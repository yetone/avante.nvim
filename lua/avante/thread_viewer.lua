local History = require("avante.history")
local Utils = require("avante.utils")
local Path = require("avante.path")
local PlPath = require("plenary.path")
local ACPClient = require("avante.libs.acp_client")
local Config = require("avante.config")
local EnvUtils = require("avante.utils.environment")

---@class avante.ThreadViewer
local M = {}

-- Cache for external session info
local _external_sessions_cache = nil
local _acp_client_cache = nil
local _acp_available = nil

---Get cached external session info by session ID
---@param session_id string
---@return table|nil
function M.get_external_session_info(session_id)
  if not _external_sessions_cache then
    -- Use legacy filesystem scan for synchronous access
    _external_sessions_cache = scan_external_acp_sessions_legacy()
  end
  
  for _, session_info in ipairs(_external_sessions_cache) do
    if session_info.session_id == session_id then
      return session_info
    end
  end
  
  return nil
end

---Clear the external sessions cache
function M.clear_cache()
  _external_sessions_cache = nil
  _acp_available = nil
end

---Get or create a shared ACP client for listing sessions
---@return avante.acp.ACPClient|nil, string|nil error
local function get_or_create_acp_client()
  -- Return cached result if we already know ACP is unavailable
  if _acp_available == false then
    return nil, "ACP unavailable (cached)"
  end

  -- Return cached client if available and connected
  if _acp_client_cache and _acp_client_cache:is_connected() then
    return _acp_client_cache, nil
  end

  -- Create new ACP client
  local provider_config = Config.providers and Config.providers["claude"]
  if not provider_config or not provider_config.acp_args then
    _acp_available = false
    return nil, "ACP not configured"
  end

  -- Get current working directory and resolve environment variables with path-based overrides
  local cwd = vim.fn.getcwd()
  local resolved_env = EnvUtils.merge_env_with_overrides(
    provider_config.acp_args.env or {},
    provider_config.acp_args.envOverrides,
    cwd
  )

  local client = ACPClient:new({
    transport_type = "stdio",
    command = provider_config.acp_args.command,
    args = provider_config.acp_args.args or {},
    env = resolved_env,
    timeout = 5000,
  })

  -- Try to connect with timeout
  local connect_err = nil
  local connected = false

  client:connect(function(err)
    if err then
      connect_err = err
    else
      connected = true
    end
  end)

  -- Wait up to 5 seconds for connection
  local start_time = vim.loop.now()
  while not connected and not connect_err and (vim.loop.now() - start_time) < 5000 do
    vim.wait(100)
  end

  if not connected or connect_err then
    _acp_available = false
    return nil, "Failed to connect to ACP: " .. (connect_err and connect_err.message or "timeout")
  end

  _acp_client_cache = client
  _acp_available = true
  return client, nil
end

---Scan external ACP session directories for sessions (legacy fallback)
---@return table[] -- Array of session info {path: string, session_id: string, mtime: number}
local function scan_external_acp_sessions_legacy()
  local sessions = {}
  
  -- Known ACP cache directories
  local acp_cache_dirs = {
    vim.fn.expand("~/.cache/claude-code-acp"),
    vim.fn.expand("~/Library/Caches/claude-code-acp"),
  }
  
  for _, cache_dir in ipairs(acp_cache_dirs) do
    local cache_path = PlPath:new(cache_dir)
    if cache_path:exists() and cache_path:is_dir() then
      -- List all session directories
      local session_dirs = vim.fn.glob(tostring(cache_path:joinpath("*")), true, true)
      for _, session_dir in ipairs(session_dirs) do
        local session_path = PlPath:new(session_dir)
        if session_path:is_dir() then
          -- Extract working directory from the encoded directory name
          local dir_name = session_path:basename()
          -- Decode the directory name (it's URL-encoded with - instead of /)
          local working_dir = dir_name:gsub("%-", "/")
          
          -- Get session modification time
          local stat = vim.loop.fs_stat(session_dir)
          local mtime = stat and stat.mtime.sec or 0
          
          -- Look for session state files
          local state_file = session_path:joinpath("state.json")
          local session_id = nil
          
          if state_file:exists() then
            local content = state_file:read()
            if content then
              local ok, state = pcall(vim.json.decode, content)
              if ok and state then
                session_id = state.session_id or state.sessionId
              end
            end
          end
          
          -- If no explicit session ID, use directory name as identifier
          if not session_id then
            session_id = dir_name
          end
          
          table.insert(sessions, {
            path = session_dir,
            session_id = session_id,
            working_directory = working_dir,
            mtime = mtime,
          })
        end
      end
    end
  end
  
  return sessions
end

---Fetch sessions from claude-code via ACP protocol
---@param callback fun(sessions: table[])
local function fetch_sessions_from_acp(callback)
  local client, err = get_or_create_acp_client()
  
  if not client then
    -- ACP not available, just use filesystem scanning
    Utils.debug("ACP client unavailable: " .. (err or "unknown") .. " - using filesystem scan")
    callback(scan_external_acp_sessions_legacy())
    return
  end

  Utils.debug("Fetching sessions via ACP...")
  client:list_sessions(function(sessions, list_err)
    if list_err then
      Utils.warn("Failed to list sessions via ACP: " .. (list_err.message or "unknown error"))
      Utils.debug("ACP error details: " .. vim.inspect(list_err))
      -- Fall back to filesystem scanning
      callback(scan_external_acp_sessions_legacy())
      return
    end
    
    if not sessions then
      Utils.warn("ACP returned no sessions (nil)")
      callback(scan_external_acp_sessions_legacy())
      return
    end

    Utils.info("ACP returned " .. #sessions .. " sessions")
    Utils.debug("Raw ACP sessions: " .. vim.inspect(sessions))

    -- Transform ACP session format to our internal format
    local transformed_sessions = {}
    for _, acp_session in ipairs(sessions) do
      table.insert(transformed_sessions, {
        session_id = acp_session.sessionId or acp_session.session_id,
        working_directory = acp_session.cwd or acp_session.workingDirectory or "unknown",
        mtime = acp_session.lastModified or acp_session.last_modified or os.time(),
        message_count = acp_session.messageCount or acp_session.message_count or 0,
        title = acp_session.title or acp_session.name or nil, -- Capture title from ACP response
        path = nil, -- ACP sessions don't have a local path
      })
    end

    Utils.info("Transformed " .. #transformed_sessions .. " ACP sessions")
    
    -- If ACP returned nothing, fall back to filesystem
    if #transformed_sessions == 0 then
      Utils.info("No ACP sessions found, falling back to filesystem scan")
      callback(scan_external_acp_sessions_legacy())
      return
    end
    
    callback(transformed_sessions)
  end)
end

---Scan external ACP sessions (async, uses ACP when available)
---@param callback fun(sessions: table[])
local function scan_external_acp_sessions(callback)
  fetch_sessions_from_acp(callback)
end

---Create a synthetic history entry for an external ACP session
---@param session_info table
---@return avante.ChatHistory
local function create_synthetic_history(session_info)
  -- Use the title from ACP if available, otherwise fall back to generic name
  local title = session_info.title or "External ACP Session"
  
  return {
    title = title,
    timestamp = os.date("%Y-%m-%d %H:%M:%S", session_info.mtime),
    messages = {},
    entries = {},
    todos = {},
    memory = nil,
    filename = "__external_acp_" .. session_info.session_id,
    system_prompt = nil,
    tokens_usage = nil,
    acp_session_id = session_info.session_id,
    working_directory = session_info.working_directory,
    selected_files = nil,
    _is_external = true,
  }
end

---@param history avante.ChatHistory
---@return string
local function format_thread_entry(history)
  local messages = History.get_history_messages(history)
  local timestamp = #messages > 0 and messages[#messages].timestamp or history.timestamp
  local working_dir = history.working_directory or "unknown"
  
  -- Extract just the directory name for display
  local dir_name = working_dir:match("([^/]+)$") or working_dir
  
  -- Add ACP indicator if this is an ACP session
  local acp_indicator = history.acp_session_id and " [ACP]" or ""
  
  -- Format: [dir_name] title - timestamp (msg_count messages) [ACP]
  return string.format("[%s] %s - %s (%d)%s", 
    dir_name, 
    history.title, 
    timestamp, 
    #messages,
    acp_indicator
  )
end

---Show telescope picker with histories
---@param histories table[]
---@param bufnr integer
---@param cb fun(filename: string)
---@param pickers table
---@param finders table
---@param conf table
---@param actions table
---@param action_state table
---@param previewers table
local function show_telescope_picker(histories, bufnr, cb, pickers, finders, conf, actions, action_state, previewers)
  if #histories == 0 then
    Utils.warn("No thread history found.")
    return
  end

  -- Create entries for telescope
  local entries = {}
  
  -- Add "Create New Thread" as the first entry
  table.insert(entries, {
    value = "__create_new__",
    display = "[+] Create New Thread",
    ordinal = "[+] Create New Thread",
    is_new_thread = true,
  })
  
  for _, history in ipairs(histories) do
    local display_text = format_thread_entry(history)
    -- Add [EXTERNAL] tag for sessions without Avante history
    if history._is_external then
      display_text = display_text .. " [EXTERNAL]"
    end
    
    table.insert(entries, {
      value = history.filename,
      display = display_text,
      ordinal = display_text,
      history = history,
    })
  end

  pickers
    .new({}, {
      prompt_title = "Avante Threads",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return entry
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = "Thread Preview",
        define_preview = function(self, entry)
          local preview_lines = {}
          
          -- Handle "Create New Thread" entry
          if entry.is_new_thread then
            table.insert(preview_lines, "# Create New Thread")
            table.insert(preview_lines, "")
            table.insert(preview_lines, "Start a fresh conversation with a new thread.")
            table.insert(preview_lines, "")
            table.insert(preview_lines, "Press **Enter** to create a new thread.")
            
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
            vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
            return
          end
          
          local history = entry.history
          local Sidebar = require("avante.sidebar")
          local content = Sidebar.render_history_content(history)
          
          -- Add directory context at the top
          if history.working_directory then
            table.insert(preview_lines, "**Working Directory:** " .. history.working_directory)
            table.insert(preview_lines, "")
          end
          if history.acp_session_id then
            table.insert(preview_lines, "**ACP Session ID:** " .. history.acp_session_id)
            table.insert(preview_lines, "")
          end
          table.insert(preview_lines, "---")
          table.insert(preview_lines, "")
          
          -- Append the actual content
          for line in content:gmatch("[^\r\n]+") do
            table.insert(preview_lines, line)
          end
          
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
          vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          -- Wrap close in pcall to handle potential autocmd errors
          pcall(actions.close, prompt_bufnr)
          if selection then
            vim.schedule(function()
              -- Handle "Create New Thread"
              if selection.is_new_thread then
                -- Create a new thread by calling AvanteChatNew
                vim.cmd("AvanteChatNew")
                return
              end
              
              -- Handle existing threads
              if cb then
                -- Pass external session ID if this is an external session
                local external_session_id = nil
                if selection.history and selection.history._is_external then
                  external_session_id = selection.history.acp_session_id
                end
                cb(selection.value, external_session_id)
              end
            end)
          end
        end)

        -- Add delete mapping with 'd'
        map("n", "d", function()
          local selection = action_state.get_selected_entry()
          if selection then
            Path.history.delete(bufnr, selection.value)
            Utils.info("Deleted thread: " .. selection.display)
            -- Wrap close in pcall to handle potential autocmd errors
            pcall(actions.close, prompt_bufnr)
            -- Reopen the picker to refresh (with slight delay to avoid conflicts)
            vim.schedule(function()
              M.open_with_telescope(bufnr, cb)
            end)
          end
        end)

        return true
      end,
    })
    :find()
end

---@param bufnr integer
---@param cb fun(filename: string)
function M.open_with_telescope(bufnr, cb)
  local has_telescope, _ = pcall(require, "telescope")
  if not has_telescope then
    Utils.warn("Telescope is not installed. Please install telescope.nvim to use :AvanteThreads")
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  -- Load histories from all projects, not just current
  local histories = Path.history.list_all()

  -- Fetch external ACP sessions asynchronously
  scan_external_acp_sessions(function(external_sessions)
    -- Create deduplicated map by session ID
    local session_map = {}
    
    -- First, add all local histories (they have priority - more complete info)
    for _, history in ipairs(histories) do
      local session_id = history.acp_session_id
      if session_id then
        -- Use session_id as key
        if not session_map[session_id] then
          session_map[session_id] = history
          Utils.debug("Added local history with session_id: " .. session_id)
        else
          -- Session already exists - check if we should update
          -- Prefer histories with more messages
          local existing_msg_count = #(History.get_history_messages(session_map[session_id]))
          local new_msg_count = #(History.get_history_messages(history))
          if new_msg_count > existing_msg_count then
            Utils.debug("Replacing session " .. session_id .. " with more complete history (" .. new_msg_count .. " vs " .. existing_msg_count .. " messages)")
            session_map[session_id] = history
          else
            Utils.debug("Skipping duplicate session: " .. session_id)
          end
        end
      else
        -- No session_id (legacy history), use filename as key
        local key = history.filename or tostring(history)
        if not session_map[key] then
          session_map[key] = history
          Utils.debug("Added legacy history: " .. key)
        end
      end
    end
    
    -- Now add external sessions that don't exist in local histories
    for _, session_info in ipairs(external_sessions) do
      local session_id = session_info.session_id
      if not session_map[session_id] then
        local synthetic_history = create_synthetic_history(session_info)
        session_map[session_id] = synthetic_history
        Utils.debug("Added external ACP session: " .. session_id)
      else
        Utils.debug("Skipping external session already in local histories: " .. session_id)
      end
    end
    
    -- Convert map back to array
    local deduplicated_histories = {}
    for _, history in pairs(session_map) do
      table.insert(deduplicated_histories, history)
    end
    
    -- Sort by timestamp (most recent first)
    table.sort(deduplicated_histories, function(a, b)
      local a_msgs = History.get_history_messages(a)
      local b_msgs = History.get_history_messages(b)
      local a_time = #a_msgs > 0 and a_msgs[#a_msgs].timestamp or a.timestamp
      local b_time = #b_msgs > 0 and b_msgs[#b_msgs].timestamp or b.timestamp
      return a_time > b_time
    end)
    
    Utils.info("Loaded " .. #deduplicated_histories .. " unique threads (deduplicated from " .. #histories .. " local + " .. #external_sessions .. " external)")
    
    -- Continue with telescope picker inside the callback
    vim.schedule(function()
      show_telescope_picker(deduplicated_histories, bufnr, cb, pickers, finders, conf, actions, action_state, previewers)
    end)
  end)
end

---@param bufnr integer
---@param cb fun(filename: string)
function M.open(bufnr, cb)
  -- Try to use telescope first, fall back to native selector
  local has_telescope, _ = pcall(require, "telescope")
  
  if has_telescope then
    M.open_with_telescope(bufnr, cb)
  else
    -- Fall back to the native history selector
    require("avante.history_selector").open(bufnr, cb)
  end
end

return M