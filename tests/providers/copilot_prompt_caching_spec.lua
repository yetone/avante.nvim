local Config = require("avante.config")
-- Initialize Config with minimal setup before requiring providers
Config.setup({})
local Providers = require("avante.providers")

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
      -- Clear cached provider to force reload with new config
      Providers.copilot = nil
      assert.is_true(Providers.copilot:is_claude_model())
    end)

    it("should detect Claude models case-insensitively", function()
      Config.setup({
        providers = {
          copilot = {
            model = "CLAUDE-3.5-SONNET",
          },
        },
      })
      -- Clear cached provider to force reload with new config
      Providers.copilot = nil
      assert.is_true(Providers.copilot:is_claude_model())
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
        -- Clear cached provider to force reload with new config
        Providers.copilot = nil
        assert.is_true(Providers.copilot:is_claude_model(), "Failed to detect: " .. model)
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
        -- Clear cached provider to force reload with new config
        Providers.copilot = nil
        assert.is_false(Providers.copilot:is_claude_model(), "Incorrectly detected as Claude: " .. model)
      end
    end)
  end)

  describe("transform_copilot_claude_usage", function()
    it("should handle basic usage without caching", function()
      local usage = {
        input_tokens = 100,
        output_tokens = 50,
      }
      local result = Providers.copilot.transform_copilot_claude_usage(usage)
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
      local result = Providers.copilot.transform_copilot_claude_usage(usage)
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
      local result = Providers.copilot.transform_copilot_claude_usage(usage)
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
      local result = Providers.copilot.transform_copilot_claude_usage(usage)
      assert.equals(140, result.prompt_tokens)
      assert.equals(50, result.completion_tokens)
      assert.equals(60, result.cache_hit_tokens)
      assert.equals(40, result.cache_write_tokens)
      assert.equals(0.6, result.cache_hit_rate)
    end)

    it("should return nil for nil usage", function()
      local result = Providers.copilot.transform_copilot_claude_usage(nil)
      assert.is_nil(result)
    end)

    it("should record stats for visualization", function()
      -- Clear cached provider to ensure fresh instance
      Providers.copilot = nil

      -- Record the current count of stats before the call
      local initial_count = Providers.copilot.cache_stats and #Providers.copilot.cache_stats or 0

      local usage = {
        input_tokens = 100,
        output_tokens = 50,
        cache_read_input_tokens = 80,
        cache_creation_input_tokens = 0,
      }

      Providers.copilot.transform_copilot_claude_usage(usage)

      -- Verify that a new stat was added
      assert.is_not_nil(Providers.copilot.cache_stats)
      assert.equals(initial_count + 1, #Providers.copilot.cache_stats)

      -- Check the last recorded stat
      local last_stat = Providers.copilot.cache_stats[#Providers.copilot.cache_stats]
      assert.equals(80, last_stat.cache_hit_tokens)
      assert.equals(0, last_stat.cache_write_tokens)
      assert.equals(100, last_stat.total_input_tokens)
      assert.equals(0.8, last_stat.cache_hit_rate)
    end)
  end)

  -- Note: parse_curl_args tests are skipped because they require complex provider setup
  -- including authentication state and other dependencies that are better tested in integration tests
end)

