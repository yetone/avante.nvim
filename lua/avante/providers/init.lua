local api, fn = vim.api, vim.fn

local Config = require("avante.config")
local Utils = require("avante.utils")

local DressingConfig = {
  conceal_char = "*",
  filetype = "DressingInput",
  close_window = function() require("dressing.input").close() end,
}
local DressingState = { winid = nil, input_winid = nil, input_bufnr = nil }

---@class avante.Providers
---@field openai AvanteProviderFunctor
---@field claude AvanteProviderFunctor
---@field copilot AvanteProviderFunctor
---@field azure AvanteProviderFunctor
---@field gemini AvanteProviderFunctor
---@field cohere AvanteProviderFunctor
---@field bedrock AvanteBedrockProviderFunctor
---@field ollama AvanteProviderFunctor
---@field vertex_claude AvanteProviderFunctor
local M = {}

---@class EnvironmentHandler
local E = {}

---@private
---@type table<string, string>
E.cache = {}

---@param Opts AvanteSupportedProvider | AvanteProviderFunctor | AvanteBedrockProviderFunctor
---@return string | nil
function E.parse_envvar(Opts)
  local value = Utils.environment.parse(Opts.api_key_name, Opts._shellenv)
  if value ~= nil then
    vim.g.avante_login = true
    return value
  end

  return nil
end

--- initialize the environment variable for current neovim session.
--- This will only run once and spawn a UI for users to input the envvar.
---@param opts {refresh: boolean, provider: AvanteProviderFunctor | AvanteBedrockProviderFunctor}
---@private
function E.setup(opts)
  opts.provider.setup()

  local var = opts.provider.api_key_name

  if var == nil or var == "" then
    vim.g.avante_login = true
    return
  end

  if type(var) ~= "table" and vim.env[var] ~= nil then
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
      if not opts.provider.is_env_set() then
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

      if not vim.tbl_contains(exclude_filetypes, vim.bo.filetype) and not opts.provider.is_env_set() then
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
function E.require_api_key(provider)
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
  ---@param k avante.ProviderName
  __index = function(t, k)
    local provider_config = M.get_config(k)

    if Config.vendors[k] ~= nil and k == "ollama" then
      Utils.warn(
        "ollama is now a first-class provider in avante.nvim, please stop using vendors to define ollama, for migration guide please refer to: https://github.com/yetone/avante.nvim/wiki/Custom-providers#ollama"
      )
    end
    ---@diagnostic disable: undefined-field,no-unknown,inject-field
    if Config.vendors[k] ~= nil and k ~= "ollama" then
      if provider_config.parse_response_data ~= nil then
        Utils.error("parse_response_data is not supported for avante.nvim vendors")
      end
      if provider_config.__inherited_from ~= nil then
        local base_provider_config = M.get_config(provider_config.__inherited_from)
        local ok, module = pcall(require, "avante.providers." .. provider_config.__inherited_from)
        if not ok then error("Failed to load provider: " .. provider_config.__inherited_from) end
        t[k] = Utils.deep_extend_with_metatable("keep", provider_config, base_provider_config, module)
      else
        t[k] = provider_config
      end
    else
      local ok, module = pcall(require, "avante.providers." .. k)
      if not ok then error("Failed to load provider: " .. k) end
      t[k] = Utils.deep_extend_with_metatable("keep", provider_config, module)
    end

    t[k].parse_api_key = function() return E.parse_envvar(t[k]) end

    -- default to gpt-4o as tokenizer
    if t[k].tokenizer_id == nil then t[k].tokenizer_id = "gpt-4o" end

    if t[k].is_env_set == nil then t[k].is_env_set = function() return E.parse_envvar(t[k]) ~= nil end end

    if t[k].setup == nil then
      local provider_conf = M.parse_config(t[k])
      t[k].setup = function()
        if E.require_api_key(provider_conf) then t[k].parse_api_key() end
        require("avante.tokenizers").setup(t[k].tokenizer_id)
      end
    end

    return t[k]
  end,
})

function M.setup()
  vim.g.avante_login = false

  ---@type AvanteProviderFunctor | AvanteBedrockProviderFunctor
  local provider = M[Config.provider]

  E.setup({ provider = provider })

  if Config.auto_suggestions_provider then
    local auto_suggestions_provider = M[Config.auto_suggestions_provider]
    if auto_suggestions_provider and auto_suggestions_provider ~= provider then
      E.setup({ provider = auto_suggestions_provider })
    end
  end

  if Config.memory_summary_provider then
    local memory_summary_provider = M[Config.memory_summary_provider]
    if memory_summary_provider and memory_summary_provider ~= provider then
      E.setup({ provider = memory_summary_provider })
    end
  end
end

---@param provider_name avante.ProviderName
function M.refresh(provider_name)
  require("avante.config").override({ provider = provider_name })

  ---@type AvanteProviderFunctor | AvanteBedrockProviderFunctor
  local p = M[Config.provider]
  E.setup({ provider = p, refresh = true })
  Utils.info("Switch to provider: " .. provider_name, { once = true, title = "Avante" })
end

---@param opts AvanteProvider | AvanteSupportedProvider | AvanteProviderFunctor | AvanteBedrockProviderFunctor
---@return AvanteDefaultBaseProvider provider_opts
---@return table<string, any> request_body
function M.parse_config(opts)
  ---@type AvanteDefaultBaseProvider
  local provider_opts = {}
  ---@type table<string, any>
  local request_body = {}

  for key, value in pairs(opts) do
    if vim.tbl_contains(Config.BASE_PROVIDER_KEYS, key) then
      provider_opts[key] = value
    else
      request_body[key] = value
    end
  end

  request_body = vim
    .iter(request_body)
    :filter(function(_, v) return type(v) ~= "function" and type(v) ~= "userdata" end)
    :fold({}, function(acc, k, v)
      acc[k] = v
      return acc
    end)

  return provider_opts, request_body
end

---@private
---@param provider_name avante.ProviderName
function M.get_config(provider_name)
  provider_name = provider_name or Config.provider
  local cur = Config.get_provider_config(provider_name)
  return type(cur) == "function" and cur() or cur
end

function M.get_memory_summary_provider()
  local provider_name = Config.memory_summary_provider
  if provider_name == nil then provider_name = Config.provider end
  return M[provider_name]
end

return M
