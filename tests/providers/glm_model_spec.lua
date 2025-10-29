local Config = require("avante.config")

describe("GLM provider model update", function()
  before_each(function()
    -- Reset config to defaults
    Config.setup({})
  end)

  it("should use glm-4.6 as default model", function()
    local glm_provider = Config.providers.glm

    assert.is_not_nil(glm_provider, "GLM provider should exist")
    assert.are.equal("glm-4.6", glm_provider.model, "GLM model should be 4.6")
  end)

  it("should inherit from openai provider", function()
    local glm_provider = Config.providers.glm

    assert.is_not_nil(glm_provider.__inherited_from, "should have inheritance marker")
    assert.are.equal("openai", glm_provider.__inherited_from, "should inherit from openai")
  end)

  it("should have correct endpoint for GLM API", function()
    local glm_provider = Config.providers.glm

    assert.are.equal(
      "https://open.bigmodel.cn/api/coding/paas/v4",
      glm_provider.endpoint,
      "endpoint should be correct"
    )
  end)

  it("should use GLM_API_KEY for authentication", function()
    local glm_provider = Config.providers.glm

    assert.are.equal("GLM_API_KEY", glm_provider.api_key_name,
      "should use GLM_API_KEY environment variable")
  end)

  it("should allow user to override model version", function()
    Config.setup({
      providers = {
        glm = {
          model = "glm-4.5", -- User preference for older version
        },
      },
    })

    -- User override should be respected
    assert.are.equal("glm-4.5", Config.providers.glm.model,
      "should allow user to override model version")
  end)

  it("should maintain backward compatibility with glm-4.5 if needed", function()
    -- While the default is now 4.6, users should be able to use 4.5
    Config.setup({
      providers = {
        glm = {
          model = "glm-4.5",
        },
      },
    })

    local glm_provider = Config.providers.glm
    assert.are.equal("glm-4.5", glm_provider.model,
      "should support backward compatibility")
  end)
end)
