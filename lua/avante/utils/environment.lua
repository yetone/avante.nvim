local Utils = require("avante.utils")

---@class avante.utils.environment
local M = {}

---@private
---@type table<string, string>
M.cache = {}

---Parse environment variable using optional cmd: feature with an override fallback
---@param key_name string
---@param override? string
---@param force_cache_invalidate? boolean
---@return string | nil
function M.parse(key_name, override, force_cache_invalidate)
  if key_name == nil then error("Requires key_name") end

  local cache_key = type(key_name) == "table" and table.concat(key_name, "__") or key_name

  if not force_cache_invalidate and M.cache[cache_key] ~= nil then return M.cache[cache_key] end

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

    ---@param result {code: number, stderr: string, stdout: string} | nil
    local function handle_command_result(result)
      local code = result.code or -1
      local stderr = result.stderr or ""
      local stdout = result.stdout and vim.split(result.stdout, "\n") or {}

      if vim.tbl_contains(exit_codes, code) and stdout[1] then
        value = stdout[1]
        M.cache[cache_key] = value
      else
        local error_msg = "failed to get key: (error code " .. code .. ")"
        if stderr ~= "" then
          error_msg = error_msg .. "\n" .. stderr
        end
        Utils.error(error_msg, { once = true, title = "Avante" })
      end
    end

    -- Create the system job
    local job = vim.system(cmd, { text = true }, handle_command_result)

    if force_cache_invalidate then
      -- Run synchronously when force invalidating cache because the credentials are likely already expired
      -- and trying to use the old ones will result in failure
      job:wait()
    end
  else
    value = os.getenv(key_name)
  end

  if value ~= nil then M.cache[cache_key] = value end

  return value
end

return M
