local api = vim.api

local Config = require("avante.config")
local Utils = require("avante.utils")
local Dressing = require("avante.ui.dressing")

---@class AvanteHandlerOptions: table<[string], string>
---@field on_chunk AvanteChunkParser
---@field on_complete AvanteCompleteParser
---
---@class AvantePromptOptions: table<[string], string>
---@field base_prompt AvanteBasePrompt
---@field system_prompt AvanteSystemPrompt
---@field question string
---@field image_path? string
---@field code_lang string
---@field code_content string
---@field selected_code_content? string
---
---@class AvanteBaseMessage
---@field role "user" | "system"
---@field content string
---
---@class AvanteClaudeMessage: AvanteBaseMessage
---@field role "user"
---@field content {type: "text", text: string, cache_control?: {type: "ephemeral"}}[]
---
---@class AvanteGeminiMessage
---@field role "user"
---@field parts { text: string }[]
---
---@alias AvanteChatMessage AvanteClaudeMessage | OpenAIMessage | AvanteGeminiMessage
---
---@alias AvanteMessageParser fun(opts: AvantePromptOptions): AvanteChatMessage[]
---
---@class AvanteCurlOutput: {url: string, proxy: string, insecure: boolean, body: table<string, any> | string, headers: table<string, string>}
---@alias AvanteCurlArgsParser fun(opts: AvanteProvider, code_opts: AvantePromptOptions): AvanteCurlOutput
---
---@class ResponseParser
---@field on_chunk fun(chunk: string): any
---@field on_complete fun(err: string|nil): any
---@alias AvanteResponseParser fun(data_stream: string, event_state: string, opts: ResponseParser): nil
---
---@class AvanteDefaultBaseProvider: table<string, any>
---@field endpoint? string
---@field model? string
---@field local? boolean
---@field proxy? string
---@field timeout? integer
---@field allow_insecure? boolean
---@field api_key_name? string
---@field _shellenv? string
---
---@class AvanteSupportedProvider: AvanteDefaultBaseProvider
---@field temperature? number
---@field max_tokens? number
---
---@alias AvanteStreamParser fun(line: string, handler_opts: AvanteHandlerOptions): nil
---@alias AvanteChunkParser fun(chunk: string): any
---@alias AvanteCompleteParser fun(err: string|nil): nil
---@alias AvanteLLMConfigHandler fun(opts: AvanteSupportedProvider): AvanteDefaultBaseProvider, table<string, any>
---
---@class AvanteProvider: AvanteSupportedProvider
---@field parse_response_data AvanteResponseParser
---@field parse_curl_args? AvanteCurlArgsParser
---@field parse_stream_data? AvanteStreamParser
---@field parse_api_key? fun(): string | nil
---
---@class AvanteProviderFunctor
---@field parse_message AvanteMessageParser
---@field parse_response AvanteResponseParser
---@field parse_curl_args AvanteCurlArgsParser
---@field setup fun(): nil
---@field has fun(): boolean
---@field api_key_name string
---@field model? string
---@field parse_api_key fun(): string | nil
---@field parse_stream_data? AvanteStreamParser
---@field on_error? fun(result: table): nil
---
---@class avante.Providers
---@field openai AvanteProviderFunctor
---@field claude AvanteProviderFunctor
---@field azure AvanteProviderFunctor
---@field gemini AvanteProviderFunctor
---@field cohere AvanteProviderFunctor
local M = {}

---@class EnvironmentHandler
local E = {}

---@private
E._once = false

---@private
---@type table<string, string>
E.cache = {}

---@param Opts AvanteSupportedProvider | AvanteProviderFunctor
---@return string | nil
E.parse_envvar = function(Opts)
  local api_key_name = Opts.api_key_name
  if api_key_name == nil then
    error("Requires api_key_name")
  end

  if E.cache[api_key_name] ~= nil then
    return E.cache[api_key_name]
  end

  local cmd = api_key_name:match("^cmd:(.*)")

  local key = nil

  if cmd ~= nil then
    -- NOTE: in case api_key_name is cmd, and users still set envvar
    -- We will try to get envvar first
    if Opts._shellenv ~= nil and Opts._shellenv ~= M.AVANTE_INTERNAL_KEY then
      key = os.getenv(Opts._shellenv)
      if key ~= nil then
        ---@diagnostic disable: no-unknown
        E.cache[Opts._shellenv] = key
        E.cache[api_key_name] = key
        vim.g.avante_login = true
        return key
      end
    end

    local exit_codes = { 0 }
    local ok, job_or_err = pcall(
      vim.system,
      vim.split(cmd, " ", { trimempty = true }),
      { text = true },
      function(result)
        local code = result.code
        local stderr = result.stderr or ""
        local stdout = result.stdout and vim.split(result.stdout, "\n") or {}
        if vim.tbl_contains(exit_codes, code) then
          key = stdout[1]
          E.cache[api_key_name] = key
          vim.g.avante_login = true
        else
          Utils.error(
            "Failed to get API key: (error code" .. code .. ")\n" .. stderr,
            { once = true, title = "Avante" }
          )
        end
      end
    )

    if not ok then
      error("failed to run command: " .. cmd .. "\n" .. job_or_err)
      return
    end
  else
    key = os.getenv(api_key_name)
  end

  if key ~= nil then
    E.cache[api_key_name] = key
    vim.g.avante_login = true
  end

  return key
end

