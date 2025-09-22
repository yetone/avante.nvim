local Config = require("avante.config")

describe("openrouter_provider", function()
  describe("configuration", function()
    it("should inherit from openai provider", function()
      assert.equals("openai", Config.defaults.providers.openrouter.__inherited_from)
    end)

    it("should have correct API key name", function()
      assert.equals("OPENROUTER_API_KEY", Config.defaults.providers.openrouter.api_key_name)
    end)

    it("should have correct endpoint", function()
      assert.equals("https://api.openrouter.ai/api/v1", Config.defaults.providers.openrouter.endpoint)
    end)

    it("should have correct default model", function()
      assert.equals("openai/gpt-4o-mini", Config.defaults.providers.openrouter.model)
    end)

    it("should have correct timeout", function()
      assert.equals(30000, Config.defaults.providers.openrouter.timeout)
    end)

    it("should have correct context window", function()
      assert.equals(128000, Config.defaults.providers.openrouter.context_window)
    end)

    it("should have correct extra request body", function()
      assert.are.same({
        temperature = 0.75,
        max_tokens = 4096,
      }, Config.defaults.providers.openrouter.extra_request_body)
    end)
  end)
end)