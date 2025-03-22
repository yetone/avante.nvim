local Path = require("plenary.path")
local Utils = require("avante.utils")
local Helpers = require("avante.llm_tools.helpers")
local Base = require("avante.llm_tools.base")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "grep"

M.description = "Search for a keyword in a directory using grep in current project scope"

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "rel_path",
      description = "Relative path to the project directory",
      type = "string",
    },
    {
      name = "query",
      description = "Query to search for",
      type = "string",
    },
    {
      name = "case_sensitive",
      description = "Whether to search case sensitively",
      type = "boolean",
      default = false,
      optional = true,
    },
    {
      name = "include_pattern",
      description = "Glob pattern to include files",
      type = "string",
      optional = true,
    },
    {
      name = "exclude_pattern",
      description = "Glob pattern to exclude files",
      type = "string",
      optional = true,
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "files",
    description = "List of files that match the keyword",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the directory was not searched successfully",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ rel_path: string, query: string, case_sensitive?: boolean, include_pattern?: string, exclude_pattern?: string }>
function M.func(opts, on_log)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return "", "No such file or directory: " .. abs_path end

  ---check if any search cmd is available
  local search_cmd = vim.fn.exepath("rg")
  if search_cmd == "" then search_cmd = vim.fn.exepath("ag") end
  if search_cmd == "" then search_cmd = vim.fn.exepath("ack") end
  if search_cmd == "" then search_cmd = vim.fn.exepath("grep") end
  if search_cmd == "" then return "", "No search command found" end

  ---execute the search command
  local cmd = ""
  if search_cmd:find("rg") then
    cmd = string.format("%s --files-with-matches --hidden", search_cmd)
    if opts.case_sensitive then
      cmd = string.format("%s --case-sensitive", cmd)
    else
      cmd = string.format("%s --ignore-case", cmd)
    end
    if opts.include_pattern then cmd = string.format("%s --glob '%s'", cmd, opts.include_pattern) end
    if opts.exclude_pattern then cmd = string.format("%s --glob '!%s'", cmd, opts.exclude_pattern) end
    cmd = string.format("%s '%s' %s", cmd, opts.query, abs_path)
  elseif search_cmd:find("ag") then
    cmd = string.format("%s --nocolor --nogroup --hidden", search_cmd)
    if opts.case_sensitive then cmd = string.format("%s --case-sensitive", cmd) end
    if opts.include_pattern then cmd = string.format("%s --ignore '!%s'", cmd, opts.include_pattern) end
    if opts.exclude_pattern then cmd = string.format("%s --ignore '%s'", cmd, opts.exclude_pattern) end
    cmd = string.format("%s '%s' %s", cmd, opts.query, abs_path)
  elseif search_cmd:find("ack") then
    cmd = string.format("%s --nocolor --nogroup --hidden", search_cmd)
    if opts.case_sensitive then cmd = string.format("%s --smart-case", cmd) end
    if opts.exclude_pattern then cmd = string.format("%s --ignore-dir '%s'", cmd, opts.exclude_pattern) end
    cmd = string.format("%s '%s' %s", cmd, opts.query, abs_path)
  elseif search_cmd:find("grep") then
    cmd = string.format("cd %s && git ls-files -co --exclude-standard | xargs %s -rH", abs_path, search_cmd, abs_path)
    if not opts.case_sensitive then cmd = string.format("%s -i", cmd) end
    if opts.include_pattern then cmd = string.format("%s --include '%s'", cmd, opts.include_pattern) end
    if opts.exclude_pattern then cmd = string.format("%s --exclude '%s'", cmd, opts.exclude_pattern) end
    cmd = string.format("%s '%s'", cmd, opts.query)
  end

  Utils.debug("cmd", cmd)
  if on_log then on_log("Running command: " .. cmd) end
  local result = vim.fn.system(cmd)

  local filepaths = vim.split(result, "\n")

  return vim.json.encode(filepaths), nil
end

return M
