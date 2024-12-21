local api, fn = vim.api, vim.fn

local Config = require("avante.config")
local Utils = require("avante.utils")

local DressingConfig = {
  conceal_char = "*",
  filetype = "DressingInput",
  close_window = function() require("dressing.input").close() end,
}
local DressingState = { winid = nil, input_winid = nil, input_bufnr = nil }

---@class AvanteHandlerOptions: table<[string], string>
---@field on_chunk AvanteChunkParser
---@field on_complete AvanteCompleteParser
---
---@class AvanteLLMMessage
---@field role "user" | "assistant"
---@field content string
---
---@class AvantePromptOptions: table<[string], string>
---@field system_prompt string
---@field messages AvanteLLMMessage[]
---@field image_paths? string[]
---
---@class AvanteGeminiMessage
---@field role "user"
---@field parts { text: string }[]
---
---@alias AvanteChatMessage AvanteClaudeMessage | OpenAIMessage | AvanteGeminiMessage
---
---@alias AvanteMessagesParser fun(opts: AvantePromptOptions): AvanteChatMessage[]
---
---@class AvanteCurlOutput: {url: string, proxy: string, insecure: boolean, body: table<string, any> | string, headers: table<string, string>, rawArgs: string[] | nil}
---@alias AvanteCurlArgsParser fun(opts: AvanteProvider | AvanteProviderFunctor, code_opts: AvantePromptOptions): AvanteCurlOutput
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
---@field __inherited_from? string
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
---@field role_map table<"user" | "assistant", string>
---@field parse_messages AvanteMessagesParser
---@field parse_response AvanteResponseParser
---@field parse_curl_args AvanteCurlArgsParser
---@field setup fun(): nil
---@field has fun(): boolean
---@field api_key_name string
---@field tokenizer_id string | "gpt-4o"
---@field use_xml_format boolean
---@field model? string
---@field parse_api_key fun(): string | nil
---@field parse_stream_data? AvanteStreamParser
---@field on_error? fun(result: table<string, any>): nil
---
---@class avante.Providers
---@field openai AvanteProviderFunctor
---@field claude AvanteProviderFunctor
---@field copilot AvanteProviderFunctor
---@field azure AvanteProviderFunctor
---@field gemini AvanteProviderFunctor
---@field cohere AvanteProviderFunctor
local M = {}

---@class EnvironmentHandler
local E = {}

---@private
---@type table<string, string>
E.cache = {}

---@param Opts AvanteSupportedProvider | AvanteProviderFunctor
---@return string | nil
E.parse_envvar = function(Opts)
  local api_key_name = Opts.api_key_name
  if api_key_name == nil then error("Requires api_key_name") end

  local cache_key = type(api_key_name) == "table" and table.concat(api_key_name, "__") or api_key_name

  if E.cache[cache_key] ~= nil then return E.cache[cache_key] end

  local cmd = type(api_key_name) == "table" and api_key_name or api_key_name:match("^cmd:(.*)")

  local value = nil

  if cmd ~= nil then
    -- NOTE: in case api_key_name is cmd, and users still set envvar
    -- We will try to get envvar first
    if Opts._shellenv ~= nil and Opts._shellenv ~= "" then
      value = os.getenv(Opts._shellenv)
      if value ~= nil then
        E.cache[cache_key] = value
        vim.g.avante_login = true
        return value
      end
    end

    if type(cmd) == "string" then cmd = vim.split(cmd, " ", { trimempty = true }) end

    Utils.debug("running command:", cmd)
    local exit_codes = { 0 }
    local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(result)
      Utils.debug("command result:", result)
      local code = result.code
      local stderr = result.stderr or ""
      local stdout = result.stdout and vim.split(result.stdout, "\n") or {}
      if vim.tbl_contains(exit_codes, code) then
        value = stdout[1]
        E.cache[cache_key] = value
        vim.g.avante_login = true
      else
        Utils.error("Failed to get API key: (error code" .. code .. ")\n" .. stderr, { once = true, title = "Avante" })
      end
    end)

    if not ok then
      error("failed to run command: " .. cmd .. "\n" .. job_or_err)
      return
    end
  else
    value = os.getenv(api_key_name)
  end

  if value ~= nil then
    E.cache[cache_key] = value
    vim.g.avante_login = true
  end

  return value
end

