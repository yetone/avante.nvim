-- tests/providers/gitlab_spec.lua
local gitlab_provider = require("avante.providers.gitlab")
local Providers = require("avante.providers")
local Utils = require("avante.utils")
local curl = require("plenary.curl") -- For mocking curl.post
local Path = require("plenary.path") -- For mocking Path:new if needed by helpers

-- Mocking utility
local mocks = {}
local function mock(obj, key, temp_val)
  local original = obj[key]
  obj[key] = temp_val
  table.insert(mocks, function() obj[key] = original end)
end

local function unmock_all()
  for i = #mocks, 1, -1 do mocks[i]() end
  mocks = {}
end

-- Deep compare for tables
local deep_compare
deep_compare = function(t1, t2)
  if type(t1) ~= type(t2) then return false end
  if type(t1) ~= "table" then return t1 == t2 end
  local k1, k2 = {}, {}
  for k in pairs(t1) do table.insert(k1, k) end
  for k in pairs(t2) do table.insert(k2, k) end
  if #k1 ~= #k2 then return false end
  table.sort(k1); table.sort(k2)
  for i = 1, #k1 do
    if k1[i] ~= k2[i] then return false end
    if not deep_compare(t1[k1[i]], t2[k1[i]]) then return false end
  end
  return true
end

describe("Avante GitLab Duo Provider (Direct Access Workflow)", function()
  local original_env_gitlab_token

  before_each(function()
    original_env_gitlab_token = vim.env.GITLAB_TOKEN
    vim.env.GITLAB_TOKEN = nil

    gitlab_provider.state = nil -- Fully reset state
    gitlab_provider._is_setup = false
    vim.g.avante_login = false

    mock(Utils, "warn", function(...) end) -- Suppress output in tests
    mock(Utils, "info", function(...) end)
    mock(Utils, "debug", function(...) end)
    mock(Providers, "get_config", function() return { gitlab_instance_url = "https://gitlab.com" } end)
    mock(Path, "new", function(path_str)
        return { path = path_str, basename = function() return path_str:match("([^/]+)$") or path_str end }
    end)
  end)

  after_each(function()
    unmock_all()
    vim.env.GITLAB_TOKEN = original_env_gitlab_token
    gitlab_provider.state = nil -- Clean up state post-test
  end)

  describe("H.fetch_and_store_ai_gateway_credentials", function()
    it("should fetch and store credentials on success", function()
      vim.env.GITLAB_TOKEN = "user_main_token"
      gitlab_provider.setup() -- To set user_gitlab_token in state

      local mock_response = {
        status = 200,
        body = vim.json.encode({
          base_url = "http://ai.gateway",
          token = "gateway_token_123",
          expires_at = os.time() + 3600,
          headers = { ["X-Custom-Header"] = "value" },
        }),
      }
      mock(curl, "post", function() return mock_response end)

      local result = gitlab_provider.H.fetch_and_store_ai_gateway_credentials()
      assert.is_true(result)
      assert.are.equal("http://ai.gateway", gitlab_provider.state.ai_gateway_base_url)
      assert.are.equal("gateway_token_123", gitlab_provider.state.ai_gateway_token)
      assert.is_not_nil(gitlab_provider.state.ai_gateway_token_expires_at)
      assert.is_true(deep_compare({ ["X-Custom-Header"] = "value" }, gitlab_provider.state.ai_gateway_headers))
      assert.is_true(vim.g.avante_login)
    end)
  end)

  describe("M.setup()", function()
    it("should read GITLAB_TOKEN into state.user_gitlab_token", function()
      vim.env.GITLAB_TOKEN = "setup_token"
      gitlab_provider.setup()
      assert.are.equal("setup_token", gitlab_provider.state.user_gitlab_token)
      assert.is_false(vim.g.avante_login)
      assert.is_true(gitlab_provider._is_setup)
    end)
  end)

  describe("M.is_env_set()", function()
    it("should return false if user_gitlab_token is not set", function()
      vim.env.GITLAB_TOKEN = nil
      gitlab_provider.setup()
      assert.is_false(gitlab_provider:is_env_set())
      assert.is_false(vim.g.avante_login)
    end)

    it("should use valid cached AI gateway creds and not re-fetch", function()
      vim.env.GITLAB_TOKEN = "user_token"
      gitlab_provider.setup()
      gitlab_provider.state.ai_gateway_token = "cached_gw_token"
      gitlab_provider.state.ai_gateway_token_expires_at = os.time() + 3600
      gitlab_provider.state.ai_gateway_base_url = "cached_url"
      gitlab_provider.state.ai_gateway_headers = {}
      local fetch_spy_called = false
      mock(gitlab_provider.H, "fetch_and_store_ai_gateway_credentials", function() fetch_spy_called = true; return true end)
      assert.is_true(gitlab_provider:is_env_set())
      assert.is_false(fetch_spy_called)
      assert.is_true(vim.g.avante_login)
    end)

    it("should fetch AI gateway creds if none cached", function()
      vim.env.GITLAB_TOKEN = "user_token"
      gitlab_provider.setup()
      local fetch_called = false
      mock(gitlab_provider.H, "fetch_and_store_ai_gateway_credentials", function() fetch_called = true; return true end)
      assert.is_true(gitlab_provider:is_env_set())
      assert.is_true(fetch_called)
    end)
  end)

  describe("M:parse_curl_args()", function()
    before_each(function()
      vim.env.GITLAB_TOKEN = "user_main_token_for_curl_args"
      gitlab_provider.setup()
      mock(gitlab_provider.H, "fetch_and_store_ai_gateway_credentials", function()
        gitlab_provider.state.ai_gateway_base_url = "http://mocked.gateway.url"
        gitlab_provider.state.ai_gateway_token = "mocked_gateway_ephemeral_token"
        gitlab_provider.state.ai_gateway_token_expires_at = os.time() + 3600
        gitlab_provider.state.ai_gateway_headers = { ["X-Mock-Header"] = "MockValue" }
        vim.g.avante_login = true
        return true
      end)
    end)

    it("should return nil if is_env_set (credential fetching) fails", function()
      unmock_all() -- Clear previous mocks
      mock(Utils, "warn", function() end); mock(Utils, "info", function() end); mock(Utils, "debug", function() end)
      mock(Providers, "get_config", function() return {} end)
      vim.env.GITLAB_TOKEN = "user_token_for_fail_case"
      gitlab_provider.state = { user_gitlab_token = "user_token_for_fail_case" }
      mock(gitlab_provider.H, "fetch_and_store_ai_gateway_credentials", function() vim.g.avante_login = false; return false end)
      local result = gitlab_provider:parse_curl_args({})
      assert.is_nil(result)
    end)

    it("should use AI Gateway URL, token, and headers for CHAT", function()
      local result = gitlab_provider:parse_curl_args({ messages = {{role="user", content="hi"}} })
      assert.is_not_nil(result)
      assert.are.equal("http://mocked.gateway.url/v1/agent/chat", result.url)
      assert.are.equal("Bearer mocked_gateway_ephemeral_token", result.headers["Authorization"])
      assert.are.equal("MockValue", result.headers["X-Mock-Header"])
      assert.are.equal("oidc", result.headers["X-Gitlab-Authentication-Type"])
      assert.is_false(result.is_streaming)
    end)
  end)

  describe("Request Body Builders (H table) - AI Gateway Payloads", function()
    before_each(function()
        mock(Path, "new", function(path_str)
            return { path = path_str, basename = function() return path_str:match("([^/]+)$") or path_str end }
        end)
    end)
    describe("H.build_code_suggestion_body", function()
      it("should build correct body for code suggestion", function()
        local prompt_opts = { content_above_cursor = "above", content_below_cursor = "below", current_file_path = "/path/to/file.lua", language_identifier = "lua_test" }
        local provider_conf = { code_suggestion_model = "cs_model_conf" }
        local body = gitlab_provider.H.build_code_suggestion_body(prompt_opts, provider_conf)
        local p = body.prompt_components[1].payload
        assert.are.equal("code_editor_completion", body.prompt_components[1].type)
        assert.are.equal("file.lua", p.file_name)
        assert.are.equal("cs_model_conf", p.model_name)
      end)
    end)
    describe("H.build_chat_body", function()
      it("should build correct body for chat", function()
        local prompt_opts = { system_prompt = "Sys", messages = { { role = "user", content = "Test" } } }
        local provider_conf = { chat_model = "chat_model_conf" }
        mock(gitlab_provider, "parse_messages", function() return {{role="system", content="Sys"}, {role="user", content="Test"}} end)
        local body = gitlab_provider.H.build_chat_body(prompt_opts, provider_conf)
        local p = body.prompt_components[1].payload
        assert.are.equal("prompt", body.prompt_components[1].type)
        assert.are.equal("anthropic", p.provider)
        assert.are.equal("chat_model_conf", p.model)
      end)
    end)
  end)

  describe("M:parse_messages (for chat payload) - AI Gateway", function()
    it("should format system, user, and assistant messages correctly", function()
      local opts = { system_prompt = "You are a bot.", messages = { { role = "user", content = "Hello" }, { role = "assistant", content = "Hi there" } } }
      local expected = { { role = "system", content = "You are a bot." }, { role = "user", content = "Hello" }, { role = "assistant", content = "Hi there" } }
      assert.is_true(deep_compare(expected, gitlab_provider:parse_messages(opts)))
    end)
  end)

  describe("Response Parsers - AI Gateway Responses", function()
    describe("M:parse_response (SSE for Code Suggestions)", function()
      it("should parse valid SSE stream for code suggestions", function()
        local ctx = { buffer = "", current_event_type = nil }
        local chunks = {}
        local stop_reason = nil
        local opts = { on_chunk = function(c) table.insert(chunks, c) end, on_stop = function(r) stop_reason = r end }
        gitlab_provider:parse_response(ctx, 'event: stream_start\ndata: {\"metadata\": \"test\"}\n\n', nil, opts)
        gitlab_provider:parse_response(ctx, 'event: content_chunk\ndata: {\"choices\": [{\"delta\": {\"content\": \"Hello \"}}]}', nil, opts)
        gitlab_provider:parse_response(ctx, '\n\nevent: content_chunk\ndata: {\"choices\": [{\"delta\": {\"content\": \"World!\"}}]}', nil, opts)
        gitlab_provider:parse_response(ctx, '\n\nevent: stream_end\ndata: null\n\n', nil, opts)
        assert.is_true(deep_compare({"Hello ", "World!"}, chunks))
        assert.is_not_nil(stop_reason); assert.are.equal("complete", stop_reason.reason)
      end)
    end)
    describe("M:parse_response_without_stream (JSON for Chat)", function()
      it("should parse valid JSON chat response", function()
        local chunk = nil; local stop_reason = nil
        local opts = { on_chunk = function(c) chunk = c end, on_stop = function(r) stop_reason = r end }
        gitlab_provider:parse_response_without_stream('{"response": "Chat says hi", "metadata": {}}', nil, opts)
        assert.are.equal("Chat says hi", chunk)
        assert.is_not_nil(stop_reason); assert.are.equal("complete", stop_reason.reason)
      end)
    end)
  end)
end)
