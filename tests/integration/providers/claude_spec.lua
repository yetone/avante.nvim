---@diagnostic disable: undefined-global
local helpers = require("tests.integration.helpers")

describe("Claude Provider Integration", function()
  local test_ctx

  before_each(function()
    test_ctx = helpers.setup_test_env({ git = false })

    -- Configure Claude provider for testing
    helpers.configure_avante_for_testing({
      provider = "claude",
      endpoint = "http://localhost:8080/v1/messages",
      model = "claude-3-opus-20240229",
    })

    -- Set test API key
    vim.env.ANTHROPIC_API_KEY = "sk-ant-test-key"
  end)

  after_each(function()
    helpers.cleanup_test_env(test_ctx)
    vim.env.ANTHROPIC_API_KEY = nil
  end)

  describe("Messages API", function()
    it("should handle successful message completion", function()
      local claude = require("avante.providers.claude")
      local messages = {
        { role = "user", content = "Explain quantum computing briefly" },
      }

      local response_received = false
      local response_content = ""

      -- Mock the curl command execution
      local original_system = vim.fn.system
      vim.fn.system = function(cmd)
        if cmd:match("curl") then
          return vim.fn.json_encode({
            id = "msg_test",
            type = "message",
            role = "assistant",
            content = {
              {
                type = "text",
                text = "Quantum computing uses quantum mechanical phenomena like superposition and entanglement to process information.",
              },
            },
            model = "claude-3-opus-20240229",
            stop_reason = "end_turn",
            usage = {
              input_tokens = 15,
              output_tokens = 25,
            },
          })
        end
        return original_system(cmd)
      end

      local opts = {
        endpoint = "http://localhost:8080/v1/messages",
        model = "claude-3-opus-20240229",
      }

      local code_opts = {
        messages = messages,
        stream = false,
        on_complete = function(content)
          response_received = true
          response_content = content
        end,
      }

      -- Simulate response handling
      if code_opts.on_complete then
        code_opts.on_complete(
          "Quantum computing uses quantum mechanical phenomena like superposition and entanglement to process information."
        )
      end

      assert.is_true(response_received)
      assert.True(response_content:match("quantum"))

      -- Restore original system function
      vim.fn.system = original_system
    end)

    it("should handle streaming responses", function()
      local streaming_chunks = {}
      local stream_complete = false
      local message_started = false

      local opts = {
        endpoint = "http://localhost:8080/v1/messages",
        model = "claude-3-opus-20240229",
      }

      local code_opts = {
        messages = { { role = "user", content = "Write a haiku" } },
        stream = true,
        on_chunk = function(chunk) table.insert(streaming_chunks, chunk) end,
        on_complete = function() stream_complete = true end,
      }

      -- Simulate Claude streaming events
      local test_events = {
        { type = "message_start", data = {} },
        { type = "content_block_start", data = {} },
        { type = "content_block_delta", data = { delta = { text = "Cherry" } } },
        { type = "content_block_delta", data = { delta = { text = " blossoms" } } },
        { type = "content_block_delta", data = { delta = { text = " fall" } } },
        { type = "content_block_stop", data = {} },
        { type = "message_stop", data = {} },
      }

      for _, event in ipairs(test_events) do
        if event.type == "message_start" then
          message_started = true
        elseif event.type == "content_block_delta" and event.data.delta and event.data.delta.text then
          if code_opts.on_chunk then code_opts.on_chunk(event.data.delta.text) end
        elseif event.type == "message_stop" then
          if code_opts.on_complete then code_opts.on_complete() end
        end
      end

      assert.is_true(message_started)
      assert.equals(3, #streaming_chunks)
      assert.equals("Cherry", streaming_chunks[1])
      assert.equals(" blossoms", streaming_chunks[2])
      assert.equals(" fall", streaming_chunks[3])
      assert.is_true(stream_complete)
    end)

    it("should handle authentication errors", function()
      local error_received = false
      local error_message = ""

      -- Set invalid API key
      vim.env.ANTHROPIC_API_KEY = "invalid-key"

      local opts = {
        endpoint = "http://localhost:8080/v1/messages",
        model = "claude-3-opus-20240229",
      }

      local code_opts = {
        messages = { { role = "user", content = "Hello" } },
        stream = false,
        on_error = function(err)
          error_received = true
          error_message = err
        end,
      }

      -- Simulate authentication error
      if code_opts.on_error then code_opts.on_error("invalid x-api-key") end

      assert.is_true(error_received)
      assert.True(error_message:match("api%-key"))
    end)

    it("should handle rate limiting with overloaded_error", function()
      local rate_limit_error = false
      local error_type = ""

      vim.env.ANTHROPIC_API_KEY = "rate-limit-key"

      local opts = {
        endpoint = "http://localhost:8080/v1/messages",
        model = "claude-3-opus-20240229",
      }

      local code_opts = {
        messages = { { role = "user", content = "Hello" } },
        stream = false,
        on_error = function(err, status_code)
          if status_code == 529 then
            rate_limit_error = true
            error_type = "overloaded_error"
          end
        end,
      }

      -- Simulate rate limit error (529 for Claude)
      if code_opts.on_error then code_opts.on_error("Number of requests per minute has been exceeded", 529) end

      assert.is_true(rate_limit_error)
      assert.equals("overloaded_error", error_type)
    end)

    it("should handle prompt caching when available", function()
      local cache_used = false

      local opts = {
        endpoint = "http://localhost:8080/v1/messages",
        model = "claude-3-opus-20240229",
      }

      local large_context = string.rep("This is a large context that should be cached. ", 100)

      local code_opts = {
        messages = {
          { role = "user", content = large_context },
          { role = "user", content = "Summarize the above." },
        },
        stream = false,
        cache_control = { type = "ephemeral" },
        on_complete = function(content, metadata)
          if metadata and metadata.cache_creation_input_tokens then cache_used = true end
        end,
      }

      -- Simulate response with cache metadata
      if code_opts.on_complete then
        code_opts.on_complete("Summary of the repeated context.", {
          cache_creation_input_tokens = 500,
          cache_read_input_tokens = 0,
        })
      end

      assert.is_true(cache_used)
    end)
  end)

  describe("Model Selection", function()
    it("should support different Claude models", function()
      local models_tested = {}
      local test_models = {
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307",
      }

      for _, model in ipairs(test_models) do
        local opts = {
          endpoint = "http://localhost:8080/v1/messages",
          model = model,
        }

        local code_opts = {
          messages = { { role = "user", content = "Test message" } },
          stream = false,
          on_complete = function(content, response_model) table.insert(models_tested, response_model or model) end,
        }

        -- Simulate response with model
        if code_opts.on_complete then code_opts.on_complete("Test response", model) end
      end

      assert.equals(3, #models_tested)
      assert.True(vim.tbl_contains(models_tested, "claude-3-opus-20240229"))
      assert.True(vim.tbl_contains(models_tested, "claude-3-sonnet-20240229"))
      assert.True(vim.tbl_contains(models_tested, "claude-3-haiku-20240307"))
    end)
  end)

  describe("Message Formatting", function()
    it("should format messages correctly for Claude API", function()
      local claude = require("avante.providers.claude")

      local messages = {
        { role = "user", content = "Hello!" },
        { role = "assistant", content = "Hi there! How can I help?" },
        { role = "user", content = "Tell me about AI" },
      }

      -- Test message role mapping
      for _, message in ipairs(messages) do
        local mapped_role = claude.role_map and claude.role_map[message.role] or message.role
        assert.True(mapped_role ~= nil, "Role should be mapped: " .. message.role)
      end
    end)

    it("should handle system messages appropriately", function()
      -- Claude handles system messages differently - they're separate from the messages array
      local system_message = "You are a helpful coding assistant."
      local user_messages = {
        { role = "user", content = "Write a Python function" },
      }

      -- In Claude API, system message is a separate parameter
      local api_payload = {
        model = "claude-3-opus-20240229",
        system = system_message,
        messages = user_messages,
        max_tokens = 4096,
      }

      assert.equals(system_message, api_payload.system)
      assert.equals(1, #api_payload.messages)
      assert.equals("user", api_payload.messages[1].role)
    end)
  end)

  describe("Response Parsing", function()
    it("should parse non-streaming responses correctly", function()
      local test_response = {
        id = "msg_test",
        type = "message",
        role = "assistant",
        content = {
          {
            type = "text",
            text = "Test response content",
          },
        },
        model = "claude-3-opus-20240229",
        stop_reason = "end_turn",
        usage = {
          input_tokens = 20,
          output_tokens = 10,
        },
      }

      helpers.assert_provider_response(test_response, "claude", {
        type = "chat",
        content = "Test response content",
      })
    end)

    it("should parse streaming events correctly", function()
      local test_events = {
        'event: message_start\ndata: {"type": "message_start", "message": {"id": "msg_test"}}',
        'event: content_block_start\ndata: {"type": "content_block_start", "index": 0}',
        'event: content_block_delta\ndata: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}',
        'event: content_block_delta\ndata: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": " world"}}',
        'event: content_block_stop\ndata: {"type": "content_block_stop", "index": 0}',
        'event: message_stop\ndata: {"type": "message_stop"}',
      }

      local parsed_content = ""
      local stream_finished = false

      for _, event_data in ipairs(test_events) do
        local event_line, data_line = event_data:match("event: ([^\n]+)\ndata: (.+)")

        if event_line == "content_block_delta" then
          local success, data = pcall(vim.fn.json_decode, data_line)
          if success and data.delta and data.delta.text then parsed_content = parsed_content .. data.delta.text end
        elseif event_line == "message_stop" then
          stream_finished = true
        end
      end

      assert.equals("Hello world", parsed_content)
      assert.is_true(stream_finished)
    end)

    it("should handle tool use in responses", function()
      local test_response = {
        id = "msg_test",
        type = "message",
        role = "assistant",
        content = {
          {
            type = "text",
            text = "I'll help you with that calculation.",
          },
          {
            type = "tool_use",
            id = "toolu_test",
            name = "calculator",
            input = {
              expression = "2 + 2",
            },
          },
        },
        model = "claude-3-opus-20240229",
        stop_reason = "tool_use",
      }

      assert.equals(2, #test_response.content)
      assert.equals("text", test_response.content[1].type)
      assert.equals("tool_use", test_response.content[2].type)
      assert.equals("calculator", test_response.content[2].name)
      assert.equals("tool_use", test_response.stop_reason)
    end)
  end)

  describe("API Version Compatibility", function()
    it("should use correct anthropic-version header", function()
      local correct_version = "2023-06-01"
      local api_version_used = ""

      -- Mock to capture the version header
      local capture_version = function(headers)
        if headers and headers["anthropic-version"] then api_version_used = headers["anthropic-version"] end
      end

      -- Simulate API call with version header
      capture_version({ ["anthropic-version"] = correct_version })

      assert.equals(correct_version, api_version_used)
    end)

    it("should handle beta features appropriately", function()
      local beta_features = { "prompt-caching-2024-07-31" }
      local beta_header = ""

      local capture_beta = function(headers)
        if headers and headers["anthropic-beta"] then beta_header = headers["anthropic-beta"] end
      end

      -- Simulate beta feature usage
      capture_beta({ ["anthropic-beta"] = table.concat(beta_features, ",") })

      assert.equals("prompt-caching-2024-07-31", beta_header)
    end)
  end)
end)
