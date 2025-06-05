-- tests/providers/gitlab_spec.lua
local gitlab_provider = require("avante.providers.gitlab")
local Providers = require("avante.providers") -- To mock get_config
local Utils = require("avante.utils") -- For mocking warn/info/debug
local Path = require("plenary.path") -- For mocking Path:new

-- Mocking utility
local function mock(obj, key, temp_val)
  local original = obj[key]
  obj[key] = temp_val
  return function() obj[key] = original end
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
  table.sort(k1)
  table.sort(k2)
  for i = 1, #k1 do
    if k1[i] ~= k2[i] then return false end
    if not deep_compare(t1[k1[i]], t2[k1[i]]) then return false end
  end
  return true
end

describe("Avante GitLab Duo Provider (New API)", function()
  local original_env_gitlab_token
  local unmock_utils_warn, unmock_utils_info, unmock_utils_debug
  local unmock_providers_get_config
  local unmock_vim_bo_filetype

  before_each(function()
    original_env_gitlab_token = vim.env.GITLAB_TOKEN
    vim.env.GITLAB_TOKEN = nil -- Ensure clean state for env

    -- Reset provider state before each test
    gitlab_provider.state = { access_token = nil }
    gitlab_provider._is_setup = false
    vim.g.avante_login = false

    unmock_utils_warn = mock(Utils, "warn", function() end)
    unmock_utils_info = mock(Utils, "info", function() end)
    unmock_utils_debug = mock(Utils, "debug", function() end)
    unmock_providers_get_config = mock(Providers, "get_config", function() return {} end)
    unmock_vim_bo_filetype = mock(vim, "bo", { filetype = "lua" }) -- Mock global vim.bo
  end)

  after_each(function()
    vim.env.GITLAB_TOKEN = original_env_gitlab_token
    if unmock_utils_warn then unmock_utils_warn() end
    if unmock_utils_info then unmock_utils_info() end
    if unmock_utils_debug then unmock_utils_debug() end
    if unmock_providers_get_config then unmock_providers_get_config() end
    if unmock_vim_bo_filetype then unmock_vim_bo_filetype() end
  end)

  describe("Authentication and Setup", function()
    it("M.setup() should read GITLAB_TOKEN and set state", function()
      vim.env.GITLAB_TOKEN = "test_token_123"
      gitlab_provider.setup()
      assert.are.equal("test_token_123", gitlab_provider.state.access_token)
      assert.is_true(vim.g.avante_login)
      assert.is_true(gitlab_provider._is_setup)
    end)

    it("M.setup() should handle missing GITLAB_TOKEN", function()
      vim.env.GITLAB_TOKEN = nil
      gitlab_provider.setup()
      assert.is_nil(gitlab_provider.state.access_token)
      assert.is_false(vim.g.avante_login)
    end)

    it("M.is_env_set() should reflect GITLAB_TOKEN status", function()
      vim.env.GITLAB_TOKEN = "another_token"
      assert.is_true(gitlab_provider.is_env_set())
      assert.is_true(vim.g.avante_login)
      assert.are.equal("another_token", gitlab_provider.state.access_token)

      vim.env.GITLAB_TOKEN = nil
      gitlab_provider.state.access_token = nil -- reset for testing this specific call path
      assert.is_false(gitlab_provider.is_env_set())
      assert.is_false(vim.g.avante_login)
    end)
  end)

  describe("M:parse_messages (for chat payload)", function()
    local parse_messages_fn = function(opts)
      return gitlab_provider["parse_messages"](gitlab_provider, opts)
    end

    it("should format system, user, and assistant messages correctly", function()
      local opts = {
        system_prompt = "You are a bot.",
        messages = {
          { role = "user", content = "Hello" },
          { role = "assistant", content = "Hi there" },
        },
      }
      local expected = {
        { role = "system", content = "You are a bot." },
        { role = "user", content = "Hello" },
        { role = "assistant", content = "Hi there" },
      }
      assert.is_true(deep_compare(expected, parse_messages_fn(opts)))
    end)

    it("should handle consecutive user messages with a dummy assistant message", function()
        local opts = {
            messages = {
                { role = "user", content = "User 1" },
                { role = "user", content = "User 2" },
            }
        }
        local result = parse_messages_fn(opts)
        assert.are.same("user", result[1].role)
        assert.are.same("assistant", result[2].role) -- Dummy
        assert.are.same("user", result[3].role)
    end)
  end)

  local mock_path_instance = { basename = function(self) return self.path end } -- Simplified mock
  local unmock_path_new

  describe("Request Body Builders (H table)", function()
    before_each(function()
        unmock_path_new = mock(Path, "new", function(path_str)
            return { path = path_str, basename = function() return path_str:match("([^/]+)$") or path_str end }
        end)
    end)
    after_each(function()
        if unmock_path_new then unmock_path_new() end
    end)

    describe("H.build_code_suggestion_body", function()
      it("should build correct body for code suggestion", function()
        local prompt_opts = {
          content_above_cursor = "above",
          content_below_cursor = "below",
          current_file_path = "/path/to/file.lua",
          language_identifier = "lua_test",
        }
        local provider_conf = { code_suggestion_model = "cs_model_conf" }
        local body = gitlab_provider.H.build_code_suggestion_body(prompt_opts, provider_conf)
        local p = body.prompt_components[1].payload
        assert.are.equal("code_editor_completion", body.prompt_components[1].type)
        assert.are.equal("file.lua", p.file_name)
        assert.are.equal("above", p.content_above_cursor)
        assert.are.equal("below", p.content_below_cursor)
        assert.are.equal("lua_test", p.language_identifier)
        assert.are.equal("cs_model_conf", p.model_name)
        assert.is_true(p.stream)
      end)

      it("model fallback: provider_conf.model then default", function()
        local prompt_opts = {}
        local provider_conf = { model = "general_model" }
        local p1 = gitlab_provider.H.build_code_suggestion_body(prompt_opts, provider_conf).prompt_components[1].payload
        assert.are.equal("general_model", p1.model_name)

        local p2 = gitlab_provider.H.build_code_suggestion_body(prompt_opts, {}).prompt_components[1].payload
        assert.are.equal("code-gecko@002", p2.model_name) -- Default
      end)
    end)

    describe("H.build_chat_body", function()
      it("should build correct body for chat", function()
        local prompt_opts = { system_prompt = "Sys", messages = { { role = "user", content = "Test" } } }
        local provider_conf = { chat_model = "chat_model_conf" }
        local unmock_gm = mock(gitlab_provider, "parse_messages", function() return {{role="system", content="Sys"}, {role="user", content="Test"}} end)

        local body = gitlab_provider.H.build_chat_body(prompt_opts, provider_conf)
        local p = body.prompt_components[1].payload
        assert.are.equal("prompt", body.prompt_components[1].type)
        assert.is_true(deep_compare({{role="system", content="Sys"}, {role="user", content="Test"}}, p.content))
        assert.are.equal("anthropic", p.provider)
        assert.are.equal("chat_model_conf", p.model)
        assert.are.equal("AvanteNvim", body.prompt_components[1].metadata.source)
        unmock_gm()
      end)

      it("model fallback: provider_conf.model then default", function()
        local prompt_opts = {messages = {}}
        local unmock_gm = mock(gitlab_provider, "parse_messages", function() return {} end)

        local provider_conf = { model = "general_chat_model" }
        local p1 = gitlab_provider.H.build_chat_body(prompt_opts, provider_conf).prompt_components[1].payload
        assert.are.equal("general_chat_model", p1.model)

        local p2 = gitlab_provider.H.build_chat_body(prompt_opts, {}).prompt_components[1].payload
        assert.are.equal("claude-3-5-sonnet-20240620", p2.model) -- Default
        unmock_gm()
      end)
    end)
  end)

  describe("M:parse_curl_args (Dispatch & Headers)", function()
    local parse_curl_args_fn = function(opts) return gitlab_provider["parse_curl_args"](gitlab_provider, opts) end

    before_each(function()
        gitlab_provider.state.access_token = "fake_token" -- Needs a token for these tests
        unmock_path_new = mock(Path, "new", function(path_str)
            return { path = path_str, basename = function() return path_str:match("([^/]+)$") or path_str end }
        end)
    end)
    after_each(function()
        if unmock_path_new then unmock_path_new() end
    end)


    it("should dispatch to code suggestion", function()
      local prompt_opts = { content_above_cursor = "test" }
      local result = parse_curl_args_fn(prompt_opts)
      assert.is_not_nil(result.url:find("/v4/code/suggestions"))
      assert.is_true(result.is_streaming)
      assert.are.equal("code_editor_completion", result.body.prompt_components[1].type)
    end)

    it("should dispatch to chat", function()
      local prompt_opts = { messages = { {role="user", content="hi"} } }
      local result = parse_curl_args_fn(prompt_opts)
      assert.is_not_nil(result.url:find("/v1/agent/chat"))
      assert.is_false(result.is_streaming)
      assert.are.equal("prompt", result.body.prompt_components[1].type)
    end)

    it("should include correct auth headers", function()
      local result = parse_curl_args_fn({}) -- defaults to chat
      assert.are.equal("Bearer fake_token", result.headers["Authorization"])
      assert.are.equal("oidc", result.headers["X-Gitlab-Authentication-Type"])
    end)
  end)

  describe("Response Parsers", function()
    describe("M:parse_response (SSE for Code Suggestions)", function()
      local parse_fn = function(ctx, data, opts) return gitlab_provider["parse_response"](gitlab_provider, ctx, data, nil, opts) end

      it("should parse valid SSE stream for code suggestions", function()
        local ctx = { buffer = "" }
        local chunks = {}
        local stop_reason = nil
        local opts = { on_chunk = function(c) table.insert(chunks, c) end, on_stop = function(r) stop_reason = r end }

        parse_fn(ctx, 'event: stream_start\ndata: {"metadata": "test"}\n\n', opts)
        parse_fn(ctx, 'event: content_chunk\ndata: {"choices": [{"delta": {"content": "Hello "}}]}', opts) -- Incomplete SSE
        parse_fn(ctx, '\n\nevent: content_chunk\ndata: {"choices": [{"delta": {"content": "World!"}}]}', opts) -- Incomplete
        parse_fn(ctx, '\n\nevent: stream_end\ndata: null\n\n', opts)

        assert.is_true(deep_compare({"Hello ", "World!"}, chunks))
        assert.is_not_nil(stop_reason)
        assert.are.equal("complete", stop_reason.reason)
        assert.are.equal("", ctx.buffer)
      end)
    end)

    describe("M:parse_response_without_stream (JSON for Chat)", function()
      local parse_fn_ns = function(data, opts) return gitlab_provider["parse_response_without_stream"](gitlab_provider, data, nil, opts) end

      it("should parse valid JSON chat response", function()
        local chunk = nil
        local stop_reason = nil
        local opts = { on_chunk = function(c) chunk = c end, on_stop = function(r) stop_reason = r end }

        parse_fn_ns('{"response": "Chat says hi", "metadata": {}}', opts)
        assert.are.equal("Chat says hi", chunk)
        assert.is_not_nil(stop_reason)
        assert.are.equal("complete", stop_reason.reason)
      end)

      it("should handle missing 'response' field", function()
        local stop_reason = nil
        local opts = { on_chunk = function() end, on_stop = function(r) stop_reason = r end }
        parse_fn_ns('{"other_field": "value"}', opts)
        assert.is_not_nil(stop_reason)
        assert.are.equal("error", stop_reason.reason)
      end)
    end)
  end)
end)
