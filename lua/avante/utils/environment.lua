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

return M
