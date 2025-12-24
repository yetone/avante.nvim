local History = require("avante.history")
local Utils = require("avante.utils")
local Path = require("avante.path")
local PlPath = require("plenary.path")

---@class avante.ThreadViewer
local M = {}

-- Cache for external session info
local _external_sessions_cache = nil

---Get cached external session info by session ID
---@param session_id string
---@return table|nil
function M.get_external_session_info(session_id)
  if not _external_sessions_cache then
    _external_sessions_cache = scan_external_acp_sessions()
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
end

---Scan external ACP session directories for sessions
---@return table[] -- Array of session info {path: string, session_id: string, mtime: number}
local function scan_external_acp_sessions()
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

---Create a synthetic history entry for an external ACP session
---@param session_info table
---@return avante.ChatHistory
local function create_synthetic_history(session_info)
  return {
    title = "External ACP Session",
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

  local histories = Path.history.list(bufnr)
  
  -- Scan for external ACP sessions
  local external_sessions = scan_external_acp_sessions()
  
  -- Create a map of existing ACP session IDs from Avante histories
  local existing_acp_sessions = {}
  for _, history in ipairs(histories) do
    if history.acp_session_id then
      existing_acp_sessions[history.acp_session_id] = true
    end
  end
  
  -- Add external sessions that don't have Avante histories
  for _, session_info in ipairs(external_sessions) do
    if not existing_acp_sessions[session_info.session_id] then
      local synthetic_history = create_synthetic_history(session_info)
      table.insert(histories, synthetic_history)
    end
  end
  
  if #histories == 0 then
    Utils.warn("No thread history found.")
    return
  end

  -- Create entries for telescope
  local entries = {}
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
          local history = entry.history
          local Sidebar = require("avante.sidebar")
          local content = Sidebar.render_history_content(history)
          
          -- Add directory context at the top
          local preview_lines = {}
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
          if selection and cb then
            vim.schedule(function()
              -- Pass external session ID if this is an external session
              local external_session_id = nil
              if selection.history._is_external then
                external_session_id = selection.history.acp_session_id
              end
              cb(selection.value, external_session_id)
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