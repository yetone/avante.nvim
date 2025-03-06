local fn = vim.fn
local Utils = require("avante.utils")
local LRUCache = require("avante.utils.lru_cache")
local Path = require("plenary.path")
local Scan = require("plenary.scandir")
local Config = require("avante.config")

---@class avante.Path
---@field history_path Path
---@field cache_path Path
local P = {}

local history_file_cache = LRUCache:new(12)

---@param bufnr integer | nil
---@return string dirname
local function generate_project_dirname_in_storage(bufnr)
  local project_root = Utils.root.get({
    buf = bufnr,
  })
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(project_root, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  local dirname = fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g")
  return tostring(Path:new("projects"):joinpath(dirname))
end

-- History path
local History = {}

-- Get a chat history file name given a buffer
---@param bufnr integer
---@param new boolean
---@return Path
function History.filepath(bufnr, new)
  local dirname = generate_project_dirname_in_storage(bufnr)
  local history_dir = Path:new(Config.history.storage_path):joinpath(dirname):joinpath("history")
  if not history_dir:exists() then history_dir:mkdir({ parents = true }) end
  local pattern = tostring(history_dir:joinpath("*.json"))
  local files = vim.fn.glob(pattern, true, true)
  local filename = #files .. ".json"
  if #files > 0 and not new then filename = (#files - 1) .. ".json" end
  return history_dir:joinpath(filename)
end

-- Returns the Path to the chat history file for the given buffer.
---@param bufnr integer
---@return Path
function History.get(bufnr) return History.filepath(bufnr, false) end

---@param bufnr integer
function History.new(bufnr)
  local filepath = History.filepath(bufnr, true)
  local history = {
    title = "untitled",
    timestamp = tostring(os.date("%Y-%m-%d %H:%M:%S")),
    entries = {},
  }
  filepath:write(vim.json.encode(history), "w")
end

-- Loads the chat history for the given buffer.
---@param bufnr integer
---@return avante.ChatHistory
function History.load(bufnr)
  local history_file = History.get(bufnr)
  local cached_key = tostring(history_file:absolute())
  local cached_value = history_file_cache:get(cached_key)
  if cached_value ~= nil then return cached_value end
  ---@type avante.ChatHistory
  local value = {
    title = "untitled",
    timestamp = tostring(os.date("%Y-%m-%d %H:%M:%S")),
    entries = {},
  }
  if history_file:exists() then
    local content = history_file:read()
    value = content ~= nil and vim.json.decode(content) or value
  end
  history_file_cache:set(cached_key, value)
  return value
end

-- Saves the chat history for the given buffer.
---@param bufnr integer
---@param history avante.ChatHistory
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
---@param mode AvanteLlmMode
---@return string
function Prompt.get_custom_prompts_filepath(mode) return string.format("custom.%s.avanterules", mode) end

function Prompt.get_builtin_prompts_filepath(mode) return string.format("%s.avanterules", mode) end

---@class AvanteTemplates
---@field initialize fun(directory: string): nil
---@field render fun(template: string, context: AvanteTemplateOptions): string
local _templates_lib = nil

Prompt.custom_modes = {
  planning = true,
  editing = true,
  suggesting = true,
  ["cursor-planning"] = true,
  ["cursor-applying"] = true,
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

  local scanner = Scan.scan_dir(directory:absolute(), { depth = 1, add_dirs = true })
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

  Path:new(debug.getinfo(1).source:match("@?(.*/)"):gsub("/lua/avante/path.lua$", "") .. "templates")
    :copy({ destination = cache_prompt_dir, recursive = true })

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

function Prompt.initialize(directory) _templates_lib.initialize(directory) end

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

  local cache_path = Path:new(vim.fn.stdpath("cache") .. "/avante")
  if not cache_path:exists() then cache_path:mkdir({ parents = true }) end
  P.cache_path = cache_path

  local data_path = Path:new(vim.fn.stdpath("data") .. "/avante")
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
