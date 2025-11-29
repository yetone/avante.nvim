local BedrockClaude = require("avante.providers.bedrock.claude")
local Config = require("avante.config")
local Utils = require("avante.utils")

describe("Bedrock Claude provider prompt caching", function()
  before_each(function()
    Config.setup({
      prompt_caching = {
        enabled = true,
        providers = {
          bedrock = true,
        },
        strategy = "simplified",
        static_message_count = 2,
        min_tokens_threshold = {
          ["claude-3-5-haiku"] = 2048,
          ["claude-3-7-sonnet"] = 1024,
          default = 1024,
        },
        debug = false,
      },
    })
  end)

  describe("is_static_content", function()
    it("should identify system messages as static", function()
      local message = { role = "system", content = "You are a helpful assistant" }
      assert.is_true(BedrockClaude:is_static_content(message, 1))
    end)

    it("should identify first messages as static based on config", function()
      local message = { role = "user", content = "Hello" }
      assert.is_true(BedrockClaude:is_static_content(message, 1))
      assert.is_true(BedrockClaude:is_static_content(message, 2))
      assert.is_false(BedrockClaude:is_static_content(message, 3))
    end)
  end)

  describe("count_tokens_before", function()
    it("should count tokens in system prompt string", function()
      local messages = {}
      local system_prompt = "You are a helpful assistant"
      local count = BedrockClaude:count_tokens_before(messages, system_prompt, 0)
      assert.is_true(count > 0)
    end)

    it("should count tokens in system prompt table", function()
      local messages = {}
      local system_prompt = {
        { type = "text", text = "You are a helpful assistant" },
      }
      local count = BedrockClaude:count_tokens_before(messages, system_prompt, 0)
      assert.is_true(count > 0)
    end)

    it("should count tokens in messages", function()
      local messages = {
        {
          role = "user",
          content = {
            { type = "text", text = "Hello world" },
          },
        },
      }
      local count = BedrockClaude:count_tokens_before(messages, "", 1)
      assert.is_true(count > 0)
    end)

    it("should accumulate tokens correctly", function()
      local messages = {
        {
          role = "user",
          content = {
            { type = "text", text = "Message one" },
          },
        },
      }
      local system_prompt = "System prompt"
      local count = BedrockClaude:count_tokens_before(messages, system_prompt, 1)
      local system_count = BedrockClaude:count_tokens_before({}, system_prompt, 0)
      assert.is_true(count >= system_count)
    end)
  end)

  -- Note: build_bedrock_payload tests are skipped because they require complex provider setup
  -- including message parsing and other dependencies that are better tested in integration tests
end)

