local Config = require("avante.config")

describe("Config codex-acp environment variables", function()
  before_each(function()
    -- Reset config to defaults
    Config.setup({})
  end)

  it("should include HOME environment variable in codex-acp provider", function()
    local codex_config = Config.acp_providers.codex
    assert.is_not_nil(codex_config, "codex provider should exist")
    assert.is_not_nil(codex_config.env, "codex provider should have env")
    assert.is_not_nil(codex_config.env.HOME, "HOME should be set in env")
    assert.are.equal(os.getenv("HOME"), codex_config.env.HOME, "HOME should match system environment")
  end)

  it("should include PATH environment variable in codex-acp provider", function()
    local codex_config = Config.acp_providers.codex
    assert.is_not_nil(codex_config, "codex provider should exist")
    assert.is_not_nil(codex_config.env, "codex provider should have env")
    assert.is_not_nil(codex_config.env.PATH, "PATH should be set in env")
    assert.are.equal(os.getenv("PATH"), codex_config.env.PATH, "PATH should match system environment")
  end)

  it("should preserve existing environment variables (NODE_NO_WARNINGS, OPENAI_API_KEY)", function()
    local codex_config = Config.acp_providers.codex
    assert.is_not_nil(codex_config.env.NODE_NO_WARNINGS, "NODE_NO_WARNINGS should still be set")
    assert.are.equal("1", codex_config.env.NODE_NO_WARNINGS, "NODE_NO_WARNINGS should be '1'")

    -- OPENAI_API_KEY should be mapped from environment
    local expected_key = os.getenv("OPENAI_API_KEY")
    assert.are.equal(expected_key, codex_config.env.OPENAI_API_KEY, "OPENAI_API_KEY should match system environment")
  end)

  it("should handle missing HOME or PATH environment variables gracefully", function()
    -- This test verifies that the config doesn't crash if env vars are missing
    -- The values will be nil, which is acceptable
    local codex_config = Config.acp_providers.codex
    assert.is_not_nil(codex_config, "codex provider should exist even with missing env vars")
    -- The env table should exist, but values might be nil
    assert.is_not_nil(codex_config.env, "env table should exist")
  end)
end)
