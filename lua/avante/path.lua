local fn = vim.fn
local Utils = require("avante.utils")
local Path = require("plenary.path")
local Scan = require("plenary.scandir")
local Config = require("avante.config")
local Names = require("avante.utils.names")

---@class avante.Path
---@field history_path string
---@field cache_path string
---@field data_path string
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

-- Hard cap per JSON file. Beyond this we transparently split into 0.json,
-- 1.json, 2.json, ... inside the instance directory.  Load reassembles them.
local MAX_FILE_SIZE_BYTES = 4 * 1024 * 1024

-- Sentinel filename written inside an instance dir to mark it as deleted by
-- /clear.  We never actually remove the directory so the user can recover
-- by deleting this sentinel manually.
local DELETED_SENTINEL = ".deleted"

-- Per-process memo of project history dirs whose legacy flat <n>.json files
-- have already been migrated into per-instance folders during this session.
local _migrated_dirs = {}

function History.get_history_dir(bufnr)
  local dirname = generate_project_dirname_in_storage(bufnr)
  local history_dir = Path:new(Config.history.storage_path):joinpath(dirname):joinpath("history")
  if not history_dir:exists() then
    history_dir:mkdir({ parents = true })

    local metadata_filepath = history_dir:joinpath("metadata.json")
    local metadata = {
      project_root = Utils.root.get({
        buf = bufnr,
      }),
    }
    metadata_filepath:write(vim.json.encode(metadata), "w")
  end
  return history_dir
end

---Return true if the given instance directory has been marked as deleted by /clear.
---@param instance_dir_path Path
---@return boolean
function History.is_instance_deleted(instance_dir_path)
  return instance_dir_path:joinpath(DELETED_SENTINEL):exists()
end

---Mark an instance as deleted (writes a sentinel file).  Keeps all JSON files
---intact so the user can restore manually.  Does NOT release the instance_name.
---@param bufnr integer
---@param instance_dirname string  e.g. "swift-fox"
function History.mark_instance_deleted(bufnr, instance_dirname)
  local history_dir = History.get_history_dir(bufnr)
  local instance_dir = history_dir:joinpath(instance_dirname)
  if not instance_dir:exists() then return end
  local sentinel = instance_dir:joinpath(DELETED_SENTINEL)
  sentinel:write(tostring(os.time()), "w")
  Utils.debug("History.mark_instance_deleted", instance_dirname)
end

---Remove the deleted sentinel from an instance directory.
---@param bufnr integer
---@param instance_dirname string
function History.restore_instance(bufnr, instance_dirname)
  local history_dir = History.get_history_dir(bufnr)
  local sentinel = history_dir:joinpath(instance_dirname):joinpath(DELETED_SENTINEL)
  if sentinel:exists() then pcall(vim.fs.rm, tostring(sentinel)) end
end

---One-shot migration: move any legacy flat <n>.json (and named *.json) files
---directly inside history_dir into per-instance folders so they show up in
---the new picker.  Runs at most once per directory per process.
---@param history_dir Path
local function migrate_legacy_files(history_dir)
  local key = tostring(history_dir)
  if _migrated_dirs[key] then return end
  _migrated_dirs[key] = true

  local files = vim.fn.glob(tostring(history_dir:joinpath("*.json")), true, true)
  for _, file_path in ipairs(files) do
    if not file_path:match("metadata%.json$") then
      local stem = vim.fn.fnamemodify(file_path, ":t:r")
      -- Prefer the existing instance_name inside the file when available;
      -- otherwise label the legacy file by its numeric stem.
      local target_dirname
      local ok, content = pcall(function() return Path:new(file_path):read() end)
      if ok and content then
        local decode_ok, parsed = pcall(vim.json.decode, content)
        if decode_ok and type(parsed) == "table" and type(parsed.instance_name) == "string" and parsed.instance_name ~= "" then
          target_dirname = parsed.instance_name
        end
      end
      if not target_dirname then target_dirname = "legacy-" .. stem end

      local target_dir = history_dir:joinpath(target_dirname)
      if not target_dir:exists() then target_dir:mkdir({ parents = true }) end
      local dest = target_dir:joinpath("0.json")
      if not dest:exists() then
        -- Fix up filename field inside the JSON before moving.
        if ok and content then
          local decode_ok, parsed = pcall(vim.json.decode, content)
          if decode_ok and type(parsed) == "table" then
            parsed.filename = target_dirname .. "/0.json"
            if not parsed.instance_name or parsed.instance_name == "" then
              parsed.instance_name = target_dirname
            end
            if not parsed.instance_id or parsed.instance_id == "" then
              parsed.instance_id = Utils.uuid()
            end
            local enc_ok, enc = pcall(vim.json.encode, parsed)
            if enc_ok then
              dest:write(enc, "w")
              pcall(vim.fs.rm, file_path)
              Utils.debug("History.migrate_legacy moved", file_path, "→", tostring(dest))
              goto continue
            end
          end
        end
        -- Fallback: byte copy + remove
        pcall(function()
          Path:new(file_path):copy({ destination = dest })
          vim.fs.rm(file_path)
        end)
      end
      ::continue::
    end
  end
