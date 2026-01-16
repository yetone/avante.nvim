local Path = require("plenary.path")
local Config = require("avante.config")
local Utils = require("avante.utils")

---@class avante.SessionManager
local M = {}

---@class avante.SessionState
---@field session_id string
---@field project_root string
---@field working_directory string
---@field provider string
---@field timestamp string
---@field history_filename string
---@field selected_files string[]
---@field acp_session_id string | nil
---@field todos avante.TODO[]
---@field last_user_input string | nil
---@field current_mode_id string | nil

---Get the session storage directory
---@return Path
local function get_session_dir()
  local session_path = Path:new(Config.history.storage_path):joinpath("sessions")
  if not session_path:exists() then
    session_path:mkdir({ parents = true })
  end
  return session_path
end

---Generate a session ID based on project and timestamp
---@param project_root string
---@return string
local function generate_session_id(project_root)
  local timestamp = os.time()
  local hash = vim.fn.sha256(project_root .. timestamp)
  return hash:sub(1, 12)
end

---Get the session file path for a project
---@param project_root string
---@return Path
local function get_session_file(project_root)
  local project_hash = vim.fn.sha256(project_root):sub(1, 12)
  return get_session_dir():joinpath(project_hash .. ".json")
end

---Save current session state
---@param sidebar avante.Sidebar
---@return boolean success
function M.save_session(sidebar)
  if not sidebar or not sidebar.code or not sidebar.code.bufnr then
    return false
  end

  local project_root = Utils.root.get({ buf = sidebar.code.bufnr })
  local session_file = get_session_file(project_root)

  ---@type avante.SessionState
  local session_state = {
    session_id = generate_session_id(project_root),
    project_root = project_root,
    working_directory = vim.fn.getcwd(),
    provider = Config.provider,
    timestamp = Utils.get_timestamp(),
    history_filename = sidebar.chat_history and sidebar.chat_history.filename or nil,
    selected_files = {},
    acp_session_id = sidebar.chat_history and sidebar.chat_history.acp_session_id or nil,
    todos = sidebar.chat_history and sidebar.chat_history.todos or {},
    last_user_input = nil,
    current_mode_id = sidebar.current_mode_id,
  }

  -- Get selected files
  if sidebar.file_selector and sidebar.file_selector.selected_files then
    for _, file in ipairs(sidebar.file_selector.selected_files) do
      table.insert(session_state.selected_files, file.path)
    end
  end

  -- Save to disk
  local ok, encoded = pcall(vim.json.encode, session_state)
  if not ok then
    Utils.error("Failed to encode session state: " .. tostring(encoded))
    return false
  end

  session_file:write(encoded, "w")
  Utils.debug("Saved session state to " .. tostring(session_file))
  return true
end

---Load session state for current project
---@param bufnr integer
---@return avante.SessionState | nil
function M.load_session(bufnr)
  local project_root = Utils.root.get({ buf = bufnr })
  local session_file = get_session_file(project_root)

  if not session_file:exists() then
    return nil
  end

  local content = session_file:read()
  if not content then
    return nil
  end

  local ok, session_state = pcall(vim.json.decode, content)
  if not ok then
    Utils.warn("Failed to decode session state: " .. tostring(session_state))
    return nil
  end

  Utils.debug("Loaded session state from " .. tostring(session_file))
  return session_state
end

---Restore session state to sidebar
---@param sidebar avante.Sidebar
---@param session_state avante.SessionState
---@return boolean success
function M.restore_session(sidebar, session_state)
  if not sidebar or not session_state then
    return false
  end

  -- Restore selected files
  if session_state.selected_files then
    for _, filepath in ipairs(session_state.selected_files) do
      if sidebar.file_selector then
        sidebar.file_selector:add_selected_file(filepath)
      end
    end
  end

  -- Restore current mode (nil if not set - will be initialized from ACP client)
  sidebar.current_mode_id = session_state.current_mode_id

  -- Restore history if available
  if session_state.history_filename then
    local PathModule = require("avante.path")
    local history = PathModule.history.load(sidebar.code.bufnr, session_state.history_filename)
    if history then
      sidebar.chat_history = history
      sidebar:update_content_with_history()

      -- Restore todos
      if session_state.todos and #session_state.todos > 0 then
        sidebar.chat_history.todos = session_state.todos
        sidebar:create_todos_container()
      end
    end
  end

  -- Change to the saved working directory
  if session_state.working_directory and vim.fn.isdirectory(session_state.working_directory) == 1 then
    vim.cmd("cd " .. vim.fn.fnameescape(session_state.working_directory))
  end

  Utils.info(string.format("Restored session from %s", session_state.timestamp))
  return true
end

---Delete session state for current project
---@param bufnr integer
---@return boolean success
function M.delete_session(bufnr)
  local project_root = Utils.root.get({ buf = bufnr })
  local session_file = get_session_file(project_root)

  if not session_file:exists() then
    return false
  end

  session_file:rm()
  Utils.info("Deleted saved session")
  return true
end

---Check if session exists for current project
---@param bufnr integer
---@return boolean
function M.has_session(bufnr)
  local project_root = Utils.root.get({ buf = bufnr })
  local session_file = get_session_file(project_root)
  return session_file:exists()
end

---List all saved sessions
---@return table<string, avante.SessionState>
function M.list_sessions()
  local session_dir = get_session_dir()
  local sessions = {}

  if not session_dir:exists() then
    return sessions
  end

  local files = vim.fn.glob(tostring(session_dir:joinpath("*.json")), true, true)
  for _, filepath in ipairs(files) do
    local file = Path:new(filepath)
    local content = file:read()
    if content then
      local ok, session_state = pcall(vim.json.decode, content)
      if ok then
        sessions[session_state.project_root] = session_state
      end
    end
  end

  return sessions
end

return M