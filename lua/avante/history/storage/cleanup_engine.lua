---🧹 Cleanup Engine for Avante history storage
---Handles automated history retention policies and cleanup operations

local Utils = require("avante.utils")
local Path = require("avante.path")

local M = {}

---@class avante.storage.CleanupEngine
---@field config table Cleanup configuration
---@field storage_engine table Storage engine instance
local CleanupEngine = {}
CleanupEngine.__index = CleanupEngine

---🏗️ Create new cleanup engine instance
---@param storage_engine table Storage engine to perform cleanup on
---@param config? table Cleanup configuration
---@return avante.storage.CleanupEngine
function M.new(storage_engine, config)
  config = config or {}
  
  local default_config = {
    enabled = config.enabled or false, -- 🧹 Enable automatic cleanup
    max_conversations = config.max_conversations or 1000, -- 📊 Maximum conversations per project
    max_age_days = config.max_age_days or 365, -- 📅 Archive conversations older than 1 year
    cleanup_interval_hours = config.cleanup_interval_hours or 24, -- ⏰ Run cleanup every 24 hours
    archive_path = config.archive_path, -- 📦 Custom archive path (uses base_path/archive if nil)
    dry_run = config.dry_run or false, -- 🧪 Test cleanup without making changes
    preserve_recent = config.preserve_recent or 10, -- 🔒 Always keep N most recent conversations
    size_threshold_mb = config.size_threshold_mb or 100, -- 📦 Archive projects larger than 100MB
    progress_callback = config.progress_callback, -- 📊 Progress reporting callback
  }
  
  local instance = {
    config = default_config,
    storage_engine = storage_engine,
    _cleanup_logs = {}, -- 📝 Track cleanup operations
    _archive_stats = {}, -- 📊 Archive operation statistics
  }
  
  return setmetatable(instance, CleanupEngine)
end

---📝 Log cleanup operation
---@param level string Log level ("info", "warn", "error")
---@param message string Log message
---@param details? table Additional details
function CleanupEngine:_log(level, message, details)
  local log_entry = {
    timestamp = Utils.get_timestamp(),
    level = level,
    message = message,
    details = details,
  }
  
  table.insert(self._cleanup_logs, log_entry)
  
  -- 🖥️ Also output to console
  if level == "error" then
    Utils.error("Cleanup: " .. message)
  elseif level == "warn" then
    Utils.warn("Cleanup: " .. message)
  else
    Utils.debug("Cleanup: " .. message)
  end
end

---📊 Report cleanup progress
---@param current number Current item being processed
---@param total number Total items to process
---@param operation string Current operation description
function CleanupEngine:_report_progress(current, total, operation)
  if self.config.progress_callback then
    local progress = {
      current = current,
      total = total,
      percentage = math.floor((current / total) * 100),
      operation = operation,
    }
    self.config.progress_callback(progress)
  else
    -- 📊 Simple console progress
    local percentage = math.floor((current / total) * 100)
    Utils.debug(string.format("Cleanup progress: %d%% (%d/%d) - %s", percentage, current, total, operation))
  end
end

---📅 Check if conversation should be archived based on age
---@param history_info table History metadata with created_at or updated_at
---@return boolean should_archive
---@return number age_days
function CleanupEngine:_should_archive_by_age(history_info)
  local cutoff_time = os.time() - (self.config.max_age_days * 24 * 60 * 60)
  local history_time = history_info.updated_at or history_info.created_at
  
  if not history_time then
    return false, 0 -- 📅 Can't determine age, don't archive
  end
  
  local parsed_time = Utils.parse_timestamp(history_time)
  if not parsed_time then
    return false, 0
  end
  
  local age_days = (os.time() - parsed_time) / (24 * 60 * 60)
  return parsed_time < cutoff_time, age_days
end

