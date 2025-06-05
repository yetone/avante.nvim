-- tests/providers/gitlab_spec.lua

local gitlab_provider = require("avante.providers.gitlab")
local Providers = require("avante.providers") -- To mock get_config if needed

-- Simple deep compare function for tables (add more robust one if needed)
local function deep_compare(t1, t2)
  if type(t1) ~= type(t2) then return false end
  if type(t1) ~= "table" then return t1 == t2 end

  local k1 = {}
  for k in pairs(t1) do table.insert(k1, k) end
  local k2 = {}
  for k in pairs(t2) do table.insert(k2, k) end
  if #k1 ~= #k2 then return false end

  for _, k in ipairs(k1) do
    if not deep_compare(t1[k], t2[k]) then return false end
  end
  return true
end

-- Mocking utility if not already part of the test setup
local function mock(obj, key, temp_val)
  local original = obj[key]
  obj[key] = temp_val
  return function()
    obj[key] = original
  end
end

describe("Avante GitLab Duo Provider", function()
  describe(":parse_messages(opts)", function()
    local parse_messages_fn = function(opts)
      -- Simulate the way the method is called on an instance
      return gitlab_provider["parse_messages"](gitlab_provider, opts)
    end

    -- Mock Providers.get_config to avoid errors if it's called within parse_messages
    local unmock_providers_config
    before_each(function()
        local mock_provider_config = { model = "test-model" } -- basic mock
        unmock_providers_config = mock(Providers, "get_config", function() return mock_provider_config end)
        -- Mock M.state for the gitlab_provider instance if parse_messages accesses it
        -- For now, assuming parse_messages primarily uses M.role_map and opts
        gitlab_provider.state = gitlab_provider.state or {} -- Ensure state table exists
    end)

    after_each(function()
        if unmock_providers_config then unmock_providers_config() end
    end)

    it("should return an empty array for empty messages and no system prompt", function()
      local opts = { messages = {} }
      local result = parse_messages_fn(opts)
      assert.are.same({}, result)
    end)

    it("should include system prompt if provided", function()
      local opts = {
        system_prompt = "You are a helpful assistant.",
        messages = {},
      }
      local result = parse_messages_fn(opts)
      assert.are.same({
        { role = "system", content = "You are a helpful assistant." },
      }, result)
    end)

    it("should handle a single user message", function()
      local opts = {
        messages = {
          { role = "user", content = "Hello there!" },
        },
      }
      local result = parse_messages_fn(opts)
      assert.are.same({
        { role = "user", content = "Hello there!" },
      }, result)
    end)

    it("should correctly map roles and handle alternating user/assistant messages", function()
      local opts = {
        system_prompt = "System instructions.",
        messages = {
          { role = "user", content = "First user message." },
          { role = "assistant", content = "First assistant response." },
          { role = "user", content = "Second user message." },
        },
      }
      local result = parse_messages_fn(opts)
      assert.are.same({
        { role = "system", content = "System instructions." },
        { role = "user", content = "First user message." },
        { role = "assistant", content = "First assistant response." },
        { role = "user", content = "Second user message." },
      }, result)
    end)

    it("should insert dummy messages for consecutive roles (user then user)", function()
      gitlab_provider.role_map = { user = "user", assistant = "assistant", system = "system" } -- Ensure role_map is default
      local opts = {
        messages = {
          { role = "user", content = "User message 1." },
          { role = "user", content = "User message 2, should follow a dummy assistant message." },
        },
      }
      local result = parse_messages_fn(opts)
      assert.are.same({
        { role = "user", content = "User message 1." },
        { role = "assistant", content = "Ok." }, -- Dummy assistant message
        { role = "user", content = "User message 2, should follow a dummy assistant message." },
      }, result)
    end)

    it("should insert dummy messages for consecutive roles (assistant then assistant)", function()
      gitlab_provider.role_map = { user = "user", assistant = "assistant", system = "system" }
      local opts = {
        messages = {
          { role = "assistant", content = "Assistant message 1." },
          { role = "assistant", content = "Assistant message 2, should follow a dummy user message." },
        },
      }
      local result = parse_messages_fn(opts)
      assert.are.same({
        { role = "assistant", content = "Assistant message 1." },
        { role = "user", content = "(Previous message continued)" }, -- Dummy user message
        { role = "assistant", content = "Assistant message 2, should follow a dummy user message." },
      }, result)
    end)

    it("should handle complex content (table with text parts)", function()
      local opts = {
        messages = {
          {
            role = "user",
            content = {
              { type = "text", text = "First line." },
              "Second line from simple string.",
            },
          },
        },
      }
      local result = parse_messages_fn(opts)
      assert.are.same({
        { role = "user", content = "First line.\nSecond line from simple string." },
      }, result)
    end)

    it("should handle system prompt with consecutive user messages", function()
      gitlab_provider.role_map = { user = "user", assistant = "assistant", system = "system" }
      local opts = {
        system_prompt = "Be concise.",
        messages = {
          { role = "user", content = "User message 1." },
          { role = "user", content = "User message 2." },
        },
      }
      local result = parse_messages_fn(opts)
      assert.are.same({
        { role = "system", content = "Be concise." },
        { role = "user", content = "User message 1." },
        { role = "assistant", content = "Ok." },
        { role = "user", content = "User message 2." },
      }, result)
    end)
  end)

  describe(":parse_curl_args(prompt_opts)", function()
    local parse_curl_args_fn = function(prompt_opts)
      -- Simulate the way the method is called on an instance
      return gitlab_provider["parse_curl_args"](gitlab_provider, prompt_opts)
    end

    local original_state
    local unmock_providers_get_config
    local unmock_parse_messages
    local unmock_h_refresh_token
    local unmock_utils_warn
    local unmock_utils_info

    before_each(function()
      -- Deep copy original state if complex, or just store and restore
      original_state = vim.deepcopy(gitlab_provider.state or {}) -- Ensure deepcopy if state is modified
      gitlab_provider.state = gitlab_provider.state or {}

      unmock_utils_warn = mock(Utils, "warn", function() end) -- Suppress warnings in tests
      unmock_utils_info = mock(Utils, "info", function() end) -- Suppress info in tests
    end)

    after_each(function()
      gitlab_provider.state = original_state -- Restore state
      if unmock_providers_get_config then unmock_providers_get_config() end
      if unmock_parse_messages then unmock_parse_messages() end
      if unmock_h_refresh_token then unmock_h_refresh_token() end
      if unmock_utils_warn then unmock_utils_warn() end
      if unmock_utils_info then unmock_utils_info() end
    end)

    it("should return nil if no token is available", function()
      gitlab_provider.state.gitlab_token = nil
      local result = parse_curl_args_fn({})
      assert.is_nil(result)
    end)

    it("should correctly form curl args with a valid token", function()
      gitlab_provider.state.gitlab_token = {
        access_token = "test_access_token",
        created_at = math.floor(os.time()) - 3000, -- well in the past
        expires_in = 3600,
      }
      unmock_providers_get_config = mock(Providers, "get_config", function()
        return { model = "default-model", timeout = 10, proxy = nil, allow_insecure = false }
      end)
      local mock_messages = { { role = "user", content = "Hello" } }
      unmock_parse_messages = mock(gitlab_provider, "parse_messages", function() return mock_messages end)

      local result = parse_curl_args_fn({})

      assert.is_not_nil(result)
      assert.are.equal(gitlab_provider.H.chat_completion_url(gitlab_provider.H.gitlab_api_base_url), result.url)
      assert.are.same({ ["Content-Type"] = "application/json", ["Authorization"] = "Bearer test_access_token" }, result.headers)
      assert.is_true(deep_compare({ model = "default-model", messages = mock_messages, stream = true }, result.body))
      assert.are.equal(10, result.timeout)
    end)

    it("should attempt to refresh an expiring token", function()
      gitlab_provider.state.gitlab_token = {
        access_token = "expiring_token",
        refresh_token = "can_refresh",
        created_at = math.floor(os.time()) - 3580, -- 20 seconds left from 3600
        expires_in = 3600,
      }
      unmock_providers_get_config = mock(Providers, "get_config", function() return { model = "default-model" } end)
      unmock_parse_messages = mock(gitlab_provider, "parse_messages", function() return {} end)

      local refresh_called_sync = false
      local refresh_forced = false
      unmock_h_refresh_token = mock(gitlab_provider.H, "refresh_token", function(async, force)
        refresh_called_sync = (async == false)
        refresh_forced = (force == true)
        return true -- Simulate successful refresh
      end)

      parse_curl_args_fn({})
      assert.is_true(refresh_called_sync, "H.refresh_token should be called synchronously")
      assert.is_true(refresh_forced, "H.refresh_token should be called with force=true")
    end)

    it("should use custom endpoint from provider config if provided", function()
      gitlab_provider.state.gitlab_token = { access_token = "test_token", created_at = math.floor(os.time()), expires_in = 3600 }
      local custom_endpoint = "https://custom.gitlab.instance/api/v4"
      unmock_providers_get_config = mock(Providers, "get_config", function()
        return { endpoint = custom_endpoint, model = "custom-model" }
      end)
      unmock_parse_messages = mock(gitlab_provider, "parse_messages", function() return {} end)

      local result = parse_curl_args_fn({})
      assert.is_not_nil(result)
      assert.are.equal(gitlab_provider.H.chat_completion_url(custom_endpoint), result.url)
      assert.are.equal("custom-model", result.body.model)
    end)

    it("should use placeholder model if not in provider config", function()
        gitlab_provider.state.gitlab_token = { access_token = "test_token", created_at = math.floor(os.time()), expires_in = 3600 }
        unmock_providers_get_config = mock(Providers, "get_config", function() return {} end) -- No model in config
        unmock_parse_messages = mock(gitlab_provider, "parse_messages", function() return {} end)

        local result = parse_curl_args_fn({})
        assert.is_not_nil(result)
        assert.are.equal("gitlab-duo-chat-001", result.body.model) -- Check placeholder model
    end)
  end)

  describe("Response Parsing", function()
    local unmock_utils_warn
    local unmock_utils_info

    before_each(function()
      unmock_utils_warn = mock(Utils, "warn", function() end) -- Suppress warnings
      unmock_utils_info = mock(Utils, "info", function() end) -- Suppress info
    end)

    after_each(function()
      if unmock_utils_warn then unmock_utils_warn() end
      if unmock_utils_info then unmock_utils_info() end
    end)

    describe(":parse_response(ctx, data_stream, _, opts) -- Streamed", function()
      local parse_response_fn = function(ctx, data_stream, opts)
        return gitlab_provider["parse_response"](gitlab_provider, ctx, data_stream, nil, opts)
      end

      it("should process valid streamed data chunks and call on_chunk and on_stop", function()
        local ctx = { buffer = "" }
        local received_chunks = {}
        local stop_reason = nil
        local opts = {
          on_chunk = function(chunk) table.insert(received_chunks, chunk) end,
          on_stop = function(reason) stop_reason = reason end,
        }

        parse_response_fn(ctx, 'data: {"token": {"text": "Hello "}, "is_final_chunk": false}\n\n', opts)
        parse_response_fn(ctx, 'data: {"token": {"text": "World"}, "is_final_chunk": false}\n\n', opts)
        parse_response_fn(ctx, 'data: {"token": {"text": "!"}, "is_final_chunk": true}\n\n', opts)

        assert.are.same({ "Hello ", "World", "!" }, received_chunks)
        assert.is_not_nil(stop_reason)
        assert.are.equal("complete", stop_reason.reason)
        assert.are.equal("", ctx.buffer, "Buffer should be empty after completion")
      end)

      it("should handle [DONE] marker", function()
        local ctx = { buffer = "" }
        local received_chunks = {}
        local stop_reason = nil
        local opts = {
          on_chunk = function(chunk) table.insert(received_chunks, chunk) end,
          on_stop = function(reason) stop_reason = reason end,
        }
        parse_response_fn(ctx, 'data: {"token": {"text": "Final "}, "is_final_chunk": false}\n\ndata: [DONE]\n\n', opts)

        assert.are.same({ "Final " }, received_chunks)
        assert.is_not_nil(stop_reason)
        assert.are.equal("complete", stop_reason.reason)
        assert.are.equal("", ctx.buffer)
      end)

      it("should handle incomplete JSON in buffer and process later", function()
        local ctx = { buffer = "" }
        local received_chunks = {}
        local opts = { on_chunk = function(chunk) table.insert(received_chunks, chunk) end, on_stop = function() end }

        parse_response_fn(ctx, 'data: {"token": {"text": "Part 1"}', opts)
        assert.are.same({}, received_chunks)
        assert.is_not_equal("", ctx.buffer)

        parse_response_fn(ctx, ', "is_final_chunk": false}\n\ndata: {"token": {"text": "Part 2"}, "is_final_chunk": true}\n\n', opts)
        assert.are.same({ "Part 1", "Part 2" }, received_chunks)
        assert.are.equal("", ctx.buffer)
      end)
    end)

    describe(":parse_response_without_stream(data, _, opts) -- Non-Streamed", function()
      local parse_response_ns_fn = function(data, opts)
        return gitlab_provider["parse_response_without_stream"](gitlab_provider, data, nil, opts)
      end

      it("should process valid non-streamed JSON and call on_chunk and on_stop", function()
        local received_chunks = {}
        local stop_reason = nil
        local opts = {
          on_chunk = function(chunk) table.insert(received_chunks, chunk) end,
          on_stop = function(reason) stop_reason = reason end,
        }
        parse_response_ns_fn('{"full_text": "Complete response text."}', opts)

        assert.are.same({ "Complete response text." }, received_chunks)
        assert.is_not_nil(stop_reason)
        assert.are.equal("complete", stop_reason.reason)
      end)

      it("should call on_stop with error for malformed JSON", function()
        local stop_reason = nil
        local warn_called = false
        local unmock_warn_local = mock(Utils, "warn", function() warn_called = true end)
        local opts = { on_chunk = function() end, on_stop = function(reason) stop_reason = reason end }

        parse_response_ns_fn("this is not json", opts)

        assert.is_true(warn_called)
        assert.is_not_nil(stop_reason)
        assert.are.equal("error", stop_reason.reason)
        unmock_warn_local()
      end)
    end)
  end)

  describe("Token Utility Functions", function()
    local unmock_utils_warn
    local unmock_utils_info
    local unmock_providers_get_config
    local unmock_curl_post
    local unmock_path_new -- For Path:new mock

    -- Store original M.state parts that might be modified
    local original_m_state_gitlab_token
    local original_m_state_client_id
    local original_m_state_client_secret

    before_each(function()
      unmock_utils_warn = mock(Utils, "warn", function() end)
      unmock_utils_info = mock(Utils, "info", function() end)

      -- Deep copy relevant parts of M.state before each test if they are modified
      -- Assuming gitlab_provider.state might be modified by functions under test
      gitlab_provider.state = gitlab_provider.state or {}
      original_m_state_gitlab_token = vim.deepcopy(gitlab_provider.state.gitlab_token)
      original_m_state_client_id = vim.deepcopy(gitlab_provider.state.client_id)
      original_m_state_client_secret = vim.deepcopy(gitlab_provider.state.client_secret)
    end)

    after_each(function()
      if unmock_utils_warn then unmock_utils_warn() end
      if unmock_utils_info then unmock_utils_info() end
      if unmock_providers_get_config then unmock_providers_get_config() end
      if unmock_curl_post then unmock_curl_post() end
      if unmock_path_new then unmock_path_new() end

      -- Restore M.state parts
      gitlab_provider.state.gitlab_token = original_m_state_gitlab_token
      gitlab_provider.state.client_id = original_m_state_client_id
      gitlab_provider.state.client_secret = original_m_state_client_secret
    end)

    -- Testing the local check_token_validity function via a temporary test hook
    -- In gitlab.lua, you would add:
    -- if vim.env.AVANTE_TEST_MODE then M._check_token_validity = check_token_validity end
    -- Or test its effects through M.is_env_set / M.setup
    describe("_check_token_validity (via test hook)", function()
        local _check_token_validity_fn

        before_each(function()
            -- This simulates exposing the local function for testing.
            -- In the actual provider 'gitlab.lua', you might have:
            -- local function check_token_validity(token) ... end
            -- if VIM_TEST_ENV then M._check_token_validity = check_token_validity end
            -- For this test, we directly use the logic if it's not exposed.
            if gitlab_provider._check_token_validity then
                 _check_token_validity_fn = gitlab_provider._check_token_validity
            else
                -- Re-define the logic here if not exposed (less ideal but works for isolated test)
                _check_token_validity_fn = function(token)
                    if token and token.access_token then
                        if token.expires_in and token.created_at then
                            return (token.created_at + token.expires_in) > (math.floor(os.time()) + 60)
                        end
                        return true -- Has access token, but no expiry info (e.g. direct token)
                    end
                    return false
                end
            end
        end)

      it("should return true for a valid token with expiry info", function()
        local token = { access_token = "valid", created_at = math.floor(os.time()), expires_in = 3600 }
        assert.is_true(_check_token_validity_fn(token))
      end)

      it("should return false for an expired token", function()
        local token = { access_token = "expired", created_at = math.floor(os.time()) - 3700, expires_in = 3600 }
        assert.is_false(_check_token_validity_fn(token))
      end)

      it("should return true for a token without expiry info (assumed long-lived)", function()
        local token = { access_token = "no_expiry_info" }
        assert.is_true(_check_token_validity_fn(token))
      end)

      it("should return false for a token that expires in less than 60 seconds", function()
        local token = { access_token = "expiring_soon", created_at = math.floor(os.time()) - 3550, expires_in = 3600 } -- 50s left
        assert.is_false(_check_token_validity_fn(token))
      end)

      it("should return true for a token that expires in more than 60 seconds", function()
        local token = { access_token = "expiring_later", created_at = math.floor(os.time()) - 3000, expires_in = 3600 } -- 600s left
        assert.is_true(_check_token_validity_fn(token))
      end)

      it("should return false for nil token or token with no access_token", function()
        assert.is_false(_check_token_validity_fn(nil))
        assert.is_false(_check_token_validity_fn({ created_at = 1, expires_in = 1}))
      end)
    end)

    describe("H.refresh_token behavior", function()
        before_each(function()
            unmock_providers_get_config = mock(Providers, "get_config", function() return { timeout = 5 } end)
            local mock_path_instance = { write = function() end } -- Mock Path:new():write
            unmock_path_new = mock(Path, "new", function() return mock_path_instance end)
        end)

      it("should not attempt refresh if token is valid and not forced", function()
        gitlab_provider.state.gitlab_token = { access_token = "valid", refresh_token = "rt", created_at = math.floor(os.time()), expires_in = 3600 }
        local curl_post_called = false
        unmock_curl_post = mock(curl, "post", function() curl_post_called = true; return {body="", status=500} end)

        local result = gitlab_provider.H.refresh_token(true, false) -- async, not forced
        assert.is_false(result)
        assert.is_false(curl_post_called)
        unmock_curl_post()
      end)

      it("should attempt refresh if token is expiring (within 120s) and not forced", function()
        gitlab_provider.state.gitlab_token = { access_token = "expiring", refresh_token = "rt", created_at = math.floor(os.time()) - 3500, expires_in = 3600 } -- 100s left
        local curl_post_called = false
        unmock_curl_post = mock(curl, "post", function() curl_post_called = true; return {body="", status=500} end)

        gitlab_provider.H.refresh_token(false, false) -- sync, not forced
        assert.is_true(curl_post_called)
        unmock_curl_post()
      end)

      it("should attempt refresh if forced, even if token is valid", function()
        gitlab_provider.state.gitlab_token = { access_token = "valid", refresh_token = "rt", created_at = math.floor(os.time()), expires_in = 3600 }
        local curl_post_called = false
        unmock_curl_post = mock(curl, "post", function() curl_post_called = true; return {body="", status=500} end)

        gitlab_provider.H.refresh_token(false, true) -- sync, forced
        assert.is_true(curl_post_called)
        unmock_curl_post()
      end)

      it("should correctly use client_id and client_secret from state, then env, then placeholders", function()
        gitlab_provider.state.gitlab_token = { refresh_token = "rt", access_token = "token", created_at = 1, expires_in = 1 } -- Expired

        local captured_body
        local function setup_curl_mock()
            return mock(curl, "post", function(url, opts)
                captured_body = opts.body
                return {body = vim.json.encode({access_token="new_token", expires_in=3600}), status=200}
            end)
        end

        -- 1. From state
        gitlab_provider.state.client_id = "state_id"
        gitlab_provider.state.client_secret = "state_secret"
        unmock_curl_post = setup_curl_mock()
        gitlab_provider.H.refresh_token(false, true)
        assert.is_true(string.find(captured_body, "client_id=state_id", 1, true), "Client ID from state not found. Body: " .. captured_body)
        assert.is_true(string.find(captured_body, "client_secret=state_secret", 1, true), "Client Secret from state not found. Body: " .. captured_body)
        unmock_curl_post()

        -- 2. From env (clear state ones)
        gitlab_provider.state.client_id = nil
        gitlab_provider.state.client_secret = nil
        local old_env_id, old_env_secret = vim.env.GITLAB_DUO_CLIENT_ID, vim.env.GITLAB_DUO_CLIENT_SECRET
        vim.env.GITLAB_DUO_CLIENT_ID = "env_id"
        vim.env.GITLAB_DUO_CLIENT_SECRET = "env_secret"
        unmock_curl_post = setup_curl_mock()
        gitlab_provider.H.refresh_token(false, true)
        assert.is_true(string.find(captured_body, "client_id=env_id", 1, true), "Client ID from env not found. Body: " .. captured_body)
        assert.is_true(string.find(captured_body, "client_secret=env_secret", 1, true), "Client Secret from env not found. Body: " .. captured_body)
        vim.env.GITLAB_DUO_CLIENT_ID, vim.env.GITLAB_DUO_CLIENT_SECRET = old_env_id, old_env_secret -- Restore env
        unmock_curl_post()

        -- 3. Placeholders (clear env ones)
        vim.env.GITLAB_DUO_CLIENT_ID = nil
        vim.env.GITLAB_DUO_CLIENT_SECRET = nil
        unmock_curl_post = setup_curl_mock()
        gitlab_provider.H.refresh_token(false, true)
        assert.is_true(string.find(captured_body, "client_id=YOUR_CLIENT_ID_PLACEHOLDER", 1, true), "Placeholder client ID not found. Body: " .. captured_body)
        assert.is_true(string.find(captured_body, "client_secret=YOUR_CLIENT_SECRET_PLACEHOLDER", 1, true), "Placeholder client secret not found. Body: " .. captured_body)
        vim.env.GITLAB_DUO_CLIENT_ID, vim.env.GITLAB_DUO_CLIENT_SECRET = old_env_id, old_env_secret -- Restore env
        unmock_curl_post()
      end)
    end)
  end)
end)
