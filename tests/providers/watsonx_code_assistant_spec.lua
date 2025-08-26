local busted = require("plenary.busted")

busted.describe("watsonx_code_assistant provider", function()
  local watsonx_provider

  busted.before_each(function()
    -- Minimal setup without extensive mocking
    watsonx_provider = require("avante.providers.watsonx_code_assistant")
  end)

  busted.describe("basic configuration", function()
    busted.it("should have required properties", function()
      assert.is_not_nil(watsonx_provider.api_key_name)
      assert.equals("WCA_API_KEY", watsonx_provider.api_key_name)
      assert.is_not_nil(watsonx_provider.role_map)
      assert.equals("USER", watsonx_provider.role_map.user)
      assert.equals("ASSISTANT", watsonx_provider.role_map.assistant)
    end)

    busted.it("should disable streaming", function() assert.is_true(watsonx_provider:is_disable_stream()) end)

    busted.it("should have required functions", function()
      assert.is_function(watsonx_provider.parse_messages)
      assert.is_function(watsonx_provider.parse_response_without_stream)
      assert.is_function(watsonx_provider.parse_curl_args)
    end)
  end)

  busted.describe("parse_messages", function()
    busted.it("should parse messages with correct role mapping", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "You are a helpful assistant",
        messages = {
          { content = "Hello", role = "user" },
          { content = "Hi there", role = "assistant" },
        },
      }

      local result = watsonx_provider:parse_messages(opts)

      assert.is_table(result)
      assert.equals(3, #result) -- system + 2 messages
      assert.equals("SYSTEM", result[1].role)
      assert.equals("You are a helpful assistant", result[1].content)
      assert.equals("USER", result[2].role)
      assert.equals("Hello", result[2].content)
      assert.equals("ASSISTANT", result[3].role)
      assert.equals("Hi there", result[3].content)
    end)

    busted.it("should handle WCA_COMMAND system prompt", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "WCA_COMMAND",
        messages = {
          { content = "/document main.py", role = "user" },
        },
      }

      local result = watsonx_provider:parse_messages(opts)

      assert.is_table(result)
      assert.equals(1, #result) -- only user message, no system prompt
      assert.equals("USER", result[1].role)
      assert.equals("/document main.py", result[1].content)
    end)
  end)
end)