---📊 Check if project should be archived based on size
---@param project_name string
---@return boolean should_archive
---@return number size_mb
function CleanupEngine:_should_archive_by_size(project_name)
  if not self.config.size_threshold_mb then
    return false, 0
  end
  
  -- 📊 Get project statistics
  local stats, stats_error = self.storage_engine:get_stats(project_name)
  if stats_error or not stats.project then
    return false, 0
  end
  
  local size_mb = (stats.project.total_size_bytes or 0) / (1024 * 1024)
  return size_mb > self.config.size_threshold_mb, size_mb
end

---📦 Get archive directory path
---@param project_name string
---@return string archive_path
function CleanupEngine:_get_archive_path(project_name)
  local base_path = self.storage_engine.config.base_path
  if self.config.archive_path then
    return Utils.join_paths(self.config.archive_path, project_name)
  else
    return Utils.join_paths(base_path, project_name, "archive")
  end
end

---📦 Archive a conversation history
---@param history_info table History metadata
---@param project_name string
---@return boolean success
---@return string? error_message
function CleanupEngine:_archive_conversation(history_info, project_name)
  self:_log("info", "Archiving conversation", {
    history_id = history_info.uuid,
    project = project_name,
    age_days = history_info.age_days,
  })
  
  if self.config.dry_run then
    self:_log("info", "DRY RUN: Would archive conversation", { history_id = history_info.uuid })
    return true
  end
  
  -- 📖 Load full history
  local history, load_error = self.storage_engine:load(history_info.uuid, project_name)
  if not history then
    return false, "Failed to load history for archiving: " .. (load_error or "unknown error")
  end
  
  -- 📦 Ensure archive directory exists
  local archive_path = self:_get_archive_path(project_name)
  local success, mkdir_error = Path.mkdir(archive_path, true)
  if not success then
    return false, "Failed to create archive directory: " .. (mkdir_error or "unknown error")
  end
  
  -- 💾 Save to archive location
  local archive_file = Utils.join_paths(archive_path, history_info.uuid .. ".json")
  local archive_data = vim.json.encode(history)
  
  local file, file_error = io.open(archive_file, "w")
  if not file then
    return false, "Failed to create archive file: " .. (file_error or "unknown error")
  end
  
  local write_success, write_error = pcall(file.write, file, archive_data)
  file:close()
  
  if not write_success then
    return false, "Failed to write archive data: " .. (write_error or "unknown error")
  end
  
  -- 🗑️ Delete original history
  local delete_success, delete_error = self.storage_engine:delete(history_info.uuid, project_name)
  if not delete_success then
    -- 🧹 Clean up partial archive file
    os.remove(archive_file)
    return false, "Failed to delete original history: " .. (delete_error or "unknown error")
  end
  
  -- 📊 Update archive statistics
  self._archive_stats[project_name] = self._archive_stats[project_name] or {
    archived_count = 0,
    total_size_bytes = 0,
    last_archive_time = Utils.get_timestamp(),
  }
  
  self._archive_stats[project_name].archived_count = self._archive_stats[project_name].archived_count + 1
  self._archive_stats[project_name].total_size_bytes = self._archive_stats[project_name].total_size_bytes + #archive_data
  self._archive_stats[project_name].last_archive_time = Utils.get_timestamp()
  
  self:_log("info", "Successfully archived conversation", {
    history_id = history_info.uuid,
    archive_path = archive_file,
  })
  
  return true
end

