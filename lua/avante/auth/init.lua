local pkce = require("avante.auth.pkce")
local http = require("avante.auth.http")
local providers = require("avante.providers")
local M = {}

local client_id = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

function M.authenticate(provider)
  local verifier = pkce.generate_verifier()
  local challenge = pkce.generate_challenge(verifier)
  local state = pkce.generate_verifier()
  local provider_conf = providers.get_config(provider)

  local auth_url = string.format(
    "%s?client_id=%s&response_type=code&redirect_uri=%s&scope=%s&state=%s&code_challenge=%s&code_challenge_method=S256",
    provider_conf.auth_endpoint,
    client_id,
    vim.uri_encode("https://console.anthropic.com/oauth/code/callback"),
    vim.uri_encode("org:create_api_key user:profile user:inference"),
    state,
    challenge
  )

  -- Open browser to begin authentication
  local open_success = pcall(vim.ui.open, auth_url)
  if not open_success then
    vim.fn.setreg("+", auth_url)
    vim.notify("Please open this URL in your browser:\n" .. auth_url, vim.log.levels.WARN)
  end

  vim.ui.input({ prompt = "Enter Auth Key: ", default = "" }, function(input)
    if input then
      local splits = vim.split(input, "#")
      local tokens, e = http.post_json(provider_conf.token_endpoint, {
        grant_type = "authorization_code",
        client_id = client_id,
        code = splits[1],
        state = splits[2],
        redirect_uri = "https://console.anthropic.com/oauth/code/callback",
        code_verifier = verifier,
      }, {
        ["Content-Type"] = "application/json",
      })

      if e then
        vim.notify("Token exchange failed: " .. e, vim.log.levels.ERROR)
        return
      end
      M.store_tokens(tokens)
      vim.notify("✓ Authentication successful!", vim.log.levels.INFO)
    else
      vim.notify("Failed to parse code, authentication failed!", vim.log.levels.ERROR)
    end
  end)
end

function M.store_tokens(tokens)
  local json = {
    access_token = tokens["access_token"],
    refresh_token = tokens["refresh_token"],
    expires_in = os.time() + tokens["expires_in"] * 1000,
  }

  local data_path = vim.fn.stdpath("data") .. "/avante/claude-auth.json"
  local file = io.open(data_path, "w")
  if file then
    file:write(vim.json.encode(json))
    file:close()
    vim.fn.system("chmod 600 " .. data_path)
  end
end

return M
