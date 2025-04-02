local Path = require("plenary.path")
local Utils = require("avante.utils")
local Helpers = require("avante.llm_tools.helpers")
local Base = require("avante.llm_tools.base")
local Config = require("avante.config")
local Providers = require("avante.providers")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "bash"

local banned_commands = {
  "alias",
  "curl",
  "curlie",
  "wget",
  "axel",
  "aria2c",
  "nc",
  "telnet",
  "lynx",
  "w3m",
  "links",
  "httpie",
  "xh",
  "http-prompt",
  "chrome",
  "firefox",
  "safari",
}

M.description = [[
Executes a bash command in a persistent shell session within the project.
- Use this tool to run bash commands to interact with the shell environment.
- It maintains a persistent session, so environment variables and shell state are preserved across multiple uses of this tool in the same conversation.
- Specify the 'command' parameter with the bash command to execute.
- WARNING: Do NOT use this tool to read or modify files under ANY circumstances. File system access is strictly prohibited for security reasons.

Example:
To check the current directory, use:
{ "name": "bash", "parameters": { "command": "pwd" } }
]]

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "rel_path",
      description = "Relative path to the project directory, as cwd",
      type = "string",
    },
    {
      name = "command",
      description = "Command to run",
      type = "string",
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "stdout",
    description = "Output of the command",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the command was not run successfully",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ rel_path: string, command: string }>
function M.func(opts, on_log, on_complete, session_ctx)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "Path not found: " .. abs_path end
  if on_log then on_log("command: " .. opts.command) end
  ---change cwd to abs_path
  ---@param output string
  ---@param exit_code integer
  ---@return string | boolean | nil result
  ---@return string | nil error
  local function handle_result(output, exit_code)
    if exit_code ~= 0 then
      if output then return false, "Error: " .. output .. "; Error code: " .. tostring(exit_code) end
      return false, "Error code: " .. tostring(exit_code)
    end
    return output, nil
  end
  if not on_complete then return false, "on_complete not provided" end
  Helpers.confirm(
    "Are you sure you want to run the command: `" .. opts.command .. "` in the directory: " .. abs_path,
    function(ok, reason)
      if not ok then
        on_complete(false, "User declined, reason: " .. (reason and reason or "unknown"))
        return
      end
      Utils.shell_run_async(opts.command, "bash -c", function(output, exit_code)
        local result, err = handle_result(output, exit_code)
        on_complete(result, err)
      end, abs_path)
    end,
    { focus = true },
    session_ctx
  )
end

return M