---🧹 Perform cleanup for a single project
---@param project_name string Project to clean up
---@return boolean success
---@return table cleanup_summary
---@return string? error_message
function CleanupEngine:cleanup_project(project_name)
  self:_log("info", "Starting cleanup for project", { project = project_name })
  
  local cleanup_summary = {
    project_name = project_name,
    started_at = Utils.get_timestamp(),
    total_conversations = 0,
    archived_by_age = 0,
    archived_by_size = 0,
    archived_by_count = 0,
    preserved_recent = 0,
    errors = {},
    dry_run = self.config.dry_run,
  }
  
  -- 📋 Get all histories for the project
  local histories, list_error = self.storage_engine:list(project_name, { sort_by = "date", sort_order = "desc" })
  if list_error then
    return false, cleanup_summary, "Failed to list histories: " .. list_error
  end
  
  cleanup_summary.total_conversations = #histories
  
  if #histories == 0 then
    self:_log("info", "No conversations found for cleanup", { project = project_name })
    cleanup_summary.completed_at = Utils.get_timestamp()
    return true, cleanup_summary
  end
  
  -- 🔒 Preserve recent conversations
  local preserve_count = math.min(self.config.preserve_recent, #histories)
  local conversations_to_check = {}
  
  for i = preserve_count + 1, #histories do
    table.insert(conversations_to_check, histories[i])
  end
  
  cleanup_summary.preserved_recent = preserve_count
  
  -- 🧹 Process conversations for cleanup
  for i, history_info in ipairs(conversations_to_check) do
    self:_report_progress(i, #conversations_to_check, "Checking " .. (history_info.uuid or "unknown"))
    
    local should_archive = false
    local archive_reason = ""
    
    -- 📅 Check age-based archiving
    local archive_by_age, age_days = self:_should_archive_by_age(history_info)
    if archive_by_age then
      should_archive = true
      archive_reason = string.format("age (%.1f days)", age_days)
      history_info.age_days = age_days
    end
    
    -- 📊 Check size-based archiving (for the entire project)
    if not should_archive then
      local archive_by_size, size_mb = self:_should_archive_by_size(project_name)
      if archive_by_size and i <= (#conversations_to_check - self.config.preserve_recent) then
        should_archive = true
        archive_reason = string.format("project size (%.1f MB)", size_mb)
      end
    end
    
    -- 📊 Check count-based archiving
    if not should_archive and (#histories > self.config.max_conversations) then
      -- 📊 Archive oldest conversations beyond the limit
      local excess_count = #histories - self.config.max_conversations
      if i <= excess_count then
        should_archive = true
        archive_reason = "conversation count limit"
      end
    end
    
    -- 📦 Perform archiving if needed
    if should_archive then
      local archive_success, archive_error = self:_archive_conversation(history_info, project_name)
      if archive_success then
        if archive_reason:match("age") then
          cleanup_summary.archived_by_age = cleanup_summary.archived_by_age + 1
        elseif archive_reason:match("size") then
          cleanup_summary.archived_by_size = cleanup_summary.archived_by_size + 1
        elseif archive_reason:match("count") then
          cleanup_summary.archived_by_count = cleanup_summary.archived_by_count + 1
        end
      else
        table.insert(cleanup_summary.errors, {
          history_id = history_info.uuid,
          reason = archive_reason,
          error = archive_error,
        })
      end
    end
  end
  
  cleanup_summary.completed_at = Utils.get_timestamp()
  
  local total_archived = cleanup_summary.archived_by_age + cleanup_summary.archived_by_size + cleanup_summary.archived_by_count
  self:_log("info", "Cleanup completed for project", {
    project = project_name,
    total_archived = total_archived,
    errors = #cleanup_summary.errors,
  })
  
  local overall_success = #cleanup_summary.errors == 0
  return overall_success, cleanup_summary
end

---🧹 Perform cleanup across all projects
---@param project_names? string[] Optional list of projects to clean (cleans all if nil)
---@return table batch_cleanup_results
function CleanupEngine:cleanup_all_projects(project_names)
  local batch_results = {
    started_at = Utils.get_timestamp(),
    total_projects = 0,
    successful_projects = 0,
    failed_projects = 0,
    total_archived = 0,
    project_results = {},
    dry_run = self.config.dry_run,
  }
  
  -- 🔍 Determine projects to clean
  local projects = project_names
  if not projects then
    -- 📁 Get all projects (this would need to be implemented in storage engine)
    projects = self:_discover_all_projects()
  end
  
  batch_results.total_projects = #projects
  
  for i, project_name in ipairs(projects) do
    self:_report_progress(i, #projects, "Cleaning project " .. project_name)
    
    local success, summary, error = self:cleanup_project(project_name)
    batch_results.project_results[project_name] = {
      success = success,
      summary = summary,
      error = error,
    }
    
    if success then
      batch_results.successful_projects = batch_results.successful_projects + 1
      local archived = (summary.archived_by_age or 0) + (summary.archived_by_size or 0) + (summary.archived_by_count or 0)
      batch_results.total_archived = batch_results.total_archived + archived
    else
      batch_results.failed_projects = batch_results.failed_projects + 1
    end
  end
  
  batch_results.completed_at = Utils.get_timestamp()
  return batch_results
end

---🔍 Discover all projects that need cleanup
---@return string[] project_names
function CleanupEngine:_discover_all_projects()
  local projects = {}
  local base_path = self.storage_engine.config.base_path
  
  if vim.fn.isdirectory(base_path) == 0 then
    return projects
  end
  
  -- 🔍 Scan all subdirectories for projects
  for item in vim.fs.dir(base_path) do
    local item_path = Utils.join_paths(base_path, item)
    if vim.fn.isdirectory(item_path) == 1 then
      -- 📁 Check if this directory has a history subdirectory
      local history_path = Utils.join_paths(item_path, "history")
      if vim.fn.isdirectory(history_path) == 1 then
        table.insert(projects, item)
      end
    end
  end
  
  return projects
end

---📊 Get cleanup statistics and logs
---@return table stats
function CleanupEngine:get_stats()
  return {
    config = self.config,
    cleanup_logs = vim.deepcopy(self._cleanup_logs),
    archive_stats = vim.deepcopy(self._archive_stats),
  }
end

---🧹 Clear cleanup logs
function CleanupEngine:clear_logs()
  self._cleanup_logs = {}
end

---📦 Restore conversation from archive
---@param history_id string
---@param project_name string
---@return boolean success
---@return string? error_message
function CleanupEngine:restore_from_archive(history_id, project_name)
  local archive_path = self:_get_archive_path(project_name)
  local archive_file = Utils.join_paths(archive_path, history_id .. ".json")
  
  -- 📖 Read archived history
  local file = io.open(archive_file, "r")
  if not file then
    return false, "Archived history not found: " .. archive_file
  end
  
  local content = file:read("*all")
  file:close()
  
  if not content or content == "" then
    return false, "Archived history file is empty"
  end
  
  -- 🔄 Parse and restore
  local success, history = pcall(vim.json.decode, content)
  if not success then
    return false, "Failed to parse archived history: " .. (history or "unknown error")
  end
  
  -- 💾 Save back to main storage
  local restore_success, restore_error = self.storage_engine:save(history, project_name)
  if not restore_success then
    return false, "Failed to restore history: " .. (restore_error or "unknown error")
  end
  
  -- 🗑️ Remove from archive
  local remove_success, remove_error = os.remove(archive_file)
  if not remove_success then
    self:_log("warn", "Failed to remove archived file after restore", {
      archive_file = archive_file,
      error = remove_error,
    })
  end
  
  self:_log("info", "Successfully restored conversation from archive", {
    history_id = history_id,
    project = project_name,
  })
  
  return true
end

---📋 List archived conversations for a project
---@param project_name string
---@return table[] archived_histories
---@return string? error_message
function CleanupEngine:list_archived(project_name)
  local archive_path = self:_get_archive_path(project_name)
  local archived = {}
  
  if vim.fn.isdirectory(archive_path) == 0 then
    return archived, nil -- 📁 No archive directory
  end
  
  -- 🔍 Scan archive directory
  for item in vim.fs.dir(archive_path) do
    if string.match(item, "%.json$") then
      local history_id = string.match(item, "(.+)%.json$")
      if history_id then
        local file_path = Utils.join_paths(archive_path, item)
        local stat = vim.loop.fs_stat(file_path)
        if stat then
          table.insert(archived, {
            uuid = history_id,
            archived_at = os.date("!%Y-%m-%dT%H:%M:%SZ", stat.mtime.sec),
            size_bytes = stat.size,
            archive_file = file_path,
          })
        end
      end
    end
  end
  
  -- 📊 Sort by archive time (newest first)
  table.sort(archived, function(a, b)
    return a.archived_at > b.archived_at
  end)
  
  return archived
end

return M