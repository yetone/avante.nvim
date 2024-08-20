---This file COPY and MODIFIED based on: https://github.com/CopilotC-Nvim/CopilotChat.nvim/blob/canary/lua/CopilotChat/copilot.lua#L560

---@class avante.utils.copilot
local M = {}

local version_headers = {
  ["editor-version"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
  ["editor-plugin-version"] = "avante.nvim/0.0.0",
  ["user-agent"] = "avante.nvim/0.0.0",
}

---@return string
M.uuid = function()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (
    string.gsub(template, "[xy]", function(c)
      local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format("%x", v)
    end)
  )
end

---@return string
M.machine_id = function()
  local length = 65
  local hex_chars = "0123456789abcdef"
  local hex = ""
  for _ = 1, length do
    hex = hex .. hex_chars:sub(math.random(1, #hex_chars), math.random(1, #hex_chars))
  end
  return hex
end

---@return string | nil
local function find_config_path()
  local config = vim.fn.expand("$XDG_CONFIG_HOME")
  if config and vim.fn.isdirectory(config) > 0 then
    return config
  elseif vim.fn.has("win32") > 0 then
    config = vim.fn.expand("~/AppData/Local")
    if vim.fn.isdirectory(config) > 0 then
      return config
    end
  else
    config = vim.fn.expand("~/.config")
    if vim.fn.isdirectory(config) > 0 then
      return config
    end
  end
end

M.cached_token = function()
  -- loading token from the environment only in GitHub Codespaces
  local token = os.getenv("GITHUB_TOKEN")
  local codespaces = os.getenv("CODESPACES")
  if token and codespaces then
    return token
  end

  -- loading token from the file
  local config_path = find_config_path()
  if not config_path then
    return nil
  end

  -- token can be sometimes in apps.json sometimes in hosts.json
  local file_paths = {
    config_path .. "/github-copilot/hosts.json",
    config_path .. "/github-copilot/apps.json",
  }

  for _, file_path in ipairs(file_paths) do
    if vim.fn.filereadable(file_path) == 1 then
      local userdata = vim.fn.json_decode(vim.fn.readfile(file_path))
      for key, value in pairs(userdata) do
        if string.find(key, "github.com") then
          return value.oauth_token
        end
      end
    end
  end

  return nil
end

---@param token string
---@param sessionid string
---@param machineid string
---@return table<string, string>
M.generate_headers = function(token, sessionid, machineid)
  local headers = {
    ["authorization"] = "Bearer " .. token,
    ["x-request-id"] = M.uuid(),
    ["vscode-sessionid"] = sessionid,
    ["vscode-machineid"] = machineid,
    ["copilot-integration-id"] = "vscode-chat",
    ["openai-organization"] = "github-copilot",
    ["openai-intent"] = "conversation-panel",
    ["content-type"] = "application/json",
  }
  for key, value in pairs(version_headers) do
    headers[key] = value
  end
  return headers
end

M.version_headers = version_headers

return M
