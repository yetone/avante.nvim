local Input = require("avante.ui.input")

describe("Input", function()
  local original_input

  before_each(function()
    original_input = vim.ui.input
  end)

  after_each(function()
    vim.ui.input = original_input
  end)

  it("uses vim.ui.input for the native provider", function()
    local captured_opts
    local captured_on_submit
    local submitted

    vim.ui.input = function(opts, on_submit)
      captured_opts = opts
      captured_on_submit = on_submit
    end

    local input = Input:new({
      provider = "native",
      title = "Model name",
      default = "claude",
      completion = "file",
      on_submit = function(result) submitted = result end,
    })

    input:open()

    assert.are.same({
      prompt = "Model name",
      default = "claude",
      completion = "file",
    }, captured_opts)
    assert.is_function(captured_on_submit)

    captured_on_submit("openai")
    assert.are.same("openai", submitted)
  end)
end)
