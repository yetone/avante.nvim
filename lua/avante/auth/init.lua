local pkce = require("avante.auth.pkce")
local http = require("avante.auth.http")
local server = require("avante.auth.server")
local providers = require("avante.providers")
local async = require("plenary.async")
local control = require("plenary.async.control")
local M = {}

local client_id = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

-- M.authenticate = async.void(function(provider)
--   local verifier = pkce.generate_verifier()
--   local challenge = pkce.generate_challenge(verifier)
--   local state = pkce.generate_verifier()
--   local provider_conf = providers.get_config(provider)
--   local port = 8082
--   local sender, receiver = control.channel.mpsc()
--
--   local function handle_callback(code, returned_state)
--     if code and state == returned_state then
--       sender.send(code)
--     else
--       sender.send(nil, "OAuth error: invalid state or missing code")
--     end
--   end
--
--   -- server.start_callback_server(port, handle_callback)
--
--   local auth_url = string.format(
--     "%s?client_id=%s&response_type=code&redirect_uri=%s&scope=%s&state=%s&code_challenge=%s&code_challenge_method=S256",
--     provider_conf.auth_endpoint,
--     client_id,
--     -- vim.uri_encode("http://127.0.0.1:" .. port .. "/callback"),
--     vim.uri_encode("https://console.anthropic.com/oauth/code/callback"),
--     vim.uri_encode("org:create_api_key user:profile user:inference"),
--     state,
--     challenge
--   )
--
--   -- Open browser to begin authentication
--   local open_success = pcall(vim.ui.open, auth_url)
--   if not open_success then vim.notify("Please open this URL in your browser:\n" .. auth_url, vim.log.levels.WARN) end
--   vim.notify("Waiting for authentication... (30s Max)", vim.log.levels.INFO)
--
--   -- Wait for code with timeout (30 seconds)
--   -- local code, _ = receiver.recv(30000)
--
--   -- if err then
--   --   vim.notify(err, vim.log.levels.ERROR)
--   --   return
--   -- end
--
--   -- if not code then
--   --   vim.notify("OAuth timeout", vim.log.levels.ERROR)
--   --   return
--   -- end
--
--   -- Stop the server
--   -- server.stop_callback_server()
--
--   local input = async.wrap(vim.ui.input, 2)
--   async.void(function()
--     local auth_code = input({ prompt = "Enter Claude Auth Code: ", default = "" })
--     if auth_code then
--       local splits = vim.split(auth_code, "#")
--       local tokens, e = http.post_json(provider_conf.token_endpoint, {
--         grant_type = "authorization_code",
--         client_id = client_id,
--         code = splits[1],
--         state = splits[2],
--         -- redirect_uri = "http://127.0.0.1:" .. port .. "/callback",
--         redirect_uri = "https://console.anthropic.com/oauth/code/callback",
--         code_verifier = verifier,
--       }, {
--         ["Content-Type"] = "application/json",
--       })
--
--       if e then
--         vim.notify("Token exchange failed: " .. e, vim.log.levels.ERROR)
--         return
--       end
--       M.store_tokens(tokens)
--       vim.notify("✓ Authentication successful!", vim.log.levels.INFO)
--     else
--       vim.notify("Failed to parse code", vim.log.levels.ERROR)
--       vim.notify("Authentication Failed!", vim.log.levels.ERROR)
--     end
--   end)
--   -- vim.ui.input({ prompt = "Enter Claude Code: ", default = "" }, function(input)
--   --   if input then
--   --     local splits = vim.split(input, "#")
--   --     local tokens, e = http.post_json(provider_conf.token_endpoint, {
--   --       grant_type = "authorization_code",
--   --       client_id = client_id,
--   --       code = splits[1],
--   --       state = splits[2],
--   --       -- redirect_uri = "http://127.0.0.1:" .. port .. "/callback",
--   --       redirect_uri = "https://console.anthropic.com/oauth/code/callback",
--   --       code_verifier = verifier,
--   --     }, {
--   --       ["Content-Type"] = "application/json",
--   --     })
--   --
--   --     if e then
--   --       vim.notify("Token exchange failed: " .. e, vim.log.levels.ERROR)
--   --       return
--   --     end
--   --     M.store_tokens(tokens)
--   --     vim.notify("✓ Authentication successful!", vim.log.levels.INFO)
--   --   else
--   --     vim.notify("Failed to parse code", vim.log.levels.ERROR)
--   --     vim.notify("Authentication Failed!", vim.log.levels.ERROR)
--   --   end
--   -- end)
--   -- -- Exchange code for tokens
--   -- local splits = vim.split(code, "#")
--   -- local tokens, e = http.post_json(provider_conf.token_endpoint, {
--   --   grant_type = "authorization_code",
--   --   client_id = client_id,
--   --   code = splits[1],
--   --   state = splits[2],
--   --   -- redirect_uri = "http://127.0.0.1:" .. port .. "/callback",
--   --   redirect_uri = "https://console.anthropic.com/oauth/code/callback",
--   --   code_verifier = verifier,
--   -- }, {
--   --   ["Content-Type"] = "application/json",
--   -- })
--   --
--   -- if e then
--   --   vim.notify("Token exchange failed: " .. e, vim.log.levels.ERROR)
--   --   return
--   -- end
--   -- M.store_tokens(tokens)
--
--   -- return tokens
-- end)

