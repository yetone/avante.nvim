local Utils = require("avante.utils")

---@class avante.utils.environment
local M = {}

---@private
---@type table<string, string>
M.cache = {}

---Parse environment variable using optional cmd: feature with an override fallback
---@param key_name string
---@param override? string
---@return string | nil
function M.parse(key_name, override)
  if key_name == nil then error("Requires key_name") end

  local cache_key = type(key_name) == "table" and table.concat(key_name, "__") or key_name

  if M.cache[cache_key] ~= nil then return M.cache[cache_key] end

  local cmd = type(key_name) == "table" and key_name or key_name:match("^cmd:(.*)")

  local value = nil

  if cmd ~= nil then
    if override ~= nil and override ~= "" then
      value = os.getenv(override)
      if value ~= nil then
        M.cache[cache_key] = value
        return value
      end
    end

    if type(cmd) == "table" then cmd = table.concat(cmd, " ") end

    Utils.debug("running command:", cmd)
    local exit_codes = { 0 }

    local result = Utils.shell_run(cmd)
    local code = result.code
    local stdout = result.stdout and vim.split(result.stdout, "\n") or {}

    if vim.tbl_contains(exit_codes, code) then
      value = stdout[1]
    else
      Utils.error(
        "failed to get key: (error code" .. code .. ")\n" .. result.stdout,
        { once = true, title = "Avante" }
      )
    end
  else
    value = os.getenv(key_name)
  end

  if value ~= nil then M.cache[cache_key] = value end

  return value
end

---Expand tilde (~) to home directory in path
---@param path string
---@return string
local function expand_tilde(path)
  if path:sub(1, 1) == "~" then
    local home = os.getenv("HOME") or vim.fn.expand("~")
    return home .. path:sub(2)
  end
  return path
end

---Resolve the best matching path from envOverrides based on current working directory
---@param env_overrides table<string, table<string, string>>|nil
---@param cwd string
---@return table<string, string>|nil, string|nil matched_path
function M.resolve_env_overrides(env_overrides, cwd)
  if not env_overrides or vim.tbl_isempty(env_overrides) then return nil, nil end

  -- Normalize cwd to absolute path
  local normalized_cwd = vim.fn.fnamemodify(cwd, ":p")
  -- Remove trailing slash for consistent comparison
  normalized_cwd = normalized_cwd:gsub("/$", "")

  local best_match = nil
  local best_match_length = 0
  local best_match_path = nil

  -- Find the most specific (longest) matching path
  for path_pattern, env_vars in pairs(env_overrides) do
    -- Expand tilde and normalize the pattern path
    local expanded_pattern = expand_tilde(path_pattern)
    local normalized_pattern = vim.fn.fnamemodify(expanded_pattern, ":p"):gsub("/$", "")

    -- Check if cwd starts with this pattern (prefix match)
    if normalized_cwd:find("^" .. vim.pesc(normalized_pattern)) then
      local pattern_length = #normalized_pattern
      if pattern_length > best_match_length then
        best_match = env_vars
        best_match_length = pattern_length
        best_match_path = normalized_pattern
      end
    end
  end

  return best_match, best_match_path
end

---Merge base environment with path-specific overrides
---@param base_env table<string, string>
---@param env_overrides table<string, table<string, string>>|nil
---@param cwd string
---@param show_message? boolean Whether to show notification message (default: true)
---@return table<string, string>
function M.merge_env_with_overrides(base_env, env_overrides, cwd, show_message)
  -- Default show_message to true if not specified
  if show_message == nil then show_message = true end

  -- Start with a copy of base_env
  local merged_env = vim.deepcopy(base_env)

  -- If no overrides, return base env as-is
  if not env_overrides or vim.tbl_isempty(env_overrides) then return merged_env end

  -- Resolve the best matching override for this path
  local override_env, matched_path = M.resolve_env_overrides(env_overrides, cwd)

  -- Merge override values into base env
  if override_env then
    local overridden_keys = {}
    for key, value in pairs(override_env) do
      merged_env[key] = value
      table.insert(overridden_keys, key)
    end

    -- Show notification about applied overrides
    if show_message and #overridden_keys > 0 then
      table.sort(overridden_keys) -- Sort for consistent display
      local message = string.format(
        "ACP Environment Overrides Applied\nPath: %s\nOverridden: %s",
        matched_path,
        table.concat(overridden_keys, ", ")
      )
      Utils.info(message, { title = "Avante ACP" })
    end
  end

  return merged_env
end

return M