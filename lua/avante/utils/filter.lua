local Path = require("plenary.path")
local Utils = require("avante.utils")

---@class avante.utils.filter
local M = {}

-- Parses .gitignore file and returns patterns
---@param gitignore_path string Path to .gitignore file
---@return string[] ignore_patterns Patterns to ignore
---@return string[] negate_patterns Patterns to not ignore (starting with !)
function M.parse_gitignore(gitignore_path)
  local ignore_patterns = {}
  local negate_patterns = {}
  local file = io.open(gitignore_path, "r")
  if not file then return ignore_patterns, negate_patterns end

  for line in file:lines() do
    if line:match("%S") and not line:match("^#") then
      local trimmed_line = line:match("^%s*(.-)%s*$")
      if trimmed_line:sub(1, 1) == "!" then
        table.insert(negate_patterns, M.pattern_to_lua(trimmed_line:sub(2)))
      else
        table.insert(ignore_patterns, M.pattern_to_lua(trimmed_line))
      end
    end
  end

  file:close()
  -- Add common patterns that should always be ignored
  ignore_patterns = vim.list_extend(ignore_patterns, { "%.git", "%.worktree", "__pycache__", "node_modules" })
  return ignore_patterns, negate_patterns
end

-- Converts gitignore pattern to Lua pattern
---@param pattern string Gitignore pattern
---@return string Lua pattern
function M.pattern_to_lua(pattern)
  local lua_pattern = pattern:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
  lua_pattern = lua_pattern:gsub("%*%*/", ".-/")
  lua_pattern = lua_pattern:gsub("%*", "[^/]*")
  lua_pattern = lua_pattern:gsub("%?", ".")
  if lua_pattern:sub(-1) == "/" then lua_pattern = lua_pattern .. ".*" end
  return lua_pattern
end

-- Checks if a file should be ignored based on gitignore patterns
---@param file string File path
---@param ignore_patterns string[] Patterns to ignore
---@param negate_patterns string[] Patterns to not ignore
---@return boolean true if file should be ignored
function M.is_ignored(file, ignore_patterns, negate_patterns)
  for _, pattern in ipairs(negate_patterns) do
    if file:match(pattern) then return false end
  end
  for _, pattern in ipairs(ignore_patterns) do
    if file:match(pattern) then return true end
  end
  return false
end

-- Gets files managed by git-crypt from .gitattributes
---@param gitattributes_path string Path to .gitattributes file
---@return string[] git_crypt_files Files managed by git-crypt
function M.get_git_crypt_files(gitattributes_path)
  local git_crypt_files = {}
  local file = io.open(gitattributes_path, "r")
  if not file then return git_crypt_files end

  for line in file:lines() do
    if line:match("filter=git%-crypt") then
      local pattern = line:match("^([^%s]+)%s+filter=git%-crypt")
      if pattern then
        table.insert(git_crypt_files, M.pattern_to_lua(pattern))
      end
    end
  end

  file:close()
  return git_crypt_files
end

-- Checks if a file is managed by git-crypt
---@param file string File path
---@param git_crypt_patterns string[] Patterns of files managed by git-crypt
---@return boolean true if file is managed by git-crypt
function M.is_git_crypt_file(file, git_crypt_patterns)
  for _, pattern in ipairs(git_crypt_patterns) do
    if file:match(pattern) then return true end
  end
  return false
end

-- Checks if a file should be filtered from RAG service
---@param file string File path
---@param project_root string Project root path
---@return boolean true if file should be filtered
function M.should_filter_file(file, project_root)
  -- Normalize paths
  file = Path:new(file):make_relative(project_root)
  
  -- Check if we're in a git repository
  local gitignore_path = Path:new(project_root):joinpath(".gitignore")
  local gitattributes_path = Path:new(project_root):joinpath(".gitattributes")
  
  local is_git_repo = gitignore_path:exists() or gitattributes_path:exists()
  if not is_git_repo then
    return false -- If not in a git repo, don't filter anything
  end
  
  -- Parse .gitignore if it exists
  local ignore_patterns, negate_patterns = {}, {}
  if gitignore_path:exists() then
    ignore_patterns, negate_patterns = M.parse_gitignore(tostring(gitignore_path))
  end
  
  -- Get git-crypt files if .gitattributes exists
  local git_crypt_patterns = {}
  if gitattributes_path:exists() then
    git_crypt_patterns = M.get_git_crypt_files(tostring(gitattributes_path))
  end
  
  -- Check if file should be ignored based on .gitignore
  if M.is_ignored(file, ignore_patterns, negate_patterns) then
    Utils.debug(string.format("Filtering file %s (matched gitignore pattern)", file))
    return true
  end
  
  -- Check if file is managed by git-crypt
  if M.is_git_crypt_file(file, git_crypt_patterns) then
    Utils.debug(string.format("Filtering file %s (matched git-crypt pattern)", file))
    return true
  end
  
  return false
end

return M