-- TODO: Explore fixing the local server method of parsing the token
function M.authenticate(provider)
  local verifier = pkce.generate_verifier()
  local challenge = pkce.generate_challenge(verifier)
  local state = pkce.generate_verifier()
  local provider_conf = providers.get_config(provider)
  -- local port = 8082
  -- local sender, receiver = control.channel.mpsc()

  -- local function handle_callback(code, returned_state)
  --   if code and state == returned_state then
  --     sender.send(code)
  --   else
  --     sender.send(nil, "OAuth error: invalid state or missing code")
  --   end
  -- end

  -- server.start_callback_server(port, handle_callback)

  local auth_url = string.format(
    "%s?client_id=%s&response_type=code&redirect_uri=%s&scope=%s&state=%s&code_challenge=%s&code_challenge_method=S256",
    provider_conf.auth_endpoint,
    client_id,
    -- vim.uri_encode("http://127.0.0.1:" .. port .. "/callback"),
    vim.uri_encode("https://console.anthropic.com/oauth/code/callback"),
    vim.uri_encode("org:create_api_key user:profile user:inference"),
    state,
    challenge
  )

  -- Open browser to begin authentication
  local open_success = pcall(vim.ui.open, auth_url)
  if not open_success then vim.notify("Please open this URL in your browser:\n" .. auth_url, vim.log.levels.WARN) end
  vim.notify("Waiting for authentication...", vim.log.levels.INFO)

  -- Wait for code with timeout (30 seconds)
  -- local code, _ = receiver.recv(30000)

  -- if err then
  --   vim.notify(err, vim.log.levels.ERROR)
  --   return
  -- end

  -- if not code then
  --   vim.notify("OAuth timeout", vim.log.levels.ERROR)
  --   return
  -- end

  -- Stop the server
  -- server.stop_callback_server()

  -- TODO: Find a way to get this into a better UI, ideally a multi-step UI where user on first launch can type AvanteLogin and choose the provider,
  -- and if they choose an OAuth provider move to this functions process
  vim.ui.input({ prompt = "Enter Auth Key: ", default = "" }, function(input)
    if input then
      local splits = vim.split(input, "#")
      local tokens, e = http.post_json(provider_conf.token_endpoint, {
        grant_type = "authorization_code",
        client_id = client_id,
        code = splits[1],
        state = splits[2],
        -- redirect_uri = "http://127.0.0.1:" .. port .. "/callback",
        redirect_uri = "https://console.anthropic.com/oauth/code/callback",
        code_verifier = verifier,
      }, {
        ["Content-Type"] = "application/json",
      })

      if e then
        vim.notify("Token exchange failed: " .. e, vim.log.levels.ERROR)
        return
      end
      M.store_tokens(provider, tokens)
      vim.notify("✓ Authentication successful!", vim.log.levels.INFO)
    else
      vim.notify("Failed to parse code", vim.log.levels.ERROR)
      vim.notify("Authentication Failed!", vim.log.levels.ERROR)
    end
  end)
  -- -- Exchange code for tokens
  -- local splits = vim.split(code, "#")
  -- local tokens, e = http.post_json(provider_conf.token_endpoint, {
  --   grant_type = "authorization_code",
  --   client_id = client_id,
  --   code = splits[1],
  --   state = splits[2],
  --   -- redirect_uri = "http://127.0.0.1:" .. port .. "/callback",
  --   redirect_uri = "https://console.anthropic.com/oauth/code/callback",
  --   code_verifier = verifier,
  -- }, {
  --   ["Content-Type"] = "application/json",
  -- })
  --
  -- if e then
  --   vim.notify("Token exchange failed: " .. e, vim.log.levels.ERROR)
  --   return
  -- end
  -- M.store_tokens(tokens)

  -- return tokens
end

-- TODO: This needs to be more general (entry in the auth.json per provider) and needs to call into
-- the provider to parse the response properly i.e. for the Claude Code auth the expires_in needs to be added to Date.now()
function M.store_tokens(provider, tokens)
  local data_path = vim.fn.stdpath("data") .. "/avante/auth.json"
  local file = io.open(data_path, "w")
  if file then
    file:write(vim.json.encode(tokens))
    file:close()
    -- Set restrictive permissions (Unix)
    vim.fn.system("chmod 600 " .. data_path)
  end
end

return M