end

---@param bufnr integer
---@param opts? { include_deleted?: boolean }
---@return avante.ChatHistory[]
function History.list(bufnr, opts)
  opts = opts or {}
  local history_dir = History.get_history_dir(bufnr)
  local latest_filename = History.get_latest_filename(bufnr, false)
  local res = {}

  -- Migrate legacy flat files into per-instance folders (idempotent, one-shot per session).
  migrate_legacy_files(history_dir)

  Utils.debug("History.list scanning", tostring(history_dir))

  -- Per-instance subdirectories (<instance_name>/*.json).  After migration this
  -- is the ONLY layout we have to deal with.
  local subdirs = Scan.scan_dir(tostring(history_dir), { depth = 1, only_dirs = true, add_dirs = true })
  for _, subdir_path in ipairs(subdirs) do
    local subdir = Path:new(subdir_path)
    if opts.include_deleted or not History.is_instance_deleted(subdir) then
      local instance_dirname = filepath_to_filename(subdir)
      -- Load the merged instance history (handles multi-part 0.json / 1.json / …).
      local history = History.load(bufnr, instance_dirname .. "/0.json")
      if history then
        Utils.debug("History.list found", history.filename, history.instance_name)
        table.insert(res, history)
      end
    end
  end

  -- Sort: latest_filename pinned first, then descending by last-message timestamp
  table.sort(res, function(a, b)
    local H = require("avante.history")
    if a.filename == latest_filename then return true end
    if b.filename == latest_filename then return false end
    local a_messages = H.get_history_messages(a)
    local b_messages = H.get_history_messages(b)
    local timestamp_a = #a_messages > 0 and a_messages[#a_messages].timestamp or a.timestamp
    local timestamp_b = #b_messages > 0 and b_messages[#b_messages].timestamp or b.timestamp
    return timestamp_a > timestamp_b
  end)
  return res
end

---Lightweight per-instance summary used by the :AvanteHistory picker.  Avoids
---loading multi-megabyte JSON files when only mtime/title/first-message are
---needed for the picker.  Sorted by mtime descending.
---@class avante.HistoryInstanceSummary
---@field instance_name string
---@field instance_dirname string
---@field filename string             relative path: "<instance>/0.json"
---@field project_root string
---@field project_dirname string      filesystem-safe encoded form (the storage key)
---@field title string
---@field first_message_text string
---@field last_message_text string
---@field mtime integer               seconds since epoch (latest mtime in instance dir)
---@field timestamp string|nil
---@field is_legacy boolean

---@param history_dir Path
---@param instance_dirname string
---@param project_root string
---@param project_dirname string
---@return avante.HistoryInstanceSummary | nil
local function build_instance_summary(history_dir, instance_dirname, project_root, project_dirname)
  local instance_dir = history_dir:joinpath(instance_dirname)
  if not instance_dir:exists() then return nil end
  if History.is_instance_deleted(instance_dir) then return nil end

  -- Latest mtime across all *.json parts so growing instances bubble to the top.
  local json_files = vim.fn.glob(tostring(instance_dir:joinpath("*.json")), true, true)
  if #json_files == 0 then return nil end
  local latest_mtime = 0
  for _, fp in ipairs(json_files) do
    local stat = vim.uv.fs_stat(fp)
    if stat and stat.mtime and stat.mtime.sec and stat.mtime.sec > latest_mtime then
      latest_mtime = stat.mtime.sec
    end
  end

  -- Load merged history to extract title + first/last message previews.  This
  -- DOES read every part file, which can be expensive for very large
  -- instances; callers that want raw mtime sort should defer this.
  local history = History.from_file(instance_dir:joinpath("0.json"))
  if not history then return nil end
  -- Merge subsequent parts to make first/last message previews accurate.
  table.sort(json_files)
  for i = 2, #json_files do
    local part = History.from_file(Path:new(json_files[i]))
    if part then
      if part.messages then vim.list_extend(history.messages, part.messages) end
      if part.entries then vim.list_extend(history.entries, part.entries) end
    end
  end

  local H = require("avante.history")
  local messages = H.get_history_messages(history)

  local function extract_text(content)
    if type(content) == "string" then return content end
    if type(content) == "table" then
      for _, block in ipairs(content) do
        if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
          return block.text
        end
      end
    end
    return ""
  end
  local function msg_role(m) return m.role or (type(m.message) == "table" and m.message.role) or "" end
  local function msg_content(m) return m.content or (type(m.message) == "table" and m.message.content) or "" end

  local first_text = ""
  for _, m in ipairs(messages) do
    if msg_role(m) == "user" then
      local t = extract_text(msg_content(m))
      if t ~= "" then
        first_text = t
        break
      end
    end
  end
  local last_text = ""
  for i = #messages, 1, -1 do
    local t = extract_text(msg_content(messages[i]))
    if t ~= "" then
      last_text = t
      break
    end
  end

  return {
    instance_name = history.instance_name or instance_dirname,
    instance_dirname = instance_dirname,
    filename = instance_dirname .. "/0.json",
    project_root = project_root,
    project_dirname = project_dirname,
    title = history.title or "untitled",
    first_message_text = first_text,
    last_message_text = last_text,
    mtime = latest_mtime,
    timestamp = history.timestamp,
    is_legacy = instance_dirname:match("^legacy%-") ~= nil,
  }
end

---List instance summaries for the buffer's project, sorted by mtime descending.
---Excludes /clear-deleted instances.
---@param bufnr integer
---@return avante.HistoryInstanceSummary[]
function History.list_instances(bufnr)
  local history_dir = History.get_history_dir(bufnr)
  migrate_legacy_files(history_dir)

  local project_root = Utils.root.get({ buf = bufnr }) or ""
  local project_dirname = generate_project_dirname_in_storage(bufnr):match("[^/]+$") or ""

  local res = {}
  local subdirs = Scan.scan_dir(tostring(history_dir), { depth = 1, only_dirs = true, add_dirs = true })
  for _, subdir_path in ipairs(subdirs) do
    local subdir = Path:new(subdir_path)
    local instance_dirname = filepath_to_filename(subdir)
    local summary = build_instance_summary(history_dir, instance_dirname, project_root, project_dirname)
    if summary then table.insert(res, summary) end
  end
  table.sort(res, function(a, b) return a.mtime > b.mtime end)
  return res
end

---List instance summaries across ALL projects, sorted by mtime descending.
---Excludes the current project (callers should concat them onto the
---current-project list themselves).
---@param exclude_project_root? string
---@return avante.HistoryInstanceSummary[]
function History.list_all_instances(exclude_project_root)
  local projects_dir = Path:new(Config.history.storage_path):joinpath("projects")
  if not projects_dir:exists() then return {} end

  local res = {}
  local project_dirs = Scan.scan_dir(tostring(projects_dir), { depth = 1, only_dirs = true, add_dirs = true })
  for _, project_dir_path in ipairs(project_dirs) do
    local project_dir = Path:new(project_dir_path)
    local history_dir = project_dir:joinpath("history")
    if history_dir:exists() then
      migrate_legacy_files(history_dir)
      local metadata_file = history_dir:joinpath("metadata.json")
      local project_root = ""
      if metadata_file:exists() then
        local ok, content = pcall(function() return metadata_file:read() end)
        if ok and content then
          local dok, metadata = pcall(vim.json.decode, content)
          if dok and metadata and metadata.project_root then project_root = metadata.project_root end
        end
      end
      if project_root ~= "" and project_root ~= exclude_project_root then
        local project_dirname = filepath_to_filename(project_dir)
        local subdirs = Scan.scan_dir(tostring(history_dir), { depth = 1, only_dirs = true, add_dirs = true })
        for _, subdir_path in ipairs(subdirs) do
          local subdir = Path:new(subdir_path)
          local instance_dirname = filepath_to_filename(subdir)
          local summary = build_instance_summary(history_dir, instance_dirname, project_root, project_dirname)
          if summary then table.insert(res, summary) end
        end
      end
    end
  end
  table.sort(res, function(a, b) return a.mtime > b.mtime end)
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
  local metadata = {}
  if metadata_filepath:exists() then
    local metadata_content = metadata_filepath:read()
    metadata = vim.json.decode(metadata_content)
  end
  if metadata.project_root == nil then metadata.project_root = Utils.root.get({
    buf = bufnr,
  }) end
  metadata.latest_filename = filename
  metadata_filepath:write(vim.json.encode(metadata), "w")
end

---@param bufnr integer
function History.new(bufnr)
  local instance_name = Names.generate()
  -- New layout: one subfolder per instance, history stored as 0.json inside it.
  -- e.g.  <history_dir>/swift-fox/0.json
  local filename = instance_name .. "/0.json"
  Utils.debug("History.new creating", filename, instance_name)
  ---@type avante.ChatHistory
  local history = {
    title = "untitled",
    timestamp = Utils.get_timestamp(),
    entries = {},
    messages = {},
    todos = {},
    filename = filename,
    instance_id = Utils.uuid(),
    instance_name = instance_name,
  }
  return history
end

---Attempts to load chat history from a given file
---@param filepath Path
---@return avante.ChatHistory|nil
function History.from_file(filepath)
  if filepath:exists() then
    local content = filepath:read()
    if content ~= nil then
      local decode_ok, history = pcall(vim.json.decode, content)
      if decode_ok and type(history) == "table" then
        if not history.title or type(history.title) ~= "string" then history.title = "untitled" end
        if not history.timestamp or history.timestamp ~= "string" then history.timestamp = Utils.get_timestamp() end
        -- TODO: sanitize individual entries of the lists below as well.
        if not vim.islist(history.entries) then history.entries = {} end
        if not vim.islist(history.messages) then history.messages = {} end
        if not vim.islist(history.todos) then history.todos = {} end
        ---@cast history avante.ChatHistory
        history.filename = filepath_to_filename(filepath)
        -- Backfill instance_id / instance_name for histories created before this feature.
        if not history.instance_id or history.instance_id == "" then history.instance_id = Utils.uuid() end
        if not history.instance_name or history.instance_name == "" then
          history.instance_name = Names.generate()
        else
          -- Register the persisted name so the collision table stays accurate.
          Names.register(history.instance_name)
        end
        return history
      end
    end
  end
end

-- Loads the chat history for the given buffer.  Transparently merges
-- multi-part instance directories (0.json + 1.json + …) produced by the
-- 4 MB split logic in History.save.
---@param bufnr integer
---@param filename string?
---@return avante.ChatHistory
function History.load(bufnr, filename)
  local history_dir = History.get_history_dir(bufnr)
  local instance_dirname = filename and filename:match("^(.-)/[^/]+%.json$") or nil

  if instance_dirname then
    local instance_dir = history_dir:joinpath(instance_dirname)
    if instance_dir:exists() then
      local json_files = vim.fn.glob(tostring(instance_dir:joinpath("*.json")), true, true)
      table.sort(json_files, function(a, b)
        local na = tonumber(vim.fn.fnamemodify(a, ":t:r")) or 0
        local nb = tonumber(vim.fn.fnamemodify(b, ":t:r")) or 0
        return na < nb
      end)
      if #json_files > 0 then
        local base = History.from_file(Path:new(json_files[1]))
        if base then
          -- Canonical filename always points at 0.json regardless of how many
          -- parts there are on disk; subsequent saves go through the same
          -- canonical entry point.
          base.filename = instance_dirname .. "/0.json"
          for i = 2, #json_files do
            local part = History.from_file(Path:new(json_files[i]))
            if part then
              if part.messages then vim.list_extend(base.messages, part.messages) end
              if part.entries then vim.list_extend(base.entries, part.entries) end
            end
          end
          Utils.debug(
            "History.load merged",
            base.filename,
            base.instance_name,
            string.format("(%d parts, %d messages)", #json_files, #base.messages)
          )
          return base
        end
      end
    end
  end

  -- Fall back to legacy single-file path (e.g. metadata.json points at a
  -- flat <n>.json that hasn't been migrated yet).
  local history_filepath = filename and History.get_filepath(bufnr, filename)
    or History.get_latest_filepath(bufnr, false)
  local h = History.from_file(history_filepath)
  if h then
    if filename then h.filename = filename end
    Utils.debug("History.load loaded (legacy single-file)", h.filename, h.instance_name)
    return h
  end
  Utils.debug("History.load creating new (file missing or unreadable)", tostring(history_filepath))
  return History.new(bufnr)
end

--- Recursively strip UTF-8 surrogate code points (CESU-8: 0xED [0xA0-0xBF] [0x80-0xBF])
--- from all string values in `value`, replacing each 3-byte sequence with U+FFFD.
--- This prevents cjson from rejecting the JSON with "surrogates not allowed" when
--- file content or tool results contain characters encoded in modified UTF-8.
---@param value any
---@return any
local function deep_sanitize_utf8(value)
  local t = type(value)
  if t == "string" then
    return (value:gsub("\xED[\xA0-\xBF][\x80-\xBF]", "\xEF\xBF\xBD"))
  elseif t == "table" then
    local out = {}
    for k, v in pairs(value) do
      out[deep_sanitize_utf8(k)] = deep_sanitize_utf8(v)
    end
    if vim.islist(value) then return vim.list_slice(out, 1) end
    return out
  else
    return value
  end
end

-- Saves the chat history for the given buffer.  When the encoded history
-- exceeds MAX_FILE_SIZE_BYTES, transparently splits messages and entries
-- across <instance>/0.json, <instance>/1.json, ... so each file stays under
-- the cap.  The first part holds all metadata (title, todos, memory, etc.)
-- plus as many messages/entries as fit; subsequent parts hold only the
-- overflow `{ messages = [...], entries = [...] }`.
---@param bufnr integer
---@param history avante.ChatHistory
function History.save(bufnr, history)
  if not history or not history.filename then return end

  -- Sanitize surrogate code points before encoding so that history files
  -- remain valid UTF-8 JSON even when tool results or file contents contain
  -- CESU-8 / modified-UTF-8 surrogate bytes.
  local sanitized = deep_sanitize_utf8(history)

  local instance_dirname = type(history.filename) == "string" and history.filename:match("^(.-)/[^/]+%.json$") or nil
  local history_dir = History.get_history_dir(bufnr)

  -- Legacy: filename has no slash → behave exactly like the old single-file save.
  if not instance_dirname then
    local history_filepath = History.get_filepath(bufnr, history.filename)
    local parent = history_filepath:parent()
    if not parent:exists() then parent:mkdir({ parents = true }) end
    local ok, json_content = pcall(vim.json.encode, sanitized)
    if not ok then
      ok, json_content = pcall(vim.json.encode, history)
      if not ok then return end
    end
    Utils.debug("History.save writing (legacy)", history.filename)
    history_filepath:write(json_content, "w")
    History.save_latest_filename(bufnr, history.filename)
    return
  end

  -- New (per-instance) layout: always canonicalize filename to <instance>/0.json
  -- regardless of how many parts there end up being.
  history.filename = instance_dirname .. "/0.json"
  local instance_dir = history_dir:joinpath(instance_dirname)
  if not instance_dir:exists() then instance_dir:mkdir({ parents = true }) end

  -- Fast path: does the whole thing fit in a single file?
  local ok_full, full_json = pcall(vim.json.encode, sanitized)
  if not ok_full then
    -- Last-ditch: encode raw
    ok_full, full_json = pcall(vim.json.encode, history)
    if not ok_full then return end
  end

  if #full_json <= MAX_FILE_SIZE_BYTES then
    instance_dir:joinpath("0.json"):write(full_json, "w")
    -- Clean up any leftover part files from a previously-larger state.
    local existing = vim.fn.glob(tostring(instance_dir:joinpath("*.json")), true, true)
    for _, fp in ipairs(existing) do
      local n = tonumber(vim.fn.fnamemodify(fp, ":t:r"))
      if n and n > 0 then pcall(function() vim.fs.rm(fp) end) end
    end
    Utils.debug("History.save wrote single-part", history.filename, "bytes=" .. #full_json)
    History.save_latest_filename(bufnr, history.filename)
    return
  end

  -- Need to split.  Strategy: greedy bin-packing of messages + entries.
  -- Part 0 carries the full metadata table.  Subsequent parts are just
  -- `{ messages = [...], entries = [...] }`.
  Utils.debug("History.save splitting (size " .. #full_json .. " > cap)", history.filename)

  local base = vim.deepcopy(sanitized)
  base.messages = {}
  base.entries = {}
  local base_size = #vim.json.encode(base)
  -- Use the base size as the floor for part 0.  Reserve a small safety margin.
  local SAFETY = 1024
  local budget_for_part0 = MAX_FILE_SIZE_BYTES - base_size - SAFETY
  if budget_for_part0 < 0 then budget_for_part0 = 0 end
  local budget_for_part_n = MAX_FILE_SIZE_BYTES - SAFETY

  ---@type { messages: any[], entries: any[] }[]
  local parts = { { messages = {}, entries = {} } }
  local sizes = { 0 }
  local function current_budget(i) return i == 1 and budget_for_part0 or budget_for_part_n end

  local function fit(field, item)
    -- Encoded size: item plus a comma overhead.
    local ok_e, enc = pcall(vim.json.encode, item)
    if not ok_e then return end
    local cost = #enc + 2 -- comma + space-ish overhead

    local idx = #parts
    -- If item alone is larger than even a fresh part, drop it onto its own
    -- oversized part (better to exceed than to silently lose data).
    if cost > current_budget(idx) and (#parts[idx].messages + #parts[idx].entries) > 0 then
      table.insert(parts, { messages = {}, entries = {} })
      sizes[#parts] = 0
      idx = #parts
    end
    table.insert(parts[idx][field], item)
    sizes[idx] = sizes[idx] + cost
  end

  for _, msg in ipairs(sanitized.messages or {}) do
    fit("messages", msg)
  end
  for _, entry in ipairs(sanitized.entries or {}) do
    fit("entries", entry)
  end

  -- Materialise part 0 as base ∪ parts[1]
  local part0 = vim.deepcopy(base)
  part0.messages = parts[1].messages
  part0.entries = parts[1].entries
  local p0_ok, p0_json = pcall(vim.json.encode, part0)
  if not p0_ok then return end
  instance_dir:joinpath("0.json"):write(p0_json, "w")

  for i = 2, #parts do
    local part = { messages = parts[i].messages, entries = parts[i].entries }
    local pe_ok, pe_json = pcall(vim.json.encode, part)
    if pe_ok then instance_dir:joinpath((i - 1) .. ".json"):write(pe_json, "w") end
  end

  -- Trim any leftover files from a previously-larger state.
  local existing = vim.fn.glob(tostring(instance_dir:joinpath("*.json")), true, true)
  for _, fp in ipairs(existing) do
    local n = tonumber(vim.fn.fnamemodify(fp, ":t:r"))
    if n and n >= #parts then pcall(function() vim.fs.rm(fp) end) end
  end

  Utils.debug("History.save wrote " .. #parts .. " parts for " .. history.filename)
  History.save_latest_filename(bufnr, history.filename)
end

--- Deletes a specific chat history file.
---@param bufnr integer
---@param filename string
function History.delete(bufnr, filename)
  local history_filepath = History.get_filepath(bufnr, filename)
  if history_filepath:exists() then
    local was_latest = (filename == History.get_latest_filename(bufnr, false))
    vim.fs.rm(tostring(history_filepath))

    -- Clean up the per-instance subdirectory if it's now empty.
    -- Only remove direct subdirectories of history_dir (not history_dir itself).
    local history_dir = History.get_history_dir(bufnr)
    local parent = history_filepath:parent()
    if tostring(parent) ~= tostring(history_dir) then
      local remaining = vim.fn.glob(tostring(parent:joinpath("*")), true, true)
      if #remaining == 0 then
        pcall(vim.fs.rm, tostring(parent), { recursive = true })
      end
    end

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

---@return table[] List of projects with their information
function P.list_projects()
  local projects_dir = Path:new(Config.history.storage_path):joinpath("projects")
  if not projects_dir:exists() then return {} end

  local projects = {}
  local dirs = Scan.scan_dir(tostring(projects_dir), { depth = 1, add_dirs = true, only_dirs = true })

  for _, dir_path in ipairs(dirs) do
    local project_dir = Path:new(dir_path)
    local history_dir = project_dir:joinpath("history")

    local metadata_file = history_dir:joinpath("metadata.json")
    local project_root = ""
    if metadata_file:exists() then
      local content = metadata_file:read()
      if content then
        local metadata = vim.json.decode(content)
        if metadata and metadata.project_root then project_root = metadata.project_root end
      end
    end

    -- Skip if project_root is empty
    if project_root == "" then goto continue end

    -- Count history files
    local history_count = 0
    if history_dir:exists() then
      local history_files = vim.fn.glob(tostring(history_dir:joinpath("*.json")), true, true)
      for _, file in ipairs(history_files) do
        if not file:match("metadata.json") then history_count = history_count + 1 end
      end
    end

    table.insert(projects, {
      name = filepath_to_filename(project_dir),
      root = project_root,
      history_count = history_count,
      directory = tostring(project_dir),
    })

    ::continue::
  end

  -- Sort by history count (most active projects first)
  table.sort(projects, function(a, b) return a.history_count > b.history_count end)

  return projects
end

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
  if Utils.get_os_name() == "windows" then
    directory = Path:new(vim.fs.abspath(tostring(directory)):gsub("^%a:", ""))
  end
  local cache_prompt_dir = Path:new(P.cache_path):joinpath(directory)
  local cache_dir_str = tostring(cache_prompt_dir):gsub("\\", "/")
  if vim.fn.isdirectory(cache_dir_str) == 0 then vim.fn.mkdir(cache_dir_str, "p") end

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
  find_rules(vim.fs.abspath(tostring(directory)))

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
        local user_scanner =
          Scan.scan_dir(vim.fs.abspath(tostring(user_template_path)), { depth = 1, add_dirs = false })
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

  local dir = vim.fs.abspath(tostring(cache_prompt_dir))
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
  local history_path = Config.history.storage_path
  if vim.uv.fs_stat(history_path) == nil then vim.fn.mkdir(history_path, "p") end
  P.history_path = history_path

  local cache_path = vim.fs.joinpath(vim.fn.stdpath("cache"), "avante")
  if vim.uv.fs_stat(cache_path) == nil then vim.fn.mkdir(cache_path, "p") end
  P.cache_path = cache_path

  local data_path = vim.fs.joinpath(vim.fn.stdpath("data"), "avante")
  if vim.uv.fs_stat(data_path) == nil then vim.fn.mkdir(data_path, "p") end
  P.data_path = data_path

  vim.defer_fn(P._init_templates_lib, 1000)
end

function P.available() return P._init_templates_lib() ~= nil end

function P.clear()
  vim.fs.rm(P.cache_path, { recursive = true })
  vim.fs.rm(P.history_path, { recursive = true })

  if vim.uv.fs_stat(P.cache_path) == nil then vim.fn.mkdir(P.cache_path, "p") end
  if vim.uv.fs_stat(P.history_path) == nil then vim.fn.mkdir(P.history_path, "p") end
end

return P
