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
---@field allow_insecure? boolean
---
---@class AvanteSupportedProvider: AvanteDefaultBaseProvider
---@field temperature? number
---@field max_tokens? number
---
---@class AvanteAzureProvider: AvanteDefaultBaseProvider
---@field deployment string
---@field api_version string
---@field temperature number
---@field max_tokens number
---
---@class AvanteCopilotProvider: AvanteSupportedProvider
---@field timeout number
---
---@class AvanteGeminiProvider: AvanteDefaultBaseProvider
---@field model string
---
---@class AvanteProvider: AvanteDefaultBaseProvider
---@field api_key_name string
---@field parse_response_data AvanteResponseParser
---@field parse_curl_args AvanteCurlArgsParser
---@field parse_stream_data? AvanteStreamParser
---
---@alias AvanteStreamParser fun(line: string, handler_opts: AvanteHandlerOptions): nil
---@alias AvanteChunkParser fun(chunk: string): any
---@alias AvanteCompleteParser fun(err: string|nil): nil
---@alias AvanteLLMConfigHandler fun(opts: AvanteSupportedProvider): AvanteDefaultBaseProvider, table<string, any>
---
---@class AvanteProviderFunctor
---@field parse_message AvanteMessageParser
---@field parse_response AvanteResponseParser
---@field parse_curl_args AvanteCurlArgsParser
---@field setup? fun(): nil
---@field has fun(): boolean
---@field api_key_name string
---@field parse_stream_data? AvanteStreamParser
---
---@class avante.Providers
---@field openai AvanteProviderFunctor
---@field copilot AvanteProviderFunctor
---@field claude AvanteProviderFunctor
---@field azure AvanteProviderFunctor
---@field gemini AvanteProviderFunctor
local M = {}

setmetatable(M, {
  ---@param t avante.Providers
  ---@param k Provider
  __index = function(t, k)
    if Config.vendors[k] ~= nil then
      ---@type AvanteProvider
      local v = Config.vendors[k]

      -- Patch from vendors similar to supported providers.
      ---@type AvanteProviderFunctor
      t[k] = setmetatable({}, { __index = v })
      -- Hack for aliasing and makes it sane for us.
      t[k].parse_response = v.parse_response_data
      t[k].has = function()
        return os.getenv(t[k].api_key_name) and true or false
      end

      return t[k]
    end

    ---@type AvanteProviderFunctor
    t[k] = require("avante.providers." .. k)
    return t[k]
  end,
})

---@class EnvironmentHandler
local E = {}

---@private
E._once = false

--- intialize the environment variable for current neovim session.
--- This will only run once and spawn a UI for users to input the envvar.
---@param opts {refresh: boolean, provider: AvanteProviderFunctor}
---@private
E.setup = function(opts)
  local var = opts.provider.api_key_name

  if var == M.AVANTE_INTERNAL_KEY then
    return
  end

  local refresh = opts.refresh or false

  ---@param value string
  ---@return nil
  local function on_confirm(value)
    if value then
      vim.fn.setenv(var, value)
    else
      if not opts.provider.has() then
        Utils.warn("Failed to set " .. var .. ". Avante won't work as expected", { once = true, title = "Avante" })
      end
    end
  end

  if refresh then
    vim.defer_fn(function()
      Dressing.initialize_input_buffer({ opts = { prompt = "Enter " .. var .. ": " }, on_confirm = on_confirm })
    end, 200)
  elseif not E._once then
    E._once = true
    api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter" }, {
      pattern = "*",
      once = true,
      callback = function()
        vim.defer_fn(function()
          -- only mount if given buffer is not of buftype ministarter, dashboard, alpha, qf
          local exclude_buftypes = { "qf", "nofile" }
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
          }
          if
            not vim.tbl_contains(exclude_buftypes, vim.bo.buftype)
            and not vim.tbl_contains(exclude_filetypes, vim.bo.filetype)
            and not opts.provider.has()
          then
            Dressing.initialize_input_buffer({
              opts = { prompt = "Enter " .. var .. ": " },
              on_confirm = on_confirm,
            })
          end
        end, 200)
      end,
    })
  end
end

---@param provider Provider
E.is_local = function(provider)
  local cur = M.get(provider)
  return cur["local"] ~= nil and cur["local"] or false
end

M.env = E

M.AVANTE_INTERNAL_KEY = "__avante_env_internal"

M.setup = function()
  ---@type AvanteProviderFunctor
  local provider = M[Config.provider]
  E.setup({ provider = provider })

  if provider.setup ~= nil then
    provider.setup()
  end

  M.commands()
end

---@private
---@param provider Provider
function M.refresh(provider)
  ---@type AvanteProviderFunctor
  local p = M[Config.provider]
  if not p.has() then
    E.setup({ provider = p, refresh = true })
  else
    Utils.info("Switch to provider: " .. provider, { once = true, title = "Avante" })
  end
  require("avante.config").override({ provider = provider })
end

local default_providers = { "openai", "claude", "azure", "gemini", "copilot" }

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
      local Keys = vim.list_extend(default_providers, vim.tbl_keys(Config.vendors or {}))
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
      :filter(function(k, v)
        return type(v) ~= "function"
      end)
      :fold({}, function(acc, k, v)
        acc[k] = v
        return acc
      end)
end

---@private
---@param provider Provider
M.get = function(provider)
  local cur = Config.get_provider(provider or Config.provider)
  return type(cur) == "function" and cur() or cur
end

return M
