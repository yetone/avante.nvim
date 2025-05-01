local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("Providers", function()
  local Providers
  local Config_mock
  local Utils_mock
  local Environment

  before_each(function()
    Providers = require("avante.providers")
    Environment = require("avante.utils.environment")

    Config_mock = mock(require("avante.config"), true)
    Utils_mock = mock(require("avante.utils"), true)

    Environment.cache = {}
  end)

  after_each(function()
    package.loaded["avante.providers"] = nil
    package.loaded["avante.utils.environment"] = nil
    mock.revert(Config_mock)
    mock.revert(Utils_mock)
  end)

  describe("API key caching and expiry", function()
    it("should cache API key values", function()
      local provider = {
        api_key_name = "TEST_API_KEY",
        reevaluate_api_key_after = nil, -- No expiry
      }

      stub(Utils_mock.environment, "parse", function(key)
        if key == "TEST_API_KEY" then return "test-api-key-value" end
      end)

      -- First call should get from environment
      local value1 = Providers.env.parse_envvar(provider)
      assert.equals("test-api-key-value", value1)
      assert.spy(Utils_mock.environment.parse).was_called(1)

      -- Second call should get from cache
      local value2 = Providers.env.parse_envvar(provider)
      assert.equals("test-api-key-value", value2)
      assert.spy(Utils_mock.environment.parse).was_called(1) -- Should not call parse again

      Utils_mock.environment.parse:revert()
    end)

    it("should handle API key caching and expiry lifecycle", function()
      local provider = {
        api_key_name = "TEST_API_KEY",
        reevaluate_api_key_after = 1, -- 1 second expiry
      }

      local current_time = 1000
      stub(os, "time", function() return current_time end)

      stub(Utils_mock.environment, "parse", function(key)
        if key == "TEST_API_KEY" then return "test-api-key-value" end
      end)

      -- Initial fetch should get from environment and cache
      local value1 = Providers.env.parse_envvar(provider)
      assert.equals("test-api-key-value", value1)
      assert.spy(Utils_mock.environment.parse).was_called(1)

      -- Verify initial cache state
      assert.equals("test-api-key-value", Providers.env.cache["TEST_API_KEY"].value)
      assert.equals(current_time + 1, Providers.env.cache["TEST_API_KEY"].expires_at)

      -- Immediate second call should use cache
      local value2 = Providers.env.parse_envvar(provider)
      assert.equals("test-api-key-value", value2)
      assert.spy(Utils_mock.environment.parse).was_called(1) -- No new environment check

      -- Simulate time passing beyond expiry
      current_time = current_time + 2 -- 2 seconds later

      -- Call after expiry should force new environment check
      local value3 = Providers.env.parse_envvar(provider)
      assert.equals("test-api-key-value", value3)
      assert.spy(Utils_mock.environment.parse).was_called(2) -- New environment check

      -- Verify cache was updated with new expiry time
      assert.equals("test-api-key-value", Providers.env.cache["TEST_API_KEY"].value)
      assert.equals(current_time + 1, Providers.env.cache["TEST_API_KEY"].expires_at)

      Utils_mock.environment.parse:revert()
      os.time:revert()
    end)
  end)
end)
