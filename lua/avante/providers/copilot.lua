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
local OpenAI = require("avante.providers").openai

local H = {}

---@class AvanteProviderFunctor
local M = {}

local copilot_path = vim.fn.stdpath("data") .. "/avante/github-copilot.json"
local lockfile_path = vim.fn.stdpath("data") .. "/avante/copilot-timer.lock"

-- Lockfile management
local function is_process_running(pid)
  if vim.fn.has("win32") == 1 then
    return vim.fn.system('tasklist /FI "PID eq ' .. pid .. '" 2>NUL | find /I "' .. pid .. '"') ~= ""
  else
    return vim.fn.system("ps -p " .. pid .. " > /dev/null 2>&1; echo $?") == "0\n"
  end
end

local function try_acquire_timer_lock()
  local lockfile = Path:new(lockfile_path)

  local tmp_lockfile = lockfile_path .. ".tmp." .. vim.fn.getpid()

  Path:new(tmp_lockfile):write(tostring(vim.fn.getpid()), "w")

  -- Check existing lock
  if lockfile:exists() then
    local content = lockfile:read()
    local pid = tonumber(content)
    if pid and is_process_running(pid) then
      os.remove(tmp_lockfile)
      return false -- Another instance is already managing
    end
  end

  -- Attempt to take ownership
  local success = os.rename(tmp_lockfile, lockfile_path)
  if not success then
    os.remove(tmp_lockfile)
    return false
  end

  return true
end

local function start_manager_check_timer()
  if M._manager_check_timer then
    M._manager_check_timer:stop()
    M._manager_check_timer:close()
  end

  M._manager_check_timer = vim.uv.new_timer()
  M._manager_check_timer:start(
    30000,
    30000,
    vim.schedule_wrap(function()
      if not M._refresh_timer and try_acquire_timer_lock() then M.setup_timer() end
    end)
  )
end

---@class OAuthToken
---@field user string
---@field oauth_token string
---
---@return string
function H.get_oauth_token()
  local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
  local os_name = Utils.get_os_name()
  ---@type string
  local config_dir

  if xdg_config and vim.fn.isdirectory(xdg_config) > 0 then
    config_dir = xdg_config
  elseif vim.tbl_contains({ "linux", "darwin" }, os_name) then
    config_dir = vim.fn.expand("~/.config")
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
      ---@diagnostic disable-next-line: param-type-mismatch
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
function H.chat_completion_url(base_url) return Utils.url_join(base_url, "/chat/completions") end

function H.refresh_token(async, force)
  if not M.state then error("internal initialization error") end

  async = async == nil and true or async
  force = force or false

  -- Do not refresh token if not forced or not expired
  if
    not force
    and M.state.github_token
    and M.state.github_token.expires_at
    and M.state.github_token.expires_at > math.floor(os.time())
  then
    return false
  end

  local curl_opts = {
    headers = {
      ["Authorization"] = "token " .. M.state.oauth_token,
      ["Accept"] = "application/json",
    },
    timeout = Config.copilot.timeout,
    proxy = Config.copilot.proxy,
    insecure = Config.copilot.allow_insecure,
  }

  local function handle_response(response)
    if response.status == 200 then
      M.state.github_token = vim.json.decode(response.body)
      local file = Path:new(copilot_path)
      file:write(vim.json.encode(M.state.github_token), "w")
      if not vim.g.avante_login then vim.g.avante_login = true end

      -- If triggered synchronously, reset timer
      if not async and M._refresh_timer then M.setup_timer() end

      return true
    else
      error("Failed to get success response: " .. vim.inspect(response))
      return false
    end
  end

  if async then
    curl.get(
      H.chat_auth_url,
      vim.tbl_deep_extend("force", {
        callback = handle_response,
      }, curl_opts)
    )
  else
    local response = curl.get(H.chat_auth_url, curl_opts)
    handle_response(response)
  end
end

---@private
---@class AvanteCopilotState
---@field oauth_token string
---@field github_token CopilotToken?
M.state = nil

M.api_key_name = ""
M.tokenizer_id = "gpt-4o"
M.role_map = {
  user = "user",
  assistant = "assistant",
}

function M:is_disable_stream() return false end

setmetatable(M, { __index = OpenAI })

