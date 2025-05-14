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

    if type(cmd) == "string" then cmd = vim.split(cmd, " ", { trimempty = true }) end

    Utils.debug("running command:", cmd)
    local exit_codes = { 0 }
    local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(result)
      local code = result.code
      local stderr = result.stderr or ""
      local stdout = result.stdout and vim.split(result.stdout, "\n") or {}
      if vim.tbl_contains(exit_codes, code) then
        value = stdout[1]
        M.cache[cache_key] = value
      else
        Utils.error("failed to get key: (error code" .. code .. ")\n" .. stderr, { once = true, title = "Avante" })
      end
    end)

    if not ok then
      Utils.error("failed to run command: " .. cmd .. "\n" .. job_or_err)
      return
    end
  else
    value = os.getenv(key_name)
  end

  if value ~= nil then M.cache[cache_key] = value end

  return value
end

return M
