---Reference implementation:
---https://github.com/zbirenbaum/copilot.lua/blob/master/lua/copilot/auth.lua config file
---https://github.com/zed-industries/zed/blob/ad43bbbf5eda59eba65309735472e0be58b4f7dd/crates/copilot/src/copilot_chat.rs#L272 for authorization
---
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

local curl = require("plenary.curl")

local Config = require("avante.config")
local Path = require("plenary.path")
local Utils = require("avante.utils")
local P = require("avante.providers")
local O = require("avante.providers").openai

local H = {}

---@class OAuthToken
---@field user string
---@field oauth_token string
---
---@return string
H.get_oauth_token = function()
  local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
  local os_name = Utils.get_os_name()
  ---@type string
  local config_dir

  if vim.tbl_contains({ "linux", "darwin" }, os_name) then
    config_dir = (xdg_config and vim.fn.isdirectory(xdg_config) > 0) and xdg_config or vim.fn.expand("~/.config")
  else
    config_dir = vim.fn.expand("~/AppData/Local")
  end

  --- hosts.json (copilot.lua), apps.json (copilot.vim)
  ---@type Path[]
  local paths = vim.iter({ "hosts.json", "apps.json" }):fold({}, function(acc, path)
    local yason = Path:new(config_dir):joinpath("github-copilot", path)
    if yason:exists() then table.insert(acc, yason) end
    return acc
  end)
  if #paths == 0 then error("You must setup copilot with either copilot.lua or copilot.vim", 2) end

  local yason = paths[1]
  return vim
    .iter(
      ---@type table<string, OAuthToken>
      vim.json.decode(yason:read())
    )
    :filter(function(k, _) return k:match("github.com") end)
    ---@param acc {oauth_token: string}
    :fold({}, function(acc, _, v)
      acc.oauth_token = v.oauth_token
      return acc
    end)
    .oauth_token
end

H.chat_auth_url = "https://api.github.com/copilot_internal/v2/token"
H.chat_completion_url = function(base_url) return Utils.trim(base_url, { prefix = "/" }) .. "/chat/completions" end

---@class AvanteProviderFunctor
local M = {}

H.refresh_token = function()
  if not M.state then error("internal initialization error") end

  if
    not M.state.github_token
    or (M.state.github_token.expires_at and M.state.github_token.expires_at < math.floor(os.time()))
  then
    curl.get(H.chat_auth_url, {
      headers = {
        ["Authorization"] = "token " .. M.state.oauth_token,
        ["Accept"] = "application/json",
      },
      timeout = Config.copilot.timeout,
      proxy = Config.copilot.proxy,
      insecure = Config.copilot.allow_insecure,
      on_error = function(err) error("Failed to get response: " .. vim.inspect(err)) end,
      callback = function(output)
        M.state.github_token = vim.json.decode(output.body)
        if not vim.g.avante_login then vim.g.avante_login = true end
      end,
    })
  end
end

---@private
---@class AvanteCopilotState
---@field oauth_token string
---@field github_token CopilotToken?
M.state = nil

M.api_key_name = P.AVANTE_INTERNAL_KEY
M.tokenizer_id = "gpt-4o"

M.parse_message = function(opts)
  return {
    { role = "system", content = opts.system_prompt },
    { role = "user", content = table.concat(opts.user_prompts, "\n") },
  }
end

M.parse_response = O.parse_response

M.parse_curl_args = function(provider, code_opts)
  H.refresh_token()

  local base, body_opts = P.parse_config(provider)

  return {
    url = H.chat_completion_url(base.endpoint),
    timeout = base.timeout,
    proxy = base.proxy,
    insecure = base.allow_insecure,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. M.state.github_token.token,
      ["Copilot-Integration-Id"] = "vscode-chat",
      ["Editor-Version"] = ("Neovim/%s.%s.%s"):format(vim.version().major, vim.version().minor, vim.version().patch),
    },
    body = vim.tbl_deep_extend("force", {
      model = base.model,
      messages = M.parse_message(code_opts),
      stream = true,
    }, body_opts),
  }
end

M.setup = function()
  if not M.state then
    M.state = { github_token = nil, oauth_token = H.get_oauth_token() }
    H.refresh_token()
  end
  require("avante.tokenizers").setup(M.tokenizer_id)
  vim.g.avante_login = true
end

return M
