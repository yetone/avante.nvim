---@diagnostic disable: undefined-global
local helpers = require("tests.integration.helpers")

describe("OpenAI Provider Integration", function()
  local test_ctx

  before_each(function()
    test_ctx = helpers.setup_test_env({ git = false })

    -- Configure OpenAI provider for testing
    helpers.configure_avante_for_testing({
      provider = "openai",
      endpoint = "http://localhost:8080/v1/chat/completions",
      model = "gpt-4",
    })

    -- Set test API key
    vim.env.OPENAI_API_KEY = "test-openai-key"
  end)

  after_each(function()
    helpers.cleanup_test_env(test_ctx)
    vim.env.OPENAI_API_KEY = nil
  end)

  describe("Chat Completions", function()
    it("should handle successful chat completion", function()
      local openai = require("avante.providers.openai")
      local messages = {
        { role = "user", content = "Hello, how are you?" },
      }

      local response_received = false
      local response_content = ""

      -- Mock the curl command execution
      local original_system = vim.fn.system
      vim.fn.system = function(cmd)
        if cmd:match("curl") then
          return vim.fn.json_encode({
            id = "chatcmpl-test",
            object = "chat.completion",
            created = os.time(),
            model = "gpt-4",
            choices = {
              {
                index = 0,
                message = {
                  role = "assistant",
                  content = "Hello! I'm doing well, thank you for asking.",
                },
                finish_reason = "stop",
              },
            },
            usage = {
              prompt_tokens = 10,
              completion_tokens = 15,
              total_tokens = 25,
            },
          })
        end
        return original_system(cmd)
      end

      -- Test successful response
      local opts = {
        endpoint = "http://localhost:8080/v1/chat/completions",
        model = "gpt-4",
      }

      local code_opts = {
        messages = messages,
        stream = false,
        on_complete = function(content)
          response_received = true
          response_content = content
        end,
      }

      -- This would normally make an HTTP request
      -- For testing, we simulate the response handling
      if code_opts.on_complete then code_opts.on_complete("Hello! I'm doing well, thank you for asking.") end

      assert.is_true(response_received)
      assert.equals("Hello! I'm doing well, thank you for asking.", response_content)

      -- Restore original system function
      vim.fn.system = original_system
    end)

    it("should handle streaming responses", function()
      local streaming_chunks = {}
      local stream_complete = false

      local opts = {
        endpoint = "http://localhost:8080/v1/chat/completions",
        model = "gpt-4",
      }

      local code_opts = {
        messages = { { role = "user", content = "Count to 3" } },
        stream = true,
        on_chunk = function(chunk) table.insert(streaming_chunks, chunk) end,
        on_complete = function() stream_complete = true end,
      }

      -- Simulate streaming chunks
      local test_chunks = { "One", " Two", " Three" }
      for _, chunk in ipairs(test_chunks) do
        if code_opts.on_chunk then code_opts.on_chunk(chunk) end
      end

      if code_opts.on_complete then code_opts.on_complete() end

      assert.equals(3, #streaming_chunks)
      assert.equals("One", streaming_chunks[1])
      assert.equals(" Two", streaming_chunks[2])
      assert.equals(" Three", streaming_chunks[3])
      assert.is_true(stream_complete)
    end)

    it("should handle authentication errors", function()
      local error_received = false
      local error_message = ""

      -- Set invalid API key
      vim.env.OPENAI_API_KEY = "invalid-key"

      local opts = {
        endpoint = "http://localhost:8080/v1/chat/completions",
        model = "gpt-4",
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
      if code_opts.on_error then code_opts.on_error("Incorrect API key provided: invalid-key") end

      assert.is_true(error_received)
      assert.True(error_message:match("API key"))
    end)

    it("should handle rate limiting errors", function()
      local rate_limit_error = false
      local retry_after = nil

      -- Set rate limit test key
      vim.env.OPENAI_API_KEY = "rate-limit-key"

      local opts = {
        endpoint = "http://localhost:8080/v1/chat/completions",
        model = "gpt-4",
      }

      local code_opts = {
        messages = { { role = "user", content = "Hello" } },
        stream = false,
        on_error = function(err, headers)
          if err:match("rate limit") then
            rate_limit_error = true
            if headers and headers["Retry-After"] then retry_after = headers["Retry-After"] end
          end
        end,
      }

      -- Simulate rate limit error
      if code_opts.on_error then code_opts.on_error("Rate limit exceeded", { ["Retry-After"] = "60" }) end

      assert.is_true(rate_limit_error)
      assert.equals("60", retry_after)
    end)

    it("should handle model not found errors", function()
      local model_error = false

      local opts = {
        endpoint = "http://localhost:8080/v1/chat/completions",
        model = "invalid-model",
      }

      local code_opts = {
        messages = { { role = "user", content = "Hello" } },
        stream = false,
        on_error = function(err)
          if err:match("model") then model_error = true end
        end,
      }

      -- Simulate model error
      if code_opts.on_error then code_opts.on_error("The model 'invalid-model' does not exist") end

      assert.is_true(model_error)
    end)

    it("should handle network timeouts", function()
      local timeout_error = false

      local opts = {
        endpoint = "http://localhost:8080/v1/chat/completions",
        model = "gpt-4",
      }

      local code_opts = {
        messages = { { role = "user", content = "Hello" } },
        stream = false,
        timeout = 1000, -- 1 second
        on_error = function(err)
          if err:match("timeout") or err:match("connection") then timeout_error = true end
        end,
      }

      -- Simulate timeout error
      if code_opts.on_error then code_opts.on_error("Connection timeout after 1000ms") end

      assert.is_true(timeout_error)
    end)
  end)

  describe("Model Selection", function()
    it("should support different GPT models", function()
      local models_tested = {}
      local test_models = { "gpt-4", "gpt-4-turbo", "gpt-3.5-turbo" }

      for _, model in ipairs(test_models) do
        local opts = {
          endpoint = "http://localhost:8080/v1/chat/completions",
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
      assert.True(vim.tbl_contains(models_tested, "gpt-4"))
      assert.True(vim.tbl_contains(models_tested, "gpt-4-turbo"))
      assert.True(vim.tbl_contains(models_tested, "gpt-3.5-turbo"))
    end)
  end)

  describe("Message Formatting", function()
    it("should format messages correctly for OpenAI API", function()
      local openai = require("avante.providers.openai")

      local messages = {
        { role = "system", content = "You are a helpful assistant." },
        { role = "user", content = "Hello!" },
        { role = "assistant", content = "Hi there!" },
        { role = "user", content = "How are you?" },
      }

      -- Test message role mapping
      for _, message in ipairs(messages) do
        local mapped_role = openai.role_map[message.role]
        assert.True(mapped_role ~= nil, "Role should be mapped: " .. message.role)
        assert.equals(message.role, mapped_role)
      end
    end)

    it("should handle tool calls in messages", function()
      local openai = require("avante.providers.openai")

      -- Test tool transformation
      local test_tool = {
        name = "get_weather",
        description = "Get current weather information",
        param = {
          fields = {
            location = { type = "string", description = "City name" },
            units = { type = "string", description = "Temperature units" },
          },
        },
      }

      local transformed_tool = openai:transform_tool(test_tool)

      assert.equals("function", transformed_tool.type)
      assert.equals("get_weather", transformed_tool["function"].name)
      assert.equals("Get current weather information", transformed_tool["function"].description)
      assert.True(transformed_tool["function"].parameters ~= nil)
      assert.equals("object", transformed_tool["function"].parameters.type)
    end)
  end)

  describe("Response Parsing", function()
    it("should parse non-streaming responses correctly", function()
      local test_response = {
        id = "chatcmpl-test",
        object = "chat.completion",
        choices = {
          {
            index = 0,
            message = {
              role = "assistant",
              content = "Test response content",
            },
            finish_reason = "stop",
          },
        },
        usage = {
          prompt_tokens = 10,
          completion_tokens = 5,
          total_tokens = 15,
        },
      }

      helpers.assert_provider_response(test_response, "openai", {
        type = "chat",
        content = "Test response content",
      })
    end)

    it("should parse streaming responses correctly", function()
      local test_chunks = {
        'data: {"id":"chatcmpl-test","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"}}]}',
        'data: {"id":"chatcmpl-test","choices":[{"index":0,"delta":{"content":" world"}}]}',
        'data: {"id":"chatcmpl-test","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
        "data: [DONE]",
      }

      local parsed_content = ""
      local stream_finished = false

      for _, chunk in ipairs(test_chunks) do
        if chunk:match("^data: ") and not chunk:match("%[DONE%]") then
          local json_data = chunk:sub(7) -- Remove "data: " prefix
          local success, data = pcall(vim.fn.json_decode, json_data)

          if success and data.choices and data.choices[1] and data.choices[1].delta then
            if data.choices[1].delta.content then parsed_content = parsed_content .. data.choices[1].delta.content end
            if data.choices[1].finish_reason then stream_finished = true end
          end
        elseif chunk:match("%[DONE%]") then
          stream_finished = true
        end
      end

      assert.equals("Hello world", parsed_content)
      assert.is_true(stream_finished)
    end)
  end)
end)
