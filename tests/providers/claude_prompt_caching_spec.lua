local Claude = require("avante.providers.claude")
local Config = require("avante.config")
local Utils = require("avante.utils")

describe("Claude provider prompt caching", function()
  before_each(function()
    Config.setup({
      prompt_caching = {
        enabled = true,
        providers = {
          claude = true,
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
      assert.is_true(Claude:is_static_content(message, 1))
    end)

    it("should identify first messages as static based on config", function()
      local message = { role = "user", content = "Hello" }
      assert.is_true(Claude:is_static_content(message, 1))
      assert.is_true(Claude:is_static_content(message, 2))
      assert.is_false(Claude:is_static_content(message, 3))
    end)

    it("should identify context-marked messages as static", function()
      local message = { role = "user", content = "Context", is_context = true }
      assert.is_true(Claude:is_static_content(message, 5))
    end)
  end)

  describe("count_tokens_before", function()
    it("should count tokens in system prompt", function()
      local messages = {}
      local system_prompt = "You are a helpful assistant"
      local count = Claude:count_tokens_before(messages, system_prompt, 0)
      assert.is_true(count > 0)
    end)

    it("should count tokens in messages with string content", function()
      local messages = {
        { role = "user", content = "Hello world" },
        { role = "assistant", content = "Hi there" },
      }
      local count = Claude:count_tokens_before(messages, "", 2)
      assert.is_true(count > 0)
    end)

    it("should count tokens in messages with table content", function()
      local messages = {
        {
          role = "user",
          content = {
            { type = "text", text = "Hello world" },
          },
        },
      }
      local count = Claude:count_tokens_before(messages, "", 1)
      assert.is_true(count > 0)
    end)

    it("should accumulate tokens from system prompt and messages", function()
      local messages = {
        { role = "user", content = "Message one" },
      }
      local system_prompt = "System prompt"
      local count = Claude:count_tokens_before(messages, system_prompt, 1)
      local system_count = Claude:count_tokens_before({}, system_prompt, 0)
      local message_count = Claude:count_tokens_before(messages, "", 1)
      assert.equals(system_count + message_count, count)
    end)
  end)

  describe("transform_anthropic_usage", function()
    it("should handle basic usage without caching", function()
      local usage = {
        input_tokens = 100,
        output_tokens = 50,
      }
      local result = Claude.transform_anthropic_usage(usage)
      assert.equals(100, result.prompt_tokens)
      assert.equals(50, result.completion_tokens)
      assert.equals(0, result.cache_hit_tokens)
      assert.equals(0, result.cache_write_tokens)
      assert.equals(0, result.cache_hit_rate)
    end)

    it("should handle usage with cache hits", function()
      local usage = {
        input_tokens = 100,
        output_tokens = 50,
        cache_read_input_tokens = 80,
        cache_creation_input_tokens = 0,
      }
      local result = Claude.transform_anthropic_usage(usage)
      assert.equals(100, result.prompt_tokens)
      -- When there are cache hits, completion_tokens includes cache_read_input_tokens + output_tokens
      assert.equals(130, result.completion_tokens)
      assert.equals(80, result.cache_hit_tokens)
      assert.equals(0, result.cache_write_tokens)
      assert.equals(0.8, result.cache_hit_rate)
    end)

    it("should handle usage with cache writes", function()
      local usage = {
        input_tokens = 100,
        output_tokens = 50,
        cache_read_input_tokens = 0,
        cache_creation_input_tokens = 100,
      }
      local result = Claude.transform_anthropic_usage(usage)
      assert.equals(200, result.prompt_tokens)
      assert.equals(50, result.completion_tokens)
      assert.equals(0, result.cache_hit_tokens)
      assert.equals(100, result.cache_write_tokens)
      assert.equals(0, result.cache_hit_rate)
    end)

    it("should return nil for nil usage", function()
      local result = Claude.transform_anthropic_usage(nil)
      assert.is_nil(result)
    end)
  end)

  describe("analyze_cache_performance", function()
    before_each(function()
      -- Clear cache stats
      Claude.cache_stats = {}
    end)

    it("should return message when no stats available", function()
      local result = Claude.analyze_cache_performance()
      assert.equals("No cache statistics available", result)
    end)

    it("should calculate average hit rate", function()
      Claude.cache_stats = {
        {
          timestamp = os.time(),
          cache_hit_tokens = 80,
          cache_write_tokens = 0,
          total_input_tokens = 100,
          cache_hit_rate = 0.8,
        },
        {
          timestamp = os.time(),
          cache_hit_tokens = 60,
          cache_write_tokens = 0,
          total_input_tokens = 100,
          cache_hit_rate = 0.6,
        },
      }
      local result = Claude.analyze_cache_performance()
      assert.equals(0.7, result.average_hit_rate)
      assert.equals(140, result.total_hit_tokens)
      assert.equals(0, result.total_write_tokens)
      assert.equals(200, result.total_input_tokens)
      assert.equals(2, result.sample_count)
    end)
  end)

  -- Note: parse_curl_args tests are skipped because they require complex provider setup
  -- including API key validation and other dependencies that are better tested in integration tests
end)

