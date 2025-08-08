local azure_next_gen_provider = require("avante.providers.azure_next_gen")

describe("azure_next_gen_provider", function()
  describe("api key configuration", function()
    it(
      "should have correct api key name",
      function() assert.are.equal("AZURE_OPENAI_API_KEY", azure_next_gen_provider.api_key_name) end
    )
  end)

  describe("inheritance from openai provider", function()
    it("should inherit from openai provider methods", function()
      assert.is_function(azure_next_gen_provider.parse_messages)
      assert.is_function(azure_next_gen_provider.transform_tool)
      assert.is_function(azure_next_gen_provider.set_allowed_params)
    end)

    it(
      "should have parse_curl_args function",
      function() assert.is_function(azure_next_gen_provider.parse_curl_args) end
    )
  end)

  describe("parse_curl_args modifications", function()
    local mock_openai_result = {
      url = "https://api.openai.com/v1/chat/completions",
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer test-key",
      },
      body = {
        model = "gpt-4o",
        messages = {},
        stream = true,
      },
    }

    it("should modify openai request for azure compatibility", function()
      -- Mock the OpenAI provider's parse_curl_args
      local original_parse_curl_args = require("avante.providers.openai").parse_curl_args
      require("avante.providers.openai").parse_curl_args = function(self, prompt_opts)
        return vim.deepcopy(mock_openai_result)
      end

      -- Mock parse_api_key
      local provider = setmetatable({
        parse_api_key = function() return "test-azure-key" end,
      }, { __index = azure_next_gen_provider })

      local result = provider:parse_curl_args({})

      -- Should have Azure-specific modifications
      assert.are.equal("test-azure-key", result.headers["api-key"])
      assert.is_nil(result.headers["Authorization"])
      assert.is_true(result.url:match("api%-version=preview") ~= nil)

      -- Restore original function
      require("avante.providers.openai").parse_curl_args = original_parse_curl_args
    end)

    it("should use custom api-version if provided", function()
      -- Mock the OpenAI provider's parse_curl_args
      local original_parse_curl_args = require("avante.providers.openai").parse_curl_args
      require("avante.providers.openai").parse_curl_args = function(self, prompt_opts)
        return vim.deepcopy(mock_openai_result)
      end

      -- Mock parse_api_key
      local provider = setmetatable({
        parse_api_key = function() return "test-azure-key" end,
        api_version = "2024-02-15-preview",
      }, { __index = azure_next_gen_provider })

      local result = provider:parse_curl_args({})

      -- Should have Azure-specific modifications
      assert.is_true(result.url:match("api%-version=2024-02-15-preview") ~= nil)

      -- Restore original function
      require("avante.providers.openai").parse_curl_args = original_parse_curl_args
    end)
  end)
end)
