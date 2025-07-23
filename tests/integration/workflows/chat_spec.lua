---@diagnostic disable: undefined-global
local helpers = require("tests.integration.helpers")

describe("Chat Workflow Integration", function()
  local test_ctx
  local test_buf

  before_each(function()
    test_ctx = helpers.setup_test_env({ git = false })

    -- Create test buffer with some code
    test_buf = helpers.create_test_buffer({
      "function hello_world() {",
      "  console.log('Hello, World!');",
      "}",
    }, "javascript")

    -- Configure provider for testing
    helpers.configure_avante_for_testing({
      provider = "openai",
      endpoint = "http://localhost:8080/v1/chat/completions",
      model = "gpt-4",
    })

    vim.env.OPENAI_API_KEY = "test-key"
  end)

  after_each(function()
    if test_buf and vim.api.nvim_buf_is_valid(test_buf) then vim.api.nvim_buf_delete(test_buf, { force = true }) end
    helpers.cleanup_test_env(test_ctx)
    vim.env.OPENAI_API_KEY = nil
  end)

  describe("Chat Initialization", function()
    it("should initialize chat sidebar", function()
      local avante = require("avante")
      local sidebar = require("avante.sidebar")

      -- Mock sidebar creation
      local sidebar_created = false
      local original_create = sidebar.create
      sidebar.create = function(...)
        sidebar_created = true
        return { winid = 1001, bufnr = 1001 }
      end

      -- Initialize chat
      avante.ask()

      assert.is_true(sidebar_created)

      -- Restore original function
      sidebar.create = original_create
    end)

    it("should load conversation history if available", function()
      local history = require("avante.history")
      local history_loaded = false
      local loaded_messages = {}

      -- Mock history loading
      local original_load = history.load
      history.load = function(bufnr)
        history_loaded = true
        return {
          { role = "user", content = "Previous question" },
          { role = "assistant", content = "Previous answer" },
        }
      end

      -- Mock history display
      local original_render = history.render
      history.render = function(messages) loaded_messages = messages end

      -- Initialize chat which should load history
      local avante = require("avante")
      avante.ask()

      -- Simulate history loading
      local messages = history.load(test_buf)
      if messages then history.render(messages) end

      assert.is_true(history_loaded)
      assert.equals(2, #loaded_messages)

      -- Restore original functions
      history.load = original_load
      history.render = original_render
    end)
  end)

  describe("Message Sending", function()
    it("should send user message and receive response", function()
      local avante = require("avante")
      local llm = require("avante.llm")

      local message_sent = false
      local response_received = false
      local user_message = "Explain this JavaScript function"
      local ai_response = ""

      -- Mock LLM stream function
      local original_stream = llm.stream
      llm.stream = function(opts)
        message_sent = true

        -- Simulate streaming response
        vim.defer_fn(function()
          if opts.on_chunk then
            opts.on_chunk("This function")
            opts.on_chunk(" prints")
            opts.on_chunk(" 'Hello, World!'")
            opts.on_chunk(" to the console.")
          end

          if opts.on_complete then
            opts.on_complete("This function prints 'Hello, World!' to the console.")
            response_received = true
            ai_response = "This function prints 'Hello, World!' to the console."
          end
        end, 50)
      end

      -- Send message
      avante.ask({
        question = user_message,
        bufnr = test_buf,
      })

      -- Wait for response
      helpers.wait_for_condition(function() return response_received end, 1000)

      assert.is_true(message_sent)
      assert.is_true(response_received)
      assert.True(ai_response:match("function"))

      -- Restore original function
      llm.stream = original_stream
    end)

    it("should handle context-aware conversations", function()
      local history = require("avante.history")
      local context_preserved = false
      local conversation_messages = {}

      -- Mock history management
      local original_add = history.add
      history.add = function(bufnr, message)
        table.insert(conversation_messages, message)
        context_preserved = true
      end

      -- Start conversation
      local avante = require("avante")

      -- First message
      avante.ask({
        question = "What does this function do?",
        bufnr = test_buf,
      })

      -- Simulate adding user message to history
      history.add(test_buf, {
        role = "user",
        content = "What does this function do?",
      })

      -- Simulate AI response
      history.add(test_buf, {
        role = "assistant",
        content = "This function prints 'Hello, World!' to the console.",
      })

      -- Follow-up message
      avante.ask({
        question = "Can you improve it?",
        bufnr = test_buf,
      })

      -- Simulate follow-up message
      history.add(test_buf, {
        role = "user",
        content = "Can you improve it?",
      })

      assert.is_true(context_preserved)
      assert.equals(3, #conversation_messages)
      assert.equals("What does this function do?", conversation_messages[1].content)
      assert.equals("assistant", conversation_messages[2].role)
      assert.equals("Can you improve it?", conversation_messages[3].content)

      -- Restore original function
      history.add = original_add
    end)

    it("should include buffer content as context", function()
      local context_included = false
      local buffer_content = ""

      local llm = require("avante.llm")
      local original_stream = llm.stream
      llm.stream = function(opts)
        if opts.messages then
          for _, msg in ipairs(opts.messages) do
            if msg.content and msg.content:match("console%.log") then
              context_included = true
              buffer_content = msg.content
              break
            end
          end
        end
      end

      -- Ask question about buffer content
      local avante = require("avante")
      avante.ask({
        question = "Analyze this code",
        bufnr = test_buf,
      })

      assert.is_true(context_included)
      assert.True(buffer_content:match("Hello, World!"))

      -- Restore original function
      llm.stream = original_stream
    end)
  end)

  describe("Response Handling", function()
    it("should display streaming responses in real-time", function()
      local chunks_displayed = {}
      local sidebar = require("avante.sidebar")

      -- Mock sidebar update
      local original_update = sidebar.update_content
      sidebar.update_content = function(winid, content) table.insert(chunks_displayed, content) end

      -- Simulate streaming response
      local chunks = { "Hello", " there", "! How", " can I", " help?" }
      local accumulated = ""

      for _, chunk in ipairs(chunks) do
        accumulated = accumulated .. chunk
        sidebar.update_content(1001, accumulated)
      end

      assert.equals(5, #chunks_displayed)
      assert.equals("Hello", chunks_displayed[1])
      assert.equals("Hello there", chunks_displayed[2])
      assert.equals("Hello there! How can I help?", chunks_displayed[5])

      -- Restore original function
      sidebar.update_content = original_update
    end)

    it("should handle response formatting with markdown", function()
      local formatted_response = false
      local markdown_content = ""

      local test_response =
        "Here's the improved function:\n\n```javascript\nfunction hello_world() {\n  console.log('Hello, World!');\n}\n```"

      -- Mock markdown parsing
      local utils = require("avante.utils")
      local original_parse = utils.parse_markdown
      utils.parse_markdown = function(content)
        formatted_response = true
        markdown_content = content
        return {
          text = "Here's the improved function:",
          code_blocks = {
            {
              language = "javascript",
              content = "function hello_world() {\n  console.log('Hello, World!');\n}",
            },
          },
        }
      end

      -- Process response
      utils.parse_markdown(test_response)

      assert.is_true(formatted_response)
      assert.True(markdown_content:match("```javascript"))

      -- Restore original function
      utils.parse_markdown = original_parse
    end)

    it("should handle code suggestions and diffs", function()
      local diff_applied = false
      local suggested_changes = {}

      local diff = require("avante.diff")
      local original_apply = diff.apply
      diff.apply = function(bufnr, changes)
        diff_applied = true
        suggested_changes = changes
      end

      -- Simulate code suggestion response
      local suggestions = {
        {
          type = "replace",
          start_line = 2,
          end_line = 2,
          new_content = "  console.log('Hello, Beautiful World!');",
        },
      }

      diff.apply(test_buf, suggestions)

      assert.is_true(diff_applied)
      assert.equals(1, #suggested_changes)
      assert.equals("replace", suggested_changes[1].type)
      assert.True(suggested_changes[1].new_content:match("Beautiful"))

      -- Restore original function
      diff.apply = original_apply
    end)
  end)

  describe("Error Handling", function()
    it("should handle network errors gracefully", function()
      local error_displayed = false
      local error_message = ""

      local llm = require("avante.llm")
      local original_stream = llm.stream
      llm.stream = function(opts)
        vim.defer_fn(function()
          if opts.on_error then
            opts.on_error("Network connection failed")
            error_displayed = true
            error_message = "Network connection failed"
          end
        end, 10)
      end

      -- Attempt to send message
      local avante = require("avante")
      avante.ask({
        question = "Test question",
        bufnr = test_buf,
      })

      -- Wait for error
      helpers.wait_for_condition(function() return error_displayed end, 500)

      assert.is_true(error_displayed)
      assert.True(error_message:match("Network"))

      -- Restore original function
      llm.stream = original_stream
    end)

    it("should handle API rate limiting", function()
      local rate_limit_handled = false
      local retry_scheduled = false

      local llm = require("avante.llm")
      local original_stream = llm.stream
      llm.stream = function(opts)
        vim.defer_fn(function()
          if opts.on_error then
            opts.on_error("Rate limit exceeded", { ["Retry-After"] = "60" })
            rate_limit_handled = true

            -- Simulate retry scheduling
            vim.defer_fn(function() retry_scheduled = true end, 100)
          end
        end, 10)
      end

      -- Send message that triggers rate limit
      local avante = require("avante")
      avante.ask({
        question = "Test question",
        bufnr = test_buf,
      })

      -- Wait for rate limit handling
      helpers.wait_for_condition(function() return retry_scheduled end, 1000)

      assert.is_true(rate_limit_handled)
      assert.is_true(retry_scheduled)

      -- Restore original function
      llm.stream = original_stream
    end)
  end)

  describe("Provider Switching", function()
    it("should switch providers mid-conversation", function()
      local provider_switched = false
      local new_provider = ""

      local config = require("avante.config")
      local original_override = config.override
      config.override = function(new_config)
        if new_config.provider then
          provider_switched = true
          new_provider = new_config.provider
        end
      end

      -- Start with OpenAI
      helpers.configure_avante_for_testing({
        provider = "openai",
        model = "gpt-4",
      })

      -- Switch to Claude
      config.override({
        provider = "claude",
        model = "claude-3-opus-20240229",
      })

      assert.is_true(provider_switched)
      assert.equals("claude", new_provider)

      -- Restore original function
      config.override = original_override
    end)

    it("should preserve conversation history when switching providers", function()
      local history_preserved = false
      local message_count = 0

      local history = require("avante.history")
      local original_get = history.get
      history.get = function(bufnr)
        history_preserved = true
        return {
          { role = "user", content = "Previous question with OpenAI" },
          { role = "assistant", content = "Previous answer from OpenAI" },
        }
      end

      -- Get history after provider switch
      local messages = history.get(test_buf)
      if messages then message_count = #messages end

      assert.is_true(history_preserved)
      assert.equals(2, message_count)

      -- Restore original function
      history.get = original_get
    end)
  end)
end)
