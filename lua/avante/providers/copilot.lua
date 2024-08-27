---@see https://github.com/B00TK1D/copilot-api/blob/main/api.py

local curl = require("plenary.curl")

local Path = require("plenary.path")
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
M.copilot = nil

local H = {}

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

---@return string | nil
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

  local fp = Path:new(vim
    .iter(file_paths)
    :filter(function(f)
      return vim.fn.filereadable(f) == 1
    end)
    :next())

  ---@type table<string, any>
  local creds = vim.json.decode(fp:read() or {})
  ---@type table<"token", string>
  local value = vim
    .iter(creds)
    :filter(function(k, _)
      return k:find("github.com")
    end)
    :fold({}, function(acc, _, v)
      acc.token = v.oauth_token
      return acc
    end)

  return value.token or nil
end

M.api_key_name = P.AVANTE_INTERNAL_KEY

M.has = function()
  if Utils.has("copilot.lua") or Utils.has("copilot.vim") or H.cached_token() ~= nil then
    return true
  end
  Utils.warn("copilot is not setup correctly. Please use copilot.lua or copilot.vim for authentication.")
  return false
end

M.parse_message = function(opts)
  local user_content = O.get_user_message(opts)
  return {
    { role = "system", content = opts.system_prompt },
    { role = "user", content = user_content },
  }
end

M.parse_response = O.parse_response

M.parse_curl_args = function(provider, code_opts)
  M.refresh_token()

  local base, body_opts = P.parse_config(provider)

  return {
    url = Utils.trim(base.endpoint, { suffix = "/" }) .. "/chat/completions",
    timeout = base.timeout,
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = {
      ["Authorization"] = "Bearer " .. M.copilot.token.token,
      ["Content-Type"] = "application/json",
      ["editor-version"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
    },
    body = vim.tbl_deep_extend("force", {
      model = base.model,
      n = 1,
      top_p = 1,
      stream = true,
      messages = M.parse_message(code_opts),
    }, body_opts),
  }
end

M.on_error = function(result)
  Utils.error("Received error from Copilot API: " .. result.body, { once = true, title = "Avante" })
  Utils.debug(result)
end

M.refresh_token = function()
  if not M.copilot.token or (M.copilot.token.expires_at and M.copilot.token.expires_at <= math.floor(os.time())) then
    curl.get("https://api.github.com/copilot_internal/v2/token", {
      timeout = Config.copilot.timeout,
      headers = {
        ["Authorization"] = "token " .. M.copilot.github_token,
        ["Accept"] = "application/json",
        ["editor-version"] = "Neovim/"
          .. vim.version().major
          .. "."
          .. vim.version().minor
          .. "."
          .. vim.version().patch,
      },
      proxy = Config.copilot.proxy,
      insecure = Config.copilot.allow_insecure,
      on_error = function(err)
        error("Failed to get response: " .. vim.inspect(err))
      end,
      callback = function(output)
        M.copilot.token = vim.json.decode(output.body)
        vim.g.avante_login = true
      end,
    })
  end
end

M.setup = function()
  local github_token = H.cached_token()

  if not github_token then
    error(
      "No GitHub token found, please use `:Copilot auth` to setup with `copilot.lua` or `:Copilot setup` with `copilot.vim`"
    )
  end

  if not M.copilot then
    M.copilot = { token = nil, github_token = github_token }
    M.refresh_token()
  end
end

return M
