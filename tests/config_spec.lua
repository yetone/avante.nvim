describe("config", function()
  local Config
  local previous_avante

  before_each(function()
    previous_avante = vim.g.avante
    package.loaded["avante.config"] = nil
    Config = require("avante.config")
  end)

  after_each(function()
    vim.g.avante = previous_avante
    package.loaded["avante.config"] = nil
  end)

  it("loads setup options from vim.g.avante", function()
    vim.g.avante = {
      provider = "openai",
      behaviour = {
        auto_suggestions = true,
      },
    }

    Config.setup({})

    assert.are.same("openai", Config.provider)
    assert.is_true(Config.behaviour.auto_suggestions)
  end)

  it("lets explicit setup options override vim.g.avante", function()
    vim.g.avante = {
      provider = "openai",
      behaviour = {
        auto_suggestions = true,
      },
    }

    Config.setup({
      provider = "claude",
      behaviour = {
        auto_suggestions = false,
      },
    })

    assert.are.same("claude", Config.provider)
    assert.is_false(Config.behaviour.auto_suggestions)
  end)
end)
