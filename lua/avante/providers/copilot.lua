local curl = require("plenary.curl")

local Utils = require("avante.utils")
local Config = require("avante.config")
local P = require("avante.providers")
local O = require("avante.providers").openai

---@class AvanteProviderFunctor
local M = {}

---@class CopilotToken
---@field annotations_enabled boolean
---@field chat_enabled boolean
---@field chat_jetbrains_enabled boolean
---@field code_quote_enabled boolean
---@field codesearch boolean
---@field copilotignore_enabled boolean
---@field endpoints {api: string, ["origin-tracker"]: string, proxy: string, telemetry: string}
---@field expires_at integer
---@field individual boolean
---@field nes_enabled boolean
---@field prompt_8k boolean
---@field public_suggestions string
---@field refresh_in integer
---@field sku string
---@field snippy_load_test_enabled boolean
---@field telemetry string
---@field token string
---@field tracking_id string
---@field vsc_electron_fetcher boolean
---@field xcode boolean
---@field xcode_chat boolean
---
---@private
---@class AvanteCopilot: table<string, any>
---@field token? CopilotToken
---@field github_token? string
---@field sessionid? string
---@field machineid? string
M.copilot = nil

local H = {}

local version_headers = {
  ["editor-version"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
  ["editor-plugin-version"] = "avante.nvim/0.0.0",
  ["user-agent"] = "avante.nvim/0.0.0",
}

---@return string
H.uuid = function()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (
    string.gsub(template, "[xy]", function(c)
      local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format("%x", v)
    end)
  )
end

---@return string
H.machine_id = function()
  local length = 65
  local hex_chars = "0123456789abcdef"
  local hex = ""
  for _ = 1, length do
    hex = hex .. hex_chars:sub(math.random(1, #hex_chars), math.random(1, #hex_chars))
  end
  return hex
end

---@return string | nil
H.find_config_path = function()
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

H.cached_token = function()
  -- loading token from the environment only in GitHub Codespaces
  local token = os.getenv("GITHUB_TOKEN")
  local codespaces = os.getenv("CODESPACES")
  if token and codespaces then
    return token
  end

  -- loading token from the file
  local config_path = H.find_config_path()
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
H.generate_headers = function(token, sessionid, machineid)
  local headers = {
    ["authorization"] = "Bearer " .. token,
    ["x-request-id"] = H.uuid(),
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

M.api_key_name = P.AVANTE_INTERNAL_KEY

M.has = function()
  if Utils.has("copilot.lua") or Utils.has("copilot.vim") or H.find_config_path() then
    return true
  end
  Utils.warn("copilot is not setup correctly. Please use copilot.lua or copilot.vim for authentication.")
  return false
end

M.parse_message = O.parse_message
M.parse_response = O.parse_response

M.parse_curl_args = function(provider, code_opts)
  local github_token = H.cached_token()

  if not github_token then
    error(
      "No GitHub token found, please use `:Copilot auth` to setup with `copilot.lua` or `:Copilot setup` with `copilot.vim`"
    )
  end
  local base, body_opts = P.parse_config(provider)

  local on_done = function()
    return {
      url = Utils.trim(base.endpoint, { suffix = "/" }) .. "/chat/completions",
      proxy = base.proxy,
      insecure = base.allow_insecure,
      headers = H.generate_headers(M.copilot.token.token, M.copilot.sessionid, M.copilot.machineid),
      body = vim.tbl_deep_extend("force", {
        mode = base.model,
        n = 1,
        top_p = 1,
        stream = true,
        messages = M.parse_message(code_opts),
      }, body_opts),
    }
  end

  local result = nil

  if not M.copilot.token or (M.copilot.token.expires_at and M.copilot.token.expires_at <= math.floor(os.time())) then
    local sessionid = H.uuid() .. tostring(math.floor(os.time() * 1000))

    local url = "https://api.github.com/copilot_internal/v2/token"
    local headers = {
      ["Authorization"] = "token " .. github_token,
      ["Accept"] = "application/json",
    }
    for key, value in pairs(version_headers) do
      headers[key] = value
    end

    local response = curl.get(url, {
      timeout = Config.copilot.timeout,
      headers = headers,
      proxy = base.proxy,
      insecure = base.allow_insecure,
      on_error = function(err)
        error("Failed to get response: " .. vim.inspect(err))
      end,
    })

    M.copilot.sessionid = sessionid
    M.copilot.token = vim.json.decode(response.body)
    result = on_done()
  else
    result = on_done()
  end

  return result
end

M.setup = function()
  if not M.copilot then
    M.copilot = {
      sessionid = nil,
      token = nil,
      github_token = H.cached_token(),
      machineid = H.machine_id(),
    }
  end
end

return M