--- initialize the environment variable for current neovim session.
--- This will only run once and spawn a UI for users to input the envvar.
---@param opts {refresh: boolean, provider: AvanteProviderFunctor}
---@private
E.setup = function(opts)
  opts.provider.setup()

  local var = opts.provider.api_key_name

  if var == nil or var == "" then
    vim.g.avante_login = true
    return
  end

  -- check if var is a all caps string
  if type(var) == "table" or var:match("^cmd:(.*)") then return end

  local refresh = opts.refresh or false

  ---@param value string
  ---@return nil
  local function on_confirm(value)
    if value then
      vim.fn.setenv(var, value)
      vim.g.avante_login = true
    else
      if not opts.provider.has() then
        Utils.warn("Failed to set " .. var .. ". Avante won't work as expected", { once = true })
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
        DressingState.winid = api.nvim_get_current_win()
        vim.ui.input({ default = "", prompt = "Enter " .. var .. ": " }, on_confirm)
        for _, winid in ipairs(api.nvim_list_wins()) do
          local bufnr = api.nvim_win_get_buf(winid)
          if vim.bo[bufnr].filetype == DressingConfig.filetype then
            DressingState.input_winid = winid
            DressingState.input_bufnr = bufnr
            vim.wo[winid].conceallevel = 2
            vim.wo[winid].concealcursor = "nvi"
            break
          end
        end

        local prompt_length = api.nvim_strwidth(fn.prompt_getprompt(DressingState.input_bufnr))
        api.nvim_buf_call(
          DressingState.input_bufnr,
          function()
            vim.cmd(string.format(
              [[
      syn region SecretValue start=/^/ms=s+%s end=/$/ contains=SecretChar
      syn match SecretChar /./ contained conceal %s
      ]],
              prompt_length,
              "cchar=*"
            ))
          end
        )
      end
    end, 200)
  end

  if refresh then return mount_dressing_buffer() end

  api.nvim_create_autocmd("User", {
    pattern = E.REQUEST_LOGIN_PATTERN,
    callback = mount_dressing_buffer,
  })
end

E.REQUEST_LOGIN_PATTERN = "AvanteRequestLogin"

---@param provider AvanteDefaultBaseProvider
E.require_api_key = function(provider)
  if provider["local"] ~= nil then
    if provider["local"] then
      vim.deprecate('"local" = true', "api_key_name = ''", "0.1.0", "avante.nvim")
    else
      vim.deprecate('"local" = false', "api_key_name", "0.1.0", "avante.nvim")
    end
    return not provider["local"]
  end
  return provider.api_key_name ~= nil and provider.api_key_name ~= ""
end

M.env = E

M = setmetatable(M, {
  ---@param t avante.Providers
  ---@param k Provider
  __index = function(t, k)
    ---@type AvanteProviderFunctor
    local Opts = M.get_config(k)

    ---@diagnostic disable: undefined-field,no-unknown,inject-field
    if Config.vendors[k] ~= nil then
      Opts.parse_response = Opts.parse_response_data
      if Opts.__inherited_from ~= nil then
        local BaseOpts = M.get_config(Opts.__inherited_from)
        local ok, module = pcall(require, "avante.providers." .. Opts.__inherited_from)
        if not ok then error("Failed to load provider: " .. Opts.__inherited_from) end
        t[k] = vim.tbl_deep_extend("keep", Opts, BaseOpts, module)
      else
        t[k] = Opts
      end
    else
      local ok, module = pcall(require, "avante.providers." .. k)
      if not ok then error("Failed to load provider: " .. k) end
      t[k] = vim.tbl_deep_extend("keep", Opts, module)
    end

    t[k].parse_api_key = function() return E.parse_envvar(t[k]) end

    -- default to gpt-4o as tokenizer
    if t[k].tokenizer_id == nil then t[k].tokenizer_id = "gpt-4o" end

    if t[k].use_xml_format == nil then t[k].use_xml_format = false end

    if t[k].has == nil then t[k].has = function() return E.parse_envvar(t[k]) ~= nil end end

    if t[k].setup == nil then
      local base = M.parse_config(t[k])
      t[k].setup = function()
        if E.require_api_key(base) then t[k].parse_api_key() end
        require("avante.tokenizers").setup(t[k].tokenizer_id)
      end
    end

    return t[k]
  end,
})

M.setup = function()
  vim.g.avante_login = false

  ---@type AvanteProviderFunctor
  local provider = M[Config.provider]
  local auto_suggestions_provider = M[Config.auto_suggestions_provider]
  E.setup({ provider = provider })

  if auto_suggestions_provider and auto_suggestions_provider ~= provider then
    E.setup({ provider = auto_suggestions_provider })
  end
end

---@param provider Provider
function M.refresh(provider)
  require("avante.config").override({ provider = provider })

  ---@type AvanteProviderFunctor
  local p = M[Config.provider]
  E.setup({ provider = p, refresh = true })
  Utils.info("Switch to provider: " .. provider, { once = true, title = "Avante" })
end

---@param opts AvanteProvider | AvanteSupportedProvider | AvanteProviderFunctor
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
    vim.iter(s2):filter(function(_, v) return type(v) ~= "function" end):fold({}, function(acc, k, v)
      acc[k] = v
      return acc
    end)
end

---@private
---@param provider Provider
---@return AvanteProviderFunctor
M.get_config = function(provider)
  provider = provider or Config.provider
  local cur = Config.get_provider(provider)
  return type(cur) == "function" and cur() or cur
end

return M
