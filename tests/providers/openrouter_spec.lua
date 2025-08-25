local openrouter_provider = require("avante.providers.openrouter")

describe("openrouter_provider", function()
  describe("configuration", function()
    it("should inherit from openai provider", function()
      assert.equals("openai", openrouter_provider.__inherited_from)
    end)

    it("should have correct API key name", function()
      assert.equals("OPENROUTER_API_KEY", openrouter_provider.api_key_name)
    end)

    it("should have correct endpoint", function()
      assert.equals("https://api.openrouter.ai/api/v1", openrouter_provider.endpoint)
    end)

    it("should have correct default model", function()
      assert.equals("openai/gpt-4o-mini", openrouter_provider.model)
    end)

    it("should have correct timeout", function()
      assert.equals(30000, openrouter_provider.timeout)
    end)

    it("should have correct context window", function()
      assert.equals(128000, openrouter_provider.context_window)
    end)

    it("should have correct extra request body", function()
      assert.are.same({
        temperature = 0.75,
        max_tokens = 16384,
      }, openrouter_provider.extra_request_body)
    end)
  end)
end)