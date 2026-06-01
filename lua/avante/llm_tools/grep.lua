local Path = require("plenary.path")
local Utils = require("avante.utils")
local Helpers = require("avante.llm_tools.helpers")
local Base = require("avante.llm_tools.base")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "grep"

M.description =
  "Search for a pattern in files using ripgrep, returning matching lines with surrounding context. Use this to find code, definitions, and usages across the project."

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      description = "Relative path to the project directory",
      type = "string",
    },
    {
      name = "query",
      description = "Query to search for (supports regex)",
      type = "string",
    },
    {
      name = "context_lines",
      description = "Number of lines to show above and below each match (default 3)",
      type = "integer",
      default = 3,
      optional = true,
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
  usage = {
    path = "Relative path to the project directory",
    query = "Query to search for",
    context_lines = "Number of context lines above and below each match (default 3)",
    case_sensitive = "Whether to search case sensitively",
    include_pattern = "Glob pattern to include files",
    exclude_pattern = "Glob pattern to exclude files",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "results",
    description = "Search results with file paths, line numbers, and matching content with context",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the search failed",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ path: string, query: string, context_lines?: integer, case_sensitive?: boolean, include_pattern?: string, exclude_pattern?: string }>
function M.func(input, opts)
  local on_log = opts.on_log

  local abs_path = Helpers.get_abs_path(input.path)
  if not Helpers.has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return "", "No such file or directory: " .. abs_path end

  local context_lines = input.context_lines or 3

  -- Prefer ripgrep (rg), fall back to other tools
  local search_cmd = vim.fn.exepath("rg")
  if search_cmd == "" then search_cmd = vim.fn.exepath("ag") end
  if search_cmd == "" then search_cmd = vim.fn.exepath("grep") end
  if search_cmd == "" then return "", "No search command found (rg, ag, or grep required)" end

  local cmd = {}
  if search_cmd:find("rg") then
    -- ripgrep: return content with line numbers and context
    cmd = { search_cmd, "-n", "--hidden", "--no-heading" }
    -- Add context lines
    if context_lines > 0 then
      table.insert(cmd, "-C")
      table.insert(cmd, tostring(context_lines))
    end
    if input.case_sensitive then
      table.insert(cmd, "--case-sensitive")
    else
      table.insert(cmd, "--ignore-case")
    end
    if input.include_pattern then
      table.insert(cmd, "--glob")
      table.insert(cmd, input.include_pattern)
    end
    if input.exclude_pattern then
      table.insert(cmd, "--glob")
      table.insert(cmd, "!" .. input.exclude_pattern)
    end
    -- Limit output to avoid overwhelming context
    table.insert(cmd, "--max-count")
    table.insert(cmd, "50")
    table.insert(cmd, input.query)
    table.insert(cmd, abs_path)
  elseif search_cmd:find("ag") then
    cmd = { search_cmd, "--nocolor", "--nogroup", "--hidden" }
    if context_lines > 0 then
      table.insert(cmd, "-C")
      table.insert(cmd, tostring(context_lines))
    end
    if input.case_sensitive then table.insert(cmd, "--case-sensitive") end
    if input.include_pattern then
      table.insert(cmd, "--ignore")
      table.insert(cmd, "!" .. input.include_pattern)
    end
    if input.exclude_pattern then
      table.insert(cmd, "--ignore")
      table.insert(cmd, input.exclude_pattern)
    end
    table.insert(cmd, input.query)
    table.insert(cmd, abs_path)
  elseif search_cmd:find("grep") then
    cmd = { "grep", "-rnH" }
    if context_lines > 0 then
      table.insert(cmd, "-C")
      table.insert(cmd, tostring(context_lines))
    end
    if not input.case_sensitive then table.insert(cmd, "-i") end
    if input.include_pattern then
      table.insert(cmd, "--include")
      table.insert(cmd, input.include_pattern)
    end
    if input.exclude_pattern then
      table.insert(cmd, "--exclude")
      table.insert(cmd, input.exclude_pattern)
    end
    table.insert(cmd, input.query)
    table.insert(cmd, abs_path)
  end

  Utils.debug("cmd", table.concat(cmd, " "))
  if on_log then on_log("Running command: " .. table.concat(cmd, " ")) end
  local result = vim.system(cmd, { text = true }):wait()
  local output = result.stdout or ""

  -- Truncate if too large (avoid blowing up context)
  local max_output_size = 50000
  if #output > max_output_size then
    output = output:sub(1, max_output_size) .. "\n\n...[output truncated, " .. #output .. " total bytes]"
  end

  if output == "" then return vim.json.encode({ matches = {}, total = 0 }), nil end

  return output, nil
end

return M
