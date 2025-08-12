local fn = vim.fn
local Utils = require("avante.utils")
local Path = require("plenary.path")
local Scan = require("plenary.scandir")
local Config = require("avante.config")

---@class avante.Path
---@field history_path Path
---@field cache_path Path
---@field data_path Path
local P = {}

---@param bufnr integer | nil
---@return string dirname
local function generate_project_dirname_in_storage(bufnr)
  local project_root = Utils.root.get({
    buf = bufnr,
  })
  -- Replace path separators with double underscores
  local path_with_separators = string.gsub(project_root, "/", "__")
  -- Replace other non-alphanumeric characters with single underscores
  local dirname = string.gsub(path_with_separators, "[^A-Za-z0-9._]", "_")
  return tostring(Path:new("projects"):joinpath(dirname))
end

local function filepath_to_filename(filepath) return tostring(filepath):sub(tostring(filepath:parent()):len() + 2) end

-- History path
local History = {}

function History.get_history_dir(bufnr)
  local dirname = generate_project_dirname_in_storage(bufnr)
  local history_dir = Path:new(Config.history.storage_path):joinpath(dirname):joinpath("history")
  if not history_dir:exists() then history_dir:mkdir({ parents = true }) end
  return history_dir
end

-- 📊 Enhanced history listing with caching and lazy loading
---@return avante.ChatHistory[]
function History.list(bufnr)
  local history_dir = History.get_history_dir(bufnr)
  local files = vim.fn.glob(tostring(history_dir:joinpath("*.json")), true, true)
  local latest_filename = History.get_latest_filename(bufnr, false)
  local res = {}
  
  -- 🚀 Performance optimization: Load only metadata for sorting, full content on demand
  for _, filename in ipairs(files) do
    if not filename:match("metadata.json") then
      local filepath = Path:new(filename)
      
      -- 📊 Try to load minimal metadata first for performance
      local ok, history = pcall(function()
        local content = filepath:read()
        local data = vim.json.decode(content)
        
        -- 🔄 Handle auto-migration during listing (lightweight check only)
        if data.entries and not data.messages then
          -- 📝 For listing, just extract basic metadata without full conversion
          local entry_count = #(data.entries or {})
          local last_entry = entry_count > 0 and data.entries[entry_count] or nil
          
          return {
            title = data.title or "untitled",
            timestamp = last_entry and last_entry.timestamp or data.timestamp,
            filename = filepath_to_filename(filepath),
            entries = data.entries, -- Keep for compatibility
            messages = nil, -- Will be loaded on-demand
            _is_legacy_format = true, -- Mark for lazy migration
            _entry_count = entry_count,
          }
        else
          -- ✅ Unified format - use existing timestamp logic
          return {
            title = data.title or "untitled", 
            timestamp = data.timestamp,
            filename = filepath_to_filename(filepath),
            messages = data.messages,
            version = data.version,
            migration_metadata = data.migration_metadata,
            _is_unified_format = true,
            _message_count = data.messages and #data.messages or 0,
          }
        end
      end)
      
      if ok and history then
        table.insert(res, history)
      else
        Utils.warn("⚠️  Failed to load history file for listing: " .. filename)
      end
    end
  end
  
  -- 📊 Optimized sorting with cached timestamp extraction
  table.sort(res, function(a, b)
    -- 🥇 Latest file always comes first
    if a.filename == latest_filename then return true end
    if b.filename == latest_filename then return false end
    
    -- 🔄 Extract timestamps efficiently
    local function get_sort_timestamp(history)
      if history._is_unified_format and history.messages and #history.messages > 0 then
        return history.messages[#history.messages].timestamp
      elseif history._is_legacy_format and history.entries and #history.entries > 0 then
        return history.entries[#history.entries].timestamp
      else
        return history.timestamp or "0"
      end
    end
    
    local timestamp_a = get_sort_timestamp(a)
    local timestamp_b = get_sort_timestamp(b)
    
    return timestamp_a > timestamp_b
  end)
  
  Utils.debug(string.format("📊 Listed %d history files (%d legacy, %d unified)", 
                           #res,
                           vim.tbl_count(res, function(h) return h._is_legacy_format end),
                           vim.tbl_count(res, function(h) return h._is_unified_format end)))
  
  return res
end

-- Get a chat history file name given a buffer
---@param bufnr integer
---@param new boolean
---@return Path
function History.get_latest_filepath(bufnr, new)
  local history_dir = History.get_history_dir(bufnr)
  local filename = History.get_latest_filename(bufnr, new)
  return history_dir:joinpath(filename)
end

function History.get_filepath(bufnr, filename)
  local history_dir = History.get_history_dir(bufnr)
  return history_dir:joinpath(filename)
end

function History.get_metadata_filepath(bufnr)
  local history_dir = History.get_history_dir(bufnr)
  return history_dir:joinpath("metadata.json")
end

function History.get_latest_filename(bufnr, new)
  local history_dir = History.get_history_dir(bufnr)
  local filename
  local metadata_filepath = History.get_metadata_filepath(bufnr)
  if metadata_filepath:exists() and not new then
    local metadata_content = metadata_filepath:read()
    local metadata = vim.json.decode(metadata_content)
    filename = metadata.latest_filename
  end
  if not filename or filename == "" then
    local pattern = tostring(history_dir:joinpath("*.json"))
    local files = vim.fn.glob(pattern, true, true)
    filename = #files .. ".json"
    if #files > 0 and not new then filename = (#files - 1) .. ".json" end
  end
  return filename
end

function History.save_latest_filename(bufnr, filename)
  local metadata_filepath = History.get_metadata_filepath(bufnr)
  local metadata
  if not metadata_filepath:exists() then
    metadata = {}
  else
    local metadata_content = metadata_filepath:read()
    metadata = vim.json.decode(metadata_content)
  end
  metadata.latest_filename = filename
  metadata_filepath:write(vim.json.encode(metadata), "w")
end

---@param bufnr integer
function History.new(bufnr)
  local filepath = History.get_latest_filepath(bufnr, true)
  ---@type avante.ChatHistory
  local history = {
    title = "untitled",
    timestamp = Utils.get_timestamp(),
    messages = {},
    filename = filepath_to_filename(filepath),
  }
  return history
end

-- 📚 Enhanced history loading with caching, unified format support and auto-migration
---@param bufnr integer
---@param filename string?
---@return avante.ChatHistory | avante.UnifiedChatHistory
function History.load(bufnr, filename)
  local history_filepath = filename and History.get_filepath(bufnr, filename)
    or History.get_latest_filepath(bufnr, false)
  
  if history_filepath:exists() then
    local content = history_filepath:read()
    if content ~= nil then
      -- 🚀 Check cache first for performance
      local Cache = require("avante.history.cache")
      local cached_history, cache_hit = Cache.get(tostring(history_filepath), content)
      
      if cache_hit then
        cached_history.filename = filepath_to_filename(history_filepath)
        Utils.debug("🎯 Loaded history from cache")
        return cached_history
      end
      
      -- 📝 Parse history from file
      local history = vim.json.decode(content)
      history.filename = filepath_to_filename(history_filepath)
      
      -- 🔄 Attempt auto-migration for legacy format
      local AutoMigrator = require("avante.history.auto_migrator")
      local migrated_history, was_migrated = AutoMigrator.auto_migrate_on_load(history, history_filepath)
      
      local final_history = was_migrated and migrated_history or history
      
      if was_migrated then
        Utils.info("✅ Auto-migrated history file to unified format")
        final_history.filename = filepath_to_filename(history_filepath)
        -- 🔄 Update content for cache with migrated version
        content = history_filepath:read() -- Re-read migrated content
      end
      
      -- 💾 Cache the final result for future loads
      Cache.set(tostring(history_filepath), final_history, content)
      
      return final_history
    end
  end
  return History.new(bufnr)
end

-- 💾 Enhanced history saving with atomic operations and unified format support
---@param bufnr integer
---@param history avante.ChatHistory | avante.UnifiedChatHistory
History.save = function(bufnr, history)
  local history_filepath = History.get_filepath(bufnr, history.filename)
  
  -- 🚀 Use atomic storage for safe writes
  local AtomicStorage = require("avante.history.atomic_storage")
  local operation_id = Utils.uuid()
  
  -- 📊 Ensure unified format for new saves
  if not history.version or history.version < 2 then
    Utils.debug("🔄 Upgrading history to unified format during save")
    history.version = 2
    if not history.migration_metadata then
      local Migration = require("avante.history.migration")
      history.migration_metadata = Migration.create_migration_metadata("upgraded_on_save", nil)
    end
  end
  
  local result = AtomicStorage.atomic_write(
    history_filepath,
    vim.json.encode(history),
    operation_id,
    false -- Don't create backup for regular saves
  )
  
  if result.success then
    History.save_latest_filename(bufnr, history.filename)
    Utils.debug(string.format("💾 Saved history atomically in %.1fms", result.duration_ms))
  else
    Utils.error("❌ Failed to save history: " .. (result.error or "unknown error"))
    error("History save failed: " .. (result.error or "unknown error"))
  end
end

--- Deletes a specific chat history file.
---@param bufnr integer
---@param filename string
function History.delete(bufnr, filename)
  local history_filepath = History.get_filepath(bufnr, filename)
  if history_filepath:exists() then
    local was_latest = (filename == History.get_latest_filename(bufnr, false))
    history_filepath:rm()

    if was_latest then
      local remaining_histories = History.list(bufnr) -- This list is sorted by recency
      if #remaining_histories > 0 then
        History.save_latest_filename(bufnr, remaining_histories[1].filename)
      else
        -- No histories left, clear the latest_filename from metadata
        local metadata_filepath = History.get_metadata_filepath(bufnr)
        if metadata_filepath:exists() then
          local metadata_content = metadata_filepath:read()
          local metadata = vim.json.decode(metadata_content)
          metadata.latest_filename = nil -- Or "", depending on desired behavior for an empty latest
          metadata_filepath:write(vim.json.encode(metadata), "w")
        end
      end
    end
  else
    Utils.warn("History file not found: " .. tostring(history_filepath))
  end
end

P.history = History

-- Prompt path
local Prompt = {}

-- Given a mode, return the file name for the custom prompt.
---@param mode AvanteLlmMode
---@return string
function Prompt.get_custom_prompts_filepath(mode) return string.format("custom.%s.avanterules", mode) end

function Prompt.get_builtin_prompts_filepath(mode) return string.format("%s.avanterules", mode) end

---@class AvanteTemplates
---@field initialize fun(cache_directory: string, project_directory: string): nil
---@field render fun(template: string, context: AvanteTemplateOptions): string
local _templates_lib = nil

Prompt.custom_modes = {
  agentic = true,
  legacy = true,
  editing = true,
  suggesting = true,
}

Prompt.custom_prompts_contents = {}

---@param project_root string
---@return string templates_dir
function Prompt.get_templates_dir(project_root)
  if not P.available() then error("Make sure to build avante (missing avante_templates)", 2) end

  -- get root directory of given bufnr
  local directory = Path:new(project_root)
  if Utils.get_os_name() == "windows" then directory = Path:new(directory:absolute():gsub("^%a:", "")[1]) end
  ---@cast directory Path
  ---@type Path
  local cache_prompt_dir = P.cache_path:joinpath(directory)
  if not cache_prompt_dir:exists() then cache_prompt_dir:mkdir({ parents = true }) end

  local function find_rules(dir)
    if not dir then return end
    if vim.fn.isdirectory(dir) ~= 1 then return end

    local scanner = Scan.scan_dir(dir, { depth = 1, add_dirs = true })
    for _, entry in ipairs(scanner) do
      local file = Path:new(entry)
      if file:is_file() then
        local pieces = vim.split(entry, "/")
        local piece = pieces[#pieces]
        local mode = piece:match("([^.]+)%.avanterules$")
        if not mode or not Prompt.custom_modes[mode] then goto continue end
        if Prompt.custom_prompts_contents[mode] == nil then
          Utils.info(string.format("Using %s as %s system prompt", entry, mode))
          Prompt.custom_prompts_contents[mode] = file:read()
        end
      end
      ::continue::
    end
  end

  if Config.rules.project_dir then
    local project_rules_path = Path:new(Config.rules.project_dir)
    if not project_rules_path:is_absolute() then project_rules_path = directory:joinpath(project_rules_path) end
    find_rules(tostring(project_rules_path))
  end
  find_rules(Config.rules.global_dir)
  find_rules(directory:absolute())

  local source_dir =
    Path:new(debug.getinfo(1).source:match("@?(.*/)"):gsub("/lua/avante/path.lua$", "") .. "templates")
  -- Copy built-in templates to cache directory (only if not overridden by user templates)
  source_dir:copy({
    destination = cache_prompt_dir,
    recursive = true,
    override = true,
  })

  -- Check for override prompt
  local override_prompt_dir = Config.override_prompt_dir
  if override_prompt_dir then
    -- Handle the case where override_prompt_dir is a function
    if type(override_prompt_dir) == "function" then
      local ok, result = pcall(override_prompt_dir)
      if ok and result then override_prompt_dir = result end
    end

    if override_prompt_dir then
      local user_template_path = Path:new(override_prompt_dir)
      if user_template_path:exists() then
        local user_scanner = Scan.scan_dir(user_template_path:absolute(), { depth = 1, add_dirs = false })
        for _, entry in ipairs(user_scanner) do
          local file = Path:new(entry)
          if file:is_file() then
            local pieces = vim.split(entry, "/")
            local piece = pieces[#pieces]

            if piece == "base.avanterules" then
              local content = file:read()

              if not content:match("{%% block extra_prompt %%}[%s,\\n]*{%% endblock %%}") then
                file:write("{% block extra_prompt %}\n", "a")
                file:write("{% endblock %}\n", "a")
              end

              if not content:match("{%% block custom_prompt %%}[%s,\\n]*{%% endblock %%}") then
                file:write("{% block custom_prompt %}\n", "a")
                file:write("{% endblock %}", "a")
              end
            end
            file:copy({ destination = cache_prompt_dir:joinpath(piece) })
          end
        end
      end
    end
  end

  vim.iter(Prompt.custom_prompts_contents):filter(function(_, v) return v ~= nil end):each(function(k, v)
    local orig_file = cache_prompt_dir:joinpath(Prompt.get_builtin_prompts_filepath(k))
    local orig_content = orig_file:read()
    local f = cache_prompt_dir:joinpath(Prompt.get_custom_prompts_filepath(k))
    f:write(orig_content, "w")
    f:write("{% block custom_prompt -%}\n", "a")
    f:write(v, "a")
    f:write("\n{%- endblock %}", "a")
  end)

  local dir = cache_prompt_dir:absolute()
  return dir
end

---@param mode AvanteLlmMode
---@return string
function Prompt.get_filepath(mode)
  if Prompt.custom_prompts_contents[mode] ~= nil then return Prompt.get_custom_prompts_filepath(mode) end
  return Prompt.get_builtin_prompts_filepath(mode)
end

---@param path string
---@param opts AvanteTemplateOptions
function Prompt.render_file(path, opts) return _templates_lib.render(path, opts) end

---@param mode AvanteLlmMode
---@param opts AvanteTemplateOptions
function Prompt.render_mode(mode, opts)
  local filepath = Prompt.get_filepath(mode)
  return _templates_lib.render(filepath, opts)
end

function Prompt.initialize(cache_directory, project_directory)
  _templates_lib.initialize(cache_directory, project_directory)
end

P.prompts = Prompt

local RepoMap = {}

-- Get a chat history file name given a buffer
---@param project_root string
---@param ext string
---@return string
function RepoMap.filename(project_root, ext)
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(project_root, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  return fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g") .. "." .. ext .. ".repo_map.json"
end

function RepoMap.get(project_root, ext) return Path:new(P.data_path):joinpath(RepoMap.filename(project_root, ext)) end

function RepoMap.save(project_root, ext, data)
  local file = RepoMap.get(project_root, ext)
  file:write(vim.json.encode(data), "w")
end

function RepoMap.load(project_root, ext)
  local file = RepoMap.get(project_root, ext)
  if file:exists() then
    local content = file:read()
    return content ~= nil and vim.json.decode(content) or {}
  end
  return nil
end

P.repo_map = RepoMap

---@return AvanteTemplates|nil
function P._init_templates_lib()
  if _templates_lib ~= nil then return _templates_lib end
  local ok, module = pcall(require, "avante_templates")
  ---@cast module AvanteTemplates
  ---@cast ok boolean
  if not ok then return nil end
  _templates_lib = module

  return _templates_lib
end

function P.setup()
  local history_path = Path:new(Config.history.storage_path)
  if not history_path:exists() then history_path:mkdir({ parents = true }) end
  P.history_path = history_path

  local cache_path = Path:new(Utils.join_paths(vim.fn.stdpath("cache"), "avante"))
  if not cache_path:exists() then cache_path:mkdir({ parents = true }) end
  P.cache_path = cache_path

  local data_path = Path:new(Utils.join_paths(vim.fn.stdpath("data"), "avante"))
  if not data_path:exists() then data_path:mkdir({ parents = true }) end
  P.data_path = data_path

  vim.defer_fn(P._init_templates_lib, 1000)
end

function P.available() return P._init_templates_lib() ~= nil end

function P.clear()
  P.cache_path:rm({ recursive = true })
  P.history_path:rm({ recursive = true })

  if not P.cache_path:exists() then P.cache_path:mkdir({ parents = true }) end
  if not P.history_path:exists() then P.history_path:mkdir({ parents = true }) end
end

return P