function M:parse_curl_args(prompt_opts)
  -- refresh token synchronously, only if it has expired
  -- (this should rarely happen, as we refresh the token in the background)
  H.refresh_token(false, false)

  local provider_conf, request_body = P.parse_config(self)
  local disable_tools = provider_conf.disable_tools or false

  local tools = {}
  if not disable_tools and prompt_opts.tools then
    for _, tool in ipairs(prompt_opts.tools) do
      table.insert(tools, OpenAI:transform_tool(tool))
    end
  end

  return {
    url = H.chat_completion_url(provider_conf.endpoint),
    timeout = provider_conf.timeout,
    proxy = provider_conf.proxy,
    insecure = provider_conf.allow_insecure,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. M.state.github_token.token,
      ["Copilot-Integration-Id"] = "vscode-chat",
      ["Editor-Version"] = ("Neovim/%s.%s.%s"):format(vim.version().major, vim.version().minor, vim.version().patch),
    },
    body = vim.tbl_deep_extend("force", {
      model = provider_conf.model,
      messages = self:parse_messages(prompt_opts),
      stream = true,
      tools = tools,
    }, request_body),
  }
end

M._refresh_timer = nil

function M.setup_timer()
  if M._refresh_timer then
    M._refresh_timer:stop()
    M._refresh_timer:close()
  end

  -- Calculate time until token expires
  local now = math.floor(os.time())
  local expires_at = M.state.github_token and M.state.github_token.expires_at or now
  local time_until_expiry = math.max(0, expires_at - now)
  -- Refresh 2 minutes before expiration
  local initial_interval = math.max(0, (time_until_expiry - 120) * 1000)
  -- Regular interval of 28 minutes after the first refresh
  local repeat_interval = 28 * 60 * 1000

  M._refresh_timer = vim.uv.new_timer()
  M._refresh_timer:start(
    initial_interval,
    repeat_interval,
    vim.schedule_wrap(function() H.refresh_token(true, true) end)
  )
end

function M.setup_file_watcher()
  if M._file_watcher then return end

  local copilot_token_file = Path:new(copilot_path)
  M._file_watcher = vim.uv.new_fs_event()

  M._file_watcher:start(
    copilot_path,
    {},
    vim.schedule_wrap(function()
      -- Reload token from file
      if copilot_token_file:exists() then
        local ok, token = pcall(vim.json.decode, copilot_token_file:read())
        if ok then M.state.github_token = token end
      end
    end)
  )
end

function M.setup()
  local copilot_token_file = Path:new(copilot_path)

  if not M.state then M.state = {
    github_token = nil,
    oauth_token = H.get_oauth_token(),
  } end

  -- Load and validate existing token
  if copilot_token_file:exists() then
    local ok, token = pcall(vim.json.decode, copilot_token_file:read())
    if ok and token.expires_at and token.expires_at > math.floor(os.time()) then M.state.github_token = token end
  end

  -- Setup timer management
  local timer_lock_acquired = try_acquire_timer_lock()
  if timer_lock_acquired then
    M.setup_timer()
  else
    vim.schedule(function() H.refresh_token(true, false) end)
  end

  M.setup_file_watcher()

  start_manager_check_timer()

  require("avante.tokenizers").setup(M.tokenizer_id)
  vim.g.avante_login = true
end

function M.cleanup()
  -- Cleanup refresh timer
  if M._refresh_timer then
    M._refresh_timer:stop()
    M._refresh_timer:close()
    M._refresh_timer = nil

    -- Remove lockfile if we were the manager
    local lockfile = Path:new(lockfile_path)
    if lockfile:exists() then
      local content = lockfile:read()
      local pid = tonumber(content)
      if pid and pid == vim.fn.getpid() then lockfile:rm() end
    end
  end

  -- Cleanup manager check timer
  if M._manager_check_timer then
    M._manager_check_timer:stop()
    M._manager_check_timer:close()
    M._manager_check_timer = nil
  end

  -- Cleanup file watcher
  if M._file_watcher then
    ---@diagnostic disable-next-line: param-type-mismatch
    M._file_watcher:stop()
    M._file_watcher = nil
  end
end

-- Register cleanup on Neovim exit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function() M.cleanup() end,
})

return M
