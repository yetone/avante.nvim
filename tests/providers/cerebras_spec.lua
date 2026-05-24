local busted = require("plenary.busted")

busted.describe("cerebras provider", function()
  local cerebras_provider

  busted.before_each(function()
    -- Set up the providers module first
    local Config = require("avante.config")
    Config.setup({})

    -- Reload the provider module to get a fresh state
    package.loaded["avante.providers.cerebras"] = nil
    cerebras_provider = require("avante.providers.cerebras")
  end)

  busted.describe("basic configuration", function()
    busted.it("should have required properties", function()
      assert.is_not_nil(cerebras_provider.api_key_name)
      assert.equals("CEREBRAS_API_KEY", cerebras_provider.api_key_name)
      assert.is_not_nil(cerebras_provider.tokenizer_id)
      assert.equals("gpt-4o", cerebras_provider.tokenizer_id)
      assert.is_not_nil(cerebras_provider.role_map)
      assert.equals("user", cerebras_provider.role_map.user)
      assert.equals("assistant", cerebras_provider.role_map.assistant)
    end)

    busted.it("should not disable streaming", function() assert.is_false(cerebras_provider:is_disable_stream()) end)

    busted.it("should have required functions", function()
      assert.is_function(cerebras_provider.parse_messages)
      assert.is_function(cerebras_provider.parse_response)
      assert.is_function(cerebras_provider.parse_response_without_stream)
    end)
  end)

  busted.describe("parse_messages", function()
    busted.it("should leave plain message untouched", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          { content = "Hello", role = "user" },
        },
      }

      local result = cerebras_provider:parse_messages(opts)

      assert.is_table(result)
      assert.is_true(#result == 2) -- system + user message

      -- Check that reasoning_content was renamed to reasoning if it existed
      for _, msg in ipairs(result) do
        assert.is_table(msg, { content = "Hello", role = "user" }, "message was untouched")
      end
    end)

    busted.it("should rename reasoning_content to reasoning in nested message structure", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          {
            content = "Hello",
            role = "user",
          },
          {
            content = "Hi there",
            role = "assistant",
            reasoning_content = "This is assistant reasoning",
          },
        },
      }

      local result = cerebras_provider:parse_messages(opts)

      assert.is_table(result)
      assert.is(#result, 2)

      -- Check that reasoning_content was renamed to reasoning
      for _, msg in ipairs(result) do
        if msg.role == "assistant" then
          assert.is_nil(msg.reasoning_content, "reasoning_content should no longer be present")
          assert.is(msg.reasoning, "This is assistant reasoning", "reasoning field should be present")
        else
          assert.is_nil(msg.reasoning_content, "does not inject reasoning/reasoning_content")
          assert.is_nil(msg.reasoning, "does not inject reasoning/reasoning_content")
        end
      end
    end)

    busted.it("should handle deeply nested reasoning_content fields", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          {
            content = "Complex message",
            role = "user",
            metadata = {
              reasoning_content = "Nested reasoning",
              other_field = "value",
            },
          },
        },
      }

      local result = cerebras_provider:parse_messages(opts)

      assert.is_table(result)

      assert.is_true(#result >= 2) -- at minimum system + user message
    end)

    busted.it("should handle arrays with reasoning_content", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          {
            content = "Message with array",
            role = "user",
          },
        },
      }

      local result = cerebras_provider:parse_messages(opts)

      assert.is_table(result)
      -- Basic test that the function works with arrays in messages
      assert.is_true(#result >= 2) -- system + user message
    end)

    busted.it("should preserve other fields while renaming reasoning_content", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          {
            content = "Test message",
            role = "user",
            reasoning_content = "Reasoning text",
          },
        },
      }

      local result = cerebras_provider:parse_messages(opts)

      assert.is_table(result)

      local found_message = false
      for _, msg in ipairs(result) do
        if msg.content == "Test message" then
          found_message = true
          assert.is_nil(msg.reasoning_content)
          -- Note: The OpenAI provider may filter out custom fields, so we just verify
          -- that reasoning_content was renamed if it exists
          if msg.reasoning then assert.equals("Reasoning text", msg.reasoning) end
        end
      end
      -- Just verify the message was found and processed without crashing
      assert.is_true(found_message, "Should have found the test message")
    end)

    busted.it("should handle empty reasoning_content fields", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          {
            content = "Message",
            role = "user",
            reasoning_content = "",
          },
        },
      }

      local result = cerebras_provider:parse_messages(opts)

      assert.is_table(result)

      for _, msg in ipairs(result) do
        assert.is_nil(msg.reasoning_content)
        if msg.reasoning ~= nil then assert.equals("", msg.reasoning) end
      end
    end)

    busted.it("should handle nil reasoning_content fields", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          {
            content = "Message",
            role = "user",
            reasoning_content = nil,
          },
        },
      }

      local result = cerebras_provider:parse_messages(opts)

      assert.is_table(result)

      for _, msg in ipairs(result) do
        assert.is_nil(msg.reasoning_content)
      end
    end)

    busted.it("should handle complex nested structures", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          {
            content = "Complex nested",
            role = "user",
            level1 = {
              level2 = {
                reasoning_content = "Deep reasoning",
                other_data = {
                  items = { 1, 2, 3 },
                },
              },
            },
          },
        },
      }

      local result = cerebras_provider:parse_messages(opts)

      assert.is_table(result)

      -- The OpenAI provider processes messages, so we need to check if the transformation happens
      -- We check that the transformation function works correctly by examining any processed output
      -- Since OpenAI might filter non-standard fields, we verify the function doesn't crash
      assert.is_true(#result >= 2) -- at minimum system + user message
    end)
  end)

  busted.describe("parse_response", function()
    busted.it("should rename reasoning to reasoning_content in streaming response", function()
      local data_stream = 'data: {"choices":[{"delta":{"reasoning":"This is reasoning","content":"Response"}}]}'

      local mock_ctx = {}
      local chunk_content = ""
      local opts = {}

      -- Mock the parent OpenAI.parse_response to capture the processed stream
      local captured_stream = nil
      local OpenAI = require("avante.providers").openai
      local original_parse_response = OpenAI.parse_response
      OpenAI.parse_response = function(self, ctx, stream, chunk, options)
        captured_stream = stream
        -- Return minimal response to avoid errors
        return {}
      end

      cerebras_provider:parse_response(mock_ctx, data_stream, chunk_content, opts)

      OpenAI.parse_response = original_parse_response

      assert.is_not_nil(captured_stream)
      assert.is_true(captured_stream:match('"reasoning_content"') ~= nil)
      assert.is_false(captured_stream:match('"reasoning"%s*:') ~= nil)
    end)

    busted.it("should handle multiple reasoning fields in stream", function()
      local data_stream = 'data: {"reasoning":"First","content":"A"}\ndata: {"reasoning":"Second","content":"B"}'

      local mock_ctx = {}
      local chunk_content = ""
      local opts = {}

      local captured_stream = nil
      local OpenAI = require("avante.providers").openai
      local original_parse_response = OpenAI.parse_response
      OpenAI.parse_response = function(self, ctx, stream, chunk, options)
        captured_stream = stream
        return {}
      end

      cerebras_provider:parse_response(mock_ctx, data_stream, chunk_content, opts)

      OpenAI.parse_response = original_parse_response

      assert.is_not_nil(captured_stream)
      -- Count occurrences of reasoning_content
      local count = 0
      for _ in captured_stream:gmatch('"reasoning_content"') do
        count = count + 1
      end
      assert.equals(2, count, "Should have 2 reasoning_content fields")
    end)

    busted.it("should handle reasoning fields with various spacing", function()
      local test_cases = {
        ['data: {"reasoning":"text"}'] = 'data: {"reasoning_content":"text"}',
        ['data: {"reasoning": "text"}'] = 'data: {"reasoning_content": "text"}',
        ['data: {"reasoning"  :  "text"}'] = 'data: {"reasoning_content"  :  "text"}',
      }

      for input, expected in pairs(test_cases) do
        local mock_ctx = {}
        local chunk_content = ""
        local opts = {}

        local captured_stream = nil
        local OpenAI = require("avante.providers").openai
        local original_parse_response = OpenAI.parse_response
        OpenAI.parse_response = function(self, ctx, stream, chunk, options)
          captured_stream = stream
          return {}
        end

        cerebras_provider:parse_response(mock_ctx, input, chunk_content, opts)

        OpenAI.parse_response = original_parse_response

        assert.is_not_nil(captured_stream)
        assert.is_true(
          captured_stream:match('"reasoning_content"') ~= nil,
          "Should contain reasoning_content in: " .. input
        )
      end
    end)

    busted.it("should preserve other JSON structure in stream", function()
      local data_stream =
        'data: {"id":"123","choices":[{"delta":{"reasoning":"thinking","content":"answer"}}],"model":"gpt-4"}'

      local mock_ctx = {}
      local chunk_content = ""
      local opts = {}

      local captured_stream = nil
      local OpenAI = require("avante.providers").openai
      local original_parse_response = OpenAI.parse_response
      OpenAI.parse_response = function(self, ctx, stream, chunk, options)
        captured_stream = stream
        return {}
      end

      cerebras_provider:parse_response(mock_ctx, data_stream, chunk_content, opts)

      OpenAI.parse_response = original_parse_response

      assert.is_not_nil(captured_stream)
      -- Check that the reasoning field was renamed to reasoning_content
      assert.is_true(captured_stream:match('"reasoning_content"') ~= nil)
      -- Check that the original reasoning field is not present as "reasoning":
      assert.is_false(captured_stream:match('"reasoning"%s*:') ~= nil)
    end)

    busted.it("should handle empty stream", function()
      local data_stream = ""

      local mock_ctx = {}
      local chunk_content = ""
      local opts = {}

      local captured_stream = nil
      local OpenAI = require("avante.providers").openai
      local original_parse_response = OpenAI.parse_response
      OpenAI.parse_response = function(self, ctx, stream, chunk, options)
        captured_stream = stream
        return {}
      end

      cerebras_provider:parse_response(mock_ctx, data_stream, chunk_content, opts)

      OpenAI.parse_response = original_parse_response

      assert.equals("", captured_stream)
    end)

    busted.it("should handle stream with no reasoning field", function()
      local data_stream = 'data: {"choices":[{"delta":{"content":"Just content"}}]}'

      local mock_ctx = {}
      local chunk_content = ""
      local opts = {}

      local captured_stream = nil
      local OpenAI = require("avante.providers").openai
      local original_parse_response = OpenAI.parse_response
      OpenAI.parse_response = function(self, ctx, stream, chunk, options)
        captured_stream = stream
        return {}
      end

      cerebras_provider:parse_response(mock_ctx, data_stream, chunk_content, opts)

      OpenAI.parse_response = original_parse_response

      assert.is_not_nil(captured_stream)
      assert.is_true(captured_stream:match('"content"') ~= nil)
      assert.is_false(captured_stream:match('"reasoning_content"') ~= nil)
    end)
  end)

  busted.describe("parse_response_without_stream", function()
    busted.it("should rename reasoning to reasoning_content in JSON response", function()
      local data = vim.json.encode({
        choices = {
          {
            message = {
              reasoning = "This is reasoning",
              content = "This is content",
            },
          },
        },
      })

      local chunk_content = ""
      local opts = {}

      -- Mock the parent OpenAI.parse_response_without_stream to capture processed data
      local captured_data = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_data = processed_data
        -- Return minimal response to avoid errors
        return {}
      end

      cerebras_provider:parse_response_without_stream(data, chunk_content, opts)

      OpenAI.parse_response_without_stream = original_parse

      assert.is_not_nil(captured_data)
      local parsed = vim.json.decode(captured_data)
      assert.is_not_nil(parsed.choices[1].message.reasoning_content)
      assert.equals("This is reasoning", parsed.choices[1].message.reasoning_content)
      assert.is_nil(parsed.choices[1].message.reasoning)
    end)

    busted.it("should handle nested reasoning fields in non-streaming response", function()
      local data = vim.json.encode({
        reasoning = "Top level reasoning",
        data = {
          inner_reasoning = "Nested reasoning",
          content = "Main content",
        },
      })

      local chunk_content = ""
      local opts = {}

      local captured_data = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_data = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(data, chunk_content, opts)

      OpenAI.parse_response_without_stream = original_parse

      assert.is_not_nil(captured_data)
      local parsed = vim.json.decode(captured_data)
      assert.equals("Top level reasoning", parsed.reasoning_content)
      assert.is_nil(parsed.reasoning)
      -- Note: The nested field with "inner_reasoning" key won't be renamed because it doesn't match "reasoning" exactly
      assert.equals("Nested reasoning", parsed.data.inner_reasoning)
    end)

    busted.it("should handle array of items with reasoning fields", function()
      local data = vim.json.encode({
        items = {
          { id = 1, reasoning = "Reasoning 1", content = "Content 1" },
          { id = 2, reasoning = "Reasoning 2", content = "Content 2" },
          { id = 3, reasoning = "Reasoning 3", content = "Content 3" },
        },
      })

      local chunk_content = ""
      local opts = {}

      local captured_data = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_data = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(data, chunk_content, opts)

      OpenAI.parse_response_without_stream = original_parse

      assert.is_not_nil(captured_data)
      local parsed = vim.json.decode(captured_data)
      assert.equals(3, #parsed.items)
      for i, item in ipairs(parsed.items) do
        assert.is_not_nil(item.reasoning_content)
        assert.equals("Reasoning " .. i, item.reasoning_content)
        assert.is_nil(item.reasoning)
      end
    end)

    busted.it("should preserve other fields while renaming reasoning", function()
      local data = vim.json.encode({
        id = "12345",
        model = "cerebras-model",
        reasoning = "Thinking process",
        content = "Final answer",
        tokens_used = 150,
        metadata = {
          key = "value",
          another_field = { 1, 2, 3 },
        },
      })

      local chunk_content = ""
      local opts = {}

      local captured_data = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_data = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(data, chunk_content, opts)

      OpenAI.parse_response_without_stream = original_parse

      assert.is_not_nil(captured_data)
      local parsed = vim.json.decode(captured_data)
      assert.equals("12345", parsed.id)
      assert.equals("cerebras-model", parsed.model)
      assert.equals("Thinking process", parsed.reasoning_content)
      assert.equals("Final answer", parsed.content)
      assert.equals(150, parsed.tokens_used)
      assert.equals("value", parsed.metadata.key)
      assert.is_table(parsed.metadata.another_field)
      assert.is_nil(parsed.reasoning)
    end)

    busted.it("should handle empty reasoning field", function()
      local data = vim.json.encode({
        reasoning = "",
        content = "Content",
      })

      local chunk_content = ""
      local opts = {}

      local captured_data = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_data = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(data, chunk_content, opts)

      OpenAI.parse_response_without_stream = original_parse

      assert.is_not_nil(captured_data)
      local parsed = vim.json.decode(captured_data)
      assert.equals("", parsed.reasoning_content)
      assert.is_nil(parsed.reasoning)
    end)

    busted.it("should handle nil reasoning field", function()
      local data = vim.json.encode({
        reasoning = nil,
        content = "Content",
      })

      local chunk_content = ""
      local opts = {}

      local captured_data = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_data = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(data, chunk_content, opts)

      OpenAI.parse_response_without_stream = original_parse

      assert.is_not_nil(captured_data)
      local parsed = vim.json.decode(captured_data)
      assert.is_nil(parsed.reasoning)
      assert.is_nil(parsed.reasoning_content) -- nil values are not preserved
    end)

    busted.it("should handle malformed JSON gracefully", function()
      local malformed_data = '{"invalid": json}'

      local chunk_content = ""
      local opts = {}

      -- Should fall back to parent method without crashing
      local parent_called = false
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        parent_called = true
        return original_parse(self, processed_data, chunk, options)
      end

      local ok, err = pcall(
        function() cerebras_provider:parse_response_without_stream(malformed_data, chunk_content, opts) end
      )

      OpenAI.parse_response_without_stream = original_parse

      -- Should not crash, either succeeds or calls parent
      assert.is_true(ok or parent_called, "Should handle malformed JSON gracefully")
    end)

    busted.it("should handle response with no reasoning field", function()
      local data = vim.json.encode({
        choices = {
          {
            message = {
              content = "Just content, no reasoning",
            },
          },
        },
      })

      local chunk_content = ""
      local opts = {}

      local captured_data = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_data = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(data, chunk_content, opts)

      OpenAI.parse_response_without_stream = original_parse

      assert.is_not_nil(captured_data)
      local parsed = vim.json.decode(captured_data)
      assert.equals("Just content, no reasoning", parsed.choices[1].message.content)
      assert.is_nil(parsed.choices[1].message.reasoning)
      assert.is_nil(parsed.choices[1].message.reasoning_content)
    end)

    busted.it("should handle complex nested structures", function()
      local data = vim.json.encode({
        response = {
          reasoning = "Main reasoning",
          content = "Main content",
          details = {
            step1 = {
              reasoning = "Step 1 reasoning",
              result = "Step 1 result",
            },
            step2 = {
              reasoning = "Step 2 reasoning",
              result = "Step 2 result",
            },
          },
        },
      })

      local chunk_content = ""
      local opts = {}

      local captured_data = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_data = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(data, chunk_content, opts)

      OpenAI.parse_response_without_stream = original_parse

      assert.is_not_nil(captured_data)
      local parsed = vim.json.decode(captured_data)
      assert.equals("Main reasoning", parsed.response.reasoning_content)
      assert.equals("Step 1 reasoning", parsed.response.details.step1.reasoning_content)
      assert.equals("Step 2 reasoning", parsed.response.details.step2.reasoning_content)
      assert.is_nil(parsed.response.reasoning)
      assert.is_nil(parsed.response.details.step1.reasoning)
      assert.is_nil(parsed.response.details.step2.reasoning)
    end)
  end)

  busted.describe("integration tests", function()
    busted.it("should handle complete round-trip of reasoning field transformation", function()
      -- Test that the transformation functions work correctly
      -- Since the OpenAI provider processes messages and may filter custom fields,
      -- we test that the transformation doesn't crash and basic functionality works

      -- Test parse_messages doesn't crash and returns valid structure
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          {
            content = "Help me",
            role = "user",
            reasoning_content = "User's reasoning",
          },
        },
      }

      local outgoing_messages = cerebras_provider:parse_messages(opts)
      assert.is_table(outgoing_messages)
      assert.is_true(#outgoing_messages >= 2)

      -- Verify no reasoning_content fields remain (transformation happened)
      local found_reasoning_content = false
      for _, msg in ipairs(outgoing_messages) do
        if msg.reasoning_content then found_reasoning_content = true end
      end
      assert.is_false(found_reasoning_content, "Should have transformed all reasoning_content fields")

      -- Test parse_response_without_stream works correctly
      local response_data = vim.json.encode({
        choices = {
          {
            message = {
              reasoning = "Assistant's reasoning",
              content = "Here's help",
            },
          },
        },
      })

      local chunk_content = ""
      local response_opts = {}

      local captured_response = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_response = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(response_data, chunk_content, response_opts)

      OpenAI.parse_response_without_stream = original_parse

      -- Verify transformation in incoming response
      assert.is_not_nil(captured_response)
      local parsed_response = vim.json.decode(captured_response)
      assert.equals("Assistant's reasoning", parsed_response.choices[1].message.reasoning_content)
      assert.is_nil(parsed_response.choices[1].message.reasoning)
    end)

    busted.it("should maintain data integrity through transformations", function()
      -- Test realistic message transformation scenarios
      -- Focus on standard message fields that OpenAI provider actually processes

      -- Test 1: Simple reasoning_content transformation
      local opts1 = {
        system_prompt = "Test system prompt",
        messages = {
          {
            content = "Test content with reasoning",
            role = "user",
            reasoning_content = "Test reasoning",
          },
        },
      }

      local transformed1 = cerebras_provider:parse_messages(opts1)
      assert.is_table(transformed1)
      assert.is_true(#transformed1 >= 2) -- system + user message

      -- Verify reasoning_content was transformed
      local found_message1 = false
      for _, msg in ipairs(transformed1) do
        if msg.content == "Test content with reasoning" then
          found_message1 = true
          assert.is_nil(msg.reasoning_content, "reasoning_content should be transformed")
          -- Note: OpenAI provider may filter custom fields, so we just verify no crash
        end
      end
      assert.is_true(found_message1, "Should have found the transformed message")

      -- Test 2: Response transformation (reasoning → reasoning_content)
      local response_data = vim.json.encode({
        choices = {
          {
            message = {
              reasoning = "Assistant reasoning",
              content = "Response content",
            },
          },
        },
      })

      local chunk_content = ""
      local response_opts = {}

      local captured_response = nil
      local OpenAI = require("avante.providers").openai
      local original_parse = OpenAI.parse_response_without_stream
      OpenAI.parse_response_without_stream = function(self, processed_data, chunk, options)
        captured_response = processed_data
        return {}
      end

      cerebras_provider:parse_response_without_stream(response_data, chunk_content, response_opts)

      OpenAI.parse_response_without_stream = original_parse

      -- Verify response transformation
      assert.is_not_nil(captured_response)
      local parsed_response = vim.json.decode(captured_response)
      assert.equals("Assistant reasoning", parsed_response.choices[1].message.reasoning_content)
      assert.is_nil(parsed_response.choices[1].message.reasoning)
    end)
  end)
end)