--- initialize the environment variable for current neovim session.
--- This will only run once and spawn a UI for users to input the envvar.
---@param opts {refresh: boolean, provider: AvanteProviderFunctor}
---@private
E.setup = function(opts)
  if opts.provider["local"] then
    vim.g.avante_login = true
    return
  end

  local var = opts.provider.api_key_name

  opts.provider.setup()

  -- check if var is a all caps string
  if var == M.AVANTE_INTERNAL_KEY or var:match("^cmd:(.*)") then
    return
  end

  local refresh = opts.refresh or false

  ---@param value string
  ---@return nil
  local function on_confirm(value)
    if value then
      vim.fn.setenv(var, value)
      vim.g.avante_login = true
    else
      if not opts.provider.has() then
        Utils.warn("Failed to set " .. var .. ". Avante won't work as expected", { once = true, title = "Avante" })
      end
    end
  end

  local function mount_dressing_buffer()
    vim.defer_fn(function()
      -- only mount if given buffer is not of buftype ministarter, dashboard, alpha, qf
      local exclude_filetypes = {
        "NvimTree",
        "Outline",
        "help",
        "dashboard",
        "alpha",
        "qf",
        "ministarter",
        "TelescopePrompt",
        "gitcommit",
        "gitrebase",
        "DressingInput",
        "noice",
      }
      if not vim.tbl_contains(exclude_filetypes, vim.bo.filetype) and not opts.provider.has() then
        Dressing.initialize_input_buffer({
          opts = { prompt = "Enter " .. var .. ": " },
          on_confirm = on_confirm,
        })
      end
    end, 200)
  end

  if refresh then
    mount_dressing_buffer()
    return
  end

  if not E._once then
    E._once = true
    api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter" }, {
      pattern = "*",
      once = true,
      callback = mount_dressing_buffer,
    })
  end
end

---@param provider Provider
E.is_local = function(provider)
  local cur = M.get_config(provider)
  return cur["local"] ~= nil and cur["local"] or false
end

M.env = E

M.AVANTE_INTERNAL_KEY = "__avante_env_internal"

M = setmetatable(M, {
  ---@param t avante.Providers
  ---@param k Provider
  __index = function(t, k)
    ---@type AvanteProviderFunctor
    local Opts = M.get_config(k)

    ---@diagnostic disable: undefined-field,no-unknown,inject-field
    if Config.vendors[k] ~= nil then
      Opts.parse_response = Opts.parse_response_data
      t[k] = Opts
    else
      local ok, module = pcall(require, "avante.providers." .. k)
      if not ok then
        error("Failed to load provider: " .. k)
      end
      Opts._shellenv = module.api_key_name ~= M.AVANTE_INTERNAL_KEY and module.api_key_name or nil
      t[k] = vim.tbl_deep_extend("keep", Opts, module)
    end

    t[k].parse_api_key = function()
      return E.parse_envvar(t[k])
    end

    if t[k].has == nil then
      t[k].has = function()
        return E.parse_envvar(t[k]) ~= nil
      end
    end

    if t[k].setup == nil then
      t[k].setup = function()
        if not E.is_local(k) then
          t[k].parse_api_key()
        end
      end
    end

    return t[k]
  end,
})

M.setup = function()
  vim.g.avante_login = false

  ---@type AvanteProviderFunctor
  local provider = M[Config.provider]
  E.setup({ provider = provider })

  M.commands()
end

---@private
---@param provider Provider
function M.refresh(provider)
  require("avante.config").override({ provider = provider })

  ---@type AvanteProviderFunctor
  local p = M[Config.provider]
  E.setup({ provider = p, refresh = true })
  Utils.info("Switch to provider: " .. provider, { once = true, title = "Avante" })
end

local default_providers = { "openai", "claude", "azure", "gemini" }

---@private
M.commands = function()
  api.nvim_create_user_command("AvanteSwitchProvider", function(args)
    local cmd = vim.trim(args.args or "")
    M.refresh(cmd)
  end, {
    nargs = 1,
    desc = "avante: switch provider",
    complete = function(_, line)
      if line:match("^%s*AvanteSwitchProvider %w") then
        return {}
      end
      local prefix = line:match("^%s*AvanteSwitchProvider (%w*)") or ""
      -- join two tables
      local Keys = vim.list_extend({}, default_providers)
      Keys = vim.list_extend(Keys, vim.tbl_keys(Config.vendors or {}))
      return vim.tbl_filter(function(key)
        return key:find(prefix) == 1
      end, Keys)
    end,
  })
end

---@param opts AvanteProvider | AvanteSupportedProvider
---@return AvanteDefaultBaseProvider, table<string, any>
M.parse_config = function(opts)
  ---@type AvanteDefaultBaseProvider
  local s1 = {}
  ---@type table<string, any>
  local s2 = {}

  for key, value in pairs(opts) do
    if vim.tbl_contains(Config.BASE_PROVIDER_KEYS, key) then
      s1[key] = value
    else
      s2[key] = value
    end
  end

  return s1,
    vim
      .iter(s2)
      :filter(function(_, v)
        return type(v) ~= "function"
      end)
      :fold({}, function(acc, k, v)
        acc[k] = v
        return acc
      end)
end

---@private
---@param provider Provider
---@return AvanteProviderFunctor
M.get_config = function(provider)
  provider = provider or Config.provider
  if provider == "copilot" then
    Utils.error(
      "Sorry! We no longer support the copilot provider! Please use other providers!",
      { once = true, title = "Avante" }
    )
  end
  local cur = Config.get_provider(provider)
  return type(cur) == "function" and cur() or cur
end

return M
