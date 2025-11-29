local Copilot = require("avante.providers.copilot")
local Config = require("avante.config")

describe("Copilot provider prompt caching", function()
  before_each(function()
    Config.setup({
      prompt_caching = {
        enabled = true,
        providers = {
          copilot = true,
        },
        strategy = "simplified",
        static_message_count = 2,
        min_tokens_threshold = {
          default = 1024,
        },
        debug = false,
      },
    })
  end)

  describe("is_claude_model", function()
    it("should detect Claude models", function()
      Config.setup({
        providers = {
          copilot = {
            model = "claude-3.5-sonnet",
          },
        },
      })
      assert.is_true(Copilot:is_claude_model())
    end)

    it("should detect Claude models case-insensitively", function()
      Config.setup({
        providers = {
          copilot = {
            model = "CLAUDE-3.5-SONNET",
          },
        },
      })
      assert.is_true(Copilot:is_claude_model())
    end)

    it("should detect various Claude model variants", function()
      local claude_models = {
        "claude-3-opus",
        "claude-3-sonnet",
        "claude-3-haiku",
        "claude-3.5-sonnet",
        "claude-2",
        "claude-instant",
      }

      for _, model in ipairs(claude_models) do
        Config.setup({
          providers = {
            copilot = {
              model = model,
            },
          },
        })
        assert.is_true(Copilot:is_claude_model(), "Failed to detect: " .. model)
      end
    end)

    it("should not detect non-Claude models", function()
      local non_claude_models = {
        "gpt-4",
        "gpt-3.5-turbo",
        "o1-preview",
        "gemini-pro",
      }

      for _, model in ipairs(non_claude_models) do
        Config.setup({
          providers = {
            copilot = {
              model = model,
            },
          },
        })
        assert.is_false(Copilot:is_claude_model(), "Incorrectly detected as Claude: " .. model)
      end
    end)
  end)

  describe("transform_copilot_claude_usage", function()
    it("should handle basic usage without caching", function()
      local usage = {
        input_tokens = 100,
        output_tokens = 50,
      }
      local result = Copilot.transform_copilot_claude_usage(usage)
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
      local result = Copilot.transform_copilot_claude_usage(usage)
      assert.equals(100, result.prompt_tokens)
      assert.equals(50, result.completion_tokens)
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
      local result = Copilot.transform_copilot_claude_usage(usage)
      assert.equals(200, result.prompt_tokens)
      assert.equals(50, result.completion_tokens)
      assert.equals(0, result.cache_hit_tokens)
      assert.equals(100, result.cache_write_tokens)
      assert.equals(0, result.cache_hit_rate)
    end)

    it("should handle usage with both cache hits and writes", function()
      local usage = {
        input_tokens = 100,
        output_tokens = 50,
        cache_read_input_tokens = 60,
        cache_creation_input_tokens = 40,
      }
      local result = Copilot.transform_copilot_claude_usage(usage)
      assert.equals(140, result.prompt_tokens)
      assert.equals(50, result.completion_tokens)
      assert.equals(60, result.cache_hit_tokens)
      assert.equals(40, result.cache_write_tokens)
      assert.equals(0.6, result.cache_hit_rate)
    end)

    it("should return nil for nil usage", function()
      local result = Copilot.transform_copilot_claude_usage(nil)
      assert.is_nil(result)
    end)

    it("should record stats for visualization", function()
      -- Clear stats
      Copilot.cache_stats = {}

      local usage = {
        input_tokens = 100,
        output_tokens = 50,
        cache_read_input_tokens = 80,
        cache_creation_input_tokens = 0,
      }

      Copilot.transform_copilot_claude_usage(usage)

      assert.equals(1, #Copilot.cache_stats)
      assert.equals(80, Copilot.cache_stats[1].cache_hit_tokens)
      assert.equals(0, Copilot.cache_stats[1].cache_write_tokens)
      assert.equals(100, Copilot.cache_stats[1].total_input_tokens)
      assert.equals(0.8, Copilot.cache_stats[1].cache_hit_rate)
    end)
  end)

  -- Note: parse_curl_args tests are skipped because they require complex provider setup
  -- including authentication state and other dependencies that are better tested in integration tests
end)

