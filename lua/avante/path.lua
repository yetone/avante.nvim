local fn, api = vim.fn, vim.api
local Utils = require("avante.utils")
local Path = require("plenary.path")
local Scan = require("plenary.scandir")
local Config = require("avante.config")

---@class avante.Path
---@field history_path Path
---@field cache_path Path
local P = {}

-- Helpers
local H = {}

-- Get a chat history file name given a buffer
---@param bufnr integer
---@return string
H.filename = function(bufnr)
  local code_buf_name = api.nvim_buf_get_name(bufnr)
  -- Replace path separators with double underscores
  local path_with_separators = fn.substitute(code_buf_name, "/", "__", "g")
  -- Replace other non-alphanumeric characters with single underscores
  return fn.substitute(path_with_separators, "[^A-Za-z0-9._]", "_", "g") .. ".json"
end

-- Given a mode, return the file name for the custom prompt.
---@param mode LlmMode
H.get_mode_file = function(mode) return string.format("custom.%s.avanterules", mode) end

-- History path
local M = {}

-- Returns the Path to the chat history file for the given buffer.
---@param bufnr integer
---@return Path
M.get = function(bufnr) return Path:new(Config.history.storage_path):joinpath(H.filename(bufnr)) end

-- Loads the chat history for the given buffer.
---@param bufnr integer
M.load = function(bufnr)
  local history_file = M.get(bufnr)
  if history_file:exists() then
    local content = history_file:read()
    return content ~= nil and vim.json.decode(content) or {}
  end
  return {}
end

-- Saves the chat history for the given buffer.
---@param bufnr integer
---@param history table
M.save = function(bufnr, history)
  local history_file = M.get(bufnr)
  history_file:write(vim.json.encode(history), "w")
end

P.history = M

-- Prompt path
local N = {}

---@class AvanteTemplates
---@field initialize fun(directory: string): nil
---@field render fun(template: string, context: TemplateOptions): string
local templates = nil

N.templates = { planning = nil, editing = nil, suggesting = nil }

-- Creates a directory in the cache path for the given buffer and copies the custom prompts to it.
-- We need to do this beacuse the prompt template engine requires a given directory to load all required files.
-- PERF: Hmm instead of copy to cache, we can also load in globals context, but it requires some work on bindings. (eh maybe?)
---@param bufnr number
---@return string the resulted cache_directory to be loaded with avante_templates
N.get = function(bufnr)
  if not P.available() then error("Make sure to build avante (missing avante_templates)", 2) end

  -- get root directory of given bufnr
  local directory = Path:new(Utils.root.get({ buf = bufnr }))
  if Utils.get_os_name() == "windows" then directory = Path:new(directory:absolute():gsub("^%a:", "")[1]) end
  ---@cast directory Path
  ---@type Path
  local cache_prompt_dir = P.cache_path:joinpath(directory)
  if not cache_prompt_dir:exists() then cache_prompt_dir:mkdir({ parents = true }) end

  local scanner = Scan.scan_dir(directory:absolute(), { depth = 1, add_dirs = true })
  for _, entry in ipairs(scanner) do
    local file = Path:new(entry)
    if entry:find("planning") and N.templates.planning == nil then
      N.templates.planning = file:read()
    elseif entry:find("editing") and N.templates.editing == nil then
      N.templates.editing = file:read()
    elseif entry:find("suggesting") and N.templates.suggesting == nil then
      N.templates.suggesting = file:read()
    end
  end

  Path:new(debug.getinfo(1).source:match("@?(.*/)"):gsub("/lua/avante/path.lua$", "") .. "templates")
    :copy({ destination = cache_prompt_dir, recursive = true })

  vim.iter(N.templates):filter(function(_, v) return v ~= nil end):each(function(k, v)
    local f = cache_prompt_dir:joinpath(H.get_mode_file(k))
    f:write(v, "w")
  end)

  return cache_prompt_dir:absolute()
end

---@param mode LlmMode
N.get_file = function(mode)
  if N.templates[mode] ~= nil then return H.get_mode_file(mode) end
  return string.format("%s.avanterules", mode)
end

---@param path string
---@param opts TemplateOptions
N.render_file = function(path, opts) return templates.render(path, opts) end

---@param mode LlmMode
---@param opts TemplateOptions
N.render_mode = function(mode, opts) return templates.render(N.get_file(mode), opts) end

N.initialize = function(directory) templates.initialize(directory) end

P.prompts = N

P.setup = function()
  local history_path = Path:new(Config.history.storage_path)
  if not history_path:exists() then history_path:mkdir({ parents = true }) end
  P.history_path = history_path

  local cache_path = Path:new(vim.fn.stdpath("cache") .. "/avante")
  if not cache_path:exists() then cache_path:mkdir({ parents = true }) end
  P.cache_path = cache_path

  vim.defer_fn(function()
    local ok, module = pcall(require, "avante_templates")
    ---@cast module AvanteTemplates
    ---@cast ok boolean
    if not ok then return end
    if templates == nil then templates = module end
  end, 1000)
end

P.available = function() return templates ~= nil end

P.clear = function()
  P.cache_path:rm({ recursive = true })
  P.history_path:rm({ recursive = true })
end

return P
