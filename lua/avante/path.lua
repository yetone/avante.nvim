local fn = vim.fn
local Utils = require("avante.utils")
local LRUCache = require("avante.utils.lru_cache")
local Path = require("plenary.path")
local Scan = require("plenary.scandir")
local Config = require("avante.config")

---@class avante.ChatHistoryEntry
---@field timestamp string
---@field provider string
---@field model string
---@field request string
---@field response string
---@field original_response string
---@field selected_file {filepath: string}?
---@field selected_code {filetype: string, content: string}?
---@field reset_memory boolean?
---@field selected_filepaths string[] | nil

---@class avante.Path
---@field history_path Path
---@field cache_path Path
local P = {}

local history_file_cache = LRUCache:new(12)

-- History path
local History = {}

-- Get a chat history file name given a buffer
---@param bufnr integer
---@return string
History.filename = function(bufnr)
  local project_root = Utils.root.get({
    buf = bufnr,
  })
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(project_root, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  return fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g") .. ".json"
end

-- Returns the Path to the chat history file for the given buffer.
---@param bufnr integer
---@return Path
History.get = function(bufnr) return Path:new(Config.history.storage_path):joinpath(History.filename(bufnr)) end

-- Loads the chat history for the given buffer.
---@param bufnr integer
---@return avante.ChatHistoryEntry[]
History.load = function(bufnr)
  local history_file = History.get(bufnr)
  local cached_key = tostring(history_file:absolute())
  local cached_value = history_file_cache:get(cached_key)
  if cached_value ~= nil then return cached_value end
  local value = {}
  if history_file:exists() then
    local content = history_file:read()
    value = content ~= nil and vim.json.decode(content) or {}
  end
  history_file_cache:set(cached_key, value)
  return value
end

-- Saves the chat history for the given buffer.
---@param bufnr integer
---@param history avante.ChatHistoryEntry[]
History.save = vim.schedule_wrap(function(bufnr, history)
  local history_file = History.get(bufnr)
  local cached_key = tostring(history_file:absolute())
  history_file:write(vim.json.encode(history), "w")
  history_file_cache:set(cached_key, history)
end)

P.history = History

-- Prompt path
local Prompt = {}

-- Given a mode, return the file name for the custom prompt.
---@param mode LlmMode
Prompt.get_mode_file = function(mode) return string.format("custom.%s.avanterules", mode) end

---@class AvanteTemplates
---@field initialize fun(directory: string): nil
---@field render fun(template: string, context: TemplateOptions): string
local templates = nil

Prompt.templates = { planning = nil, editing = nil, suggesting = nil }

-- We need to do this beacuse the prompt template engine requires a given directory to load all required files.
-- PERF: Hmm instead of copy to cache, we can also load in globals context, but it requires some work on bindings. (eh maybe?)
---@param project_root string
---@return string the resulted cache_directory to be loaded with avante_templates
Prompt.get = function(project_root)
  if not P.available() then error("Make sure to build avante (missing avante_templates)", 2) end

  -- get root directory of given bufnr
  local directory = Path:new(project_root)
  if Utils.get_os_name() == "windows" then directory = Path:new(directory:absolute():gsub("^%a:", "")[1]) end
  ---@cast directory Path
  ---@type Path
  local cache_prompt_dir = P.cache_path:joinpath(directory)
  if not cache_prompt_dir:exists() then cache_prompt_dir:mkdir({ parents = true }) end

  local scanner = Scan.scan_dir(directory:absolute(), { depth = 1, add_dirs = true })
  for _, entry in ipairs(scanner) do
    local file = Path:new(entry)
    if file:is_file() then
      if entry:find("planning") and Prompt.templates.planning == nil then
        Prompt.templates.planning = file:read()
      elseif entry:find("editing") and Prompt.templates.editing == nil then
        Prompt.templates.editing = file:read()
      elseif entry:find("suggesting") and Prompt.templates.suggesting == nil then
        Prompt.templates.suggesting = file:read()
      end
    end
  end

  Path:new(debug.getinfo(1).source:match("@?(.*/)"):gsub("/lua/avante/path.lua$", "") .. "templates")
    :copy({ destination = cache_prompt_dir, recursive = true })

  vim.iter(Prompt.templates):filter(function(_, v) return v ~= nil end):each(function(k, v)
    local f = cache_prompt_dir:joinpath(Prompt.get_mode_file(k))
    f:write(v, "w")
  end)

  return cache_prompt_dir:absolute()
end

---@param mode LlmMode
Prompt.get_file = function(mode)
  if Prompt.templates[mode] ~= nil then return Prompt.get_mode_file(mode) end
  return string.format("%s.avanterules", mode)
end

---@param path string
---@param opts TemplateOptions
Prompt.render_file = function(path, opts) return templates.render(path, opts) end

---@param mode LlmMode
---@param opts TemplateOptions
Prompt.render_mode = function(mode, opts) return templates.render(Prompt.get_file(mode), opts) end

Prompt.initialize = function(directory) templates.initialize(directory) end

P.prompts = Prompt

local RepoMap = {}

-- Get a chat history file name given a buffer
---@param project_root string
---@param ext string
---@return string
RepoMap.filename = function(project_root, ext)
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(project_root, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  return fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g") .. "." .. ext .. ".repo_map.json"
end

RepoMap.get = function(project_root, ext) return Path:new(P.data_path):joinpath(RepoMap.filename(project_root, ext)) end

RepoMap.save = function(project_root, ext, data)
  local file = RepoMap.get(project_root, ext)
  file:write(vim.json.encode(data), "w")
end

RepoMap.load = function(project_root, ext)
  local file = RepoMap.get(project_root, ext)
  if file:exists() then
    local content = file:read()
    return content ~= nil and vim.json.decode(content) or {}
  end
  return nil
end

P.repo_map = RepoMap

---@return AvanteTemplates|nil
P._init_templates_lib = function()
  if templates ~= nil then return templates end
  local ok, module = pcall(require, "avante_templates")
  ---@cast module AvanteTemplates
  ---@cast ok boolean
  if not ok then return nil end
  templates = module

  return templates
end

P.setup = function()
  local history_path = Path:new(Config.history.storage_path)
  if not history_path:exists() then history_path:mkdir({ parents = true }) end
  P.history_path = history_path

  local cache_path = Path:new(vim.fn.stdpath("cache") .. "/avante")
  if not cache_path:exists() then cache_path:mkdir({ parents = true }) end
  P.cache_path = cache_path

  local data_path = Path:new(vim.fn.stdpath("data") .. "/avante")
  if not data_path:exists() then data_path:mkdir({ parents = true }) end
  P.data_path = data_path

  vim.defer_fn(P._init_templates_lib, 1000)
end

P.available = function() return P._init_templates_lib() ~= nil end

P.clear = function()
  P.cache_path:rm({ recursive = true })
  P.history_path:rm({ recursive = true })

  if not P.cache_path:exists() then P.cache_path:mkdir({ parents = true }) end
  if not P.history_path:exists() then P.history_path:mkdir({ parents = true }) end
end

return P
