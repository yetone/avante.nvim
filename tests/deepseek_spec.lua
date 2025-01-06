local deepseek = require("avante.providers.deepseek")
local Config = require("avante.config")

-- Mock Utils and other dependencies
local mock = {
  Utils = {
    error = function(msg) print("ERROR: " .. msg) end,
    url_join = function(base, path) return base .. path end,
    debug = function(...) print(...) end,
  },
}

-- Test helper function
local function assert_contains(str, pattern)
  assert(str, "Expected string but got nil")
  assert(pattern, "Expected pattern but got nil")
  assert(string.match(str, pattern), string.format("Expected '%s' to contain '%s'", str, pattern))
end

describe("DeepSeek Provider", function()
  -- Store original Utils at top level
  local original_utils = require("avante.utils")
  local errors = {}

  before_each(function()
    errors = {} -- Clear errors array

    -- Create hybrid mock that preserves original functions
    package.loaded["avante.utils"] = vim.tbl_extend("force", original_utils, {
      -- Override only the functions we need to test
      error = function(msg, opts)
        table.insert(errors, {
          msg = msg,
          opts = opts or {}, -- Ensure opts is never nil
        })
        print("Captured error:", msg, vim.inspect(opts)) -- Debug print
      end,
      debug = function(...)
        -- Keep original debug but add our test tracking
        print("Debug:", ...)
      end,
    })
  end)

  after_each(function()
    -- Restore original Utils
    package.loaded["avante.utils"] = original_utils
  end)

  -- Mock response data
  local mock_chat_response = [[
    {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}
  ]]

  local mock_coder_response = [[
    {"choices":[{"delta":{"content":"def hello():"},"finish_reason":null}]}
  ]]

  -- Test basic configuration
  it("should load with correct defaults", function()
    assert.equals(deepseek.api_key_name, "DEEPSEEK_API_KEY")
    assert.equals(type(deepseek.parse_messages), "function")
  end)

  -- Test model switching
  it("should handle model switching correctly", function()
    local test_cases = {
      {
        model = "deepseek-chat-v3",
        expected = "deepseek-chat-v3",
      },
      {
        model = "deepseek-coder-v3",
        expected = "deepseek-coder-v3",
      },
    }

    for _, case in ipairs(test_cases) do
      local args = deepseek.parse_curl_args({
        parse_api_key = function() return "test_key" end,
      }, {
        system_prompt = "test",
        messages = {},
        model = case.model,
      })
      assert.equals(args.body.model, case.expected)
    end
  end)

  -- Test response parsing
  it("should parse streaming responses correctly", function()
    local received_chunks = {}
    local opts = {
      on_chunk = function(chunk) table.insert(received_chunks, chunk) end,
      on_complete = function() end,
    }

    -- Test chat response
    deepseek.parse_response(mock_chat_response, nil, opts)
    assert.equals(received_chunks[1], "Hello")

    -- Test coder response
    received_chunks = {}
    deepseek.parse_response(mock_coder_response, nil, opts)
    assert.equals(received_chunks[1], "def hello():")
  end)

  -- Test error handling
  it("should handle errors correctly", function()
    deepseek.on_error({
      status = 401,
      body = [[{"error":{"message":"Invalid API key","code":401}}]],
    })

    assert(#errors > 0, "Expected error message to be captured")
    assert(errors[1].opts.once, "Expected error to have once=true option")
    assert(errors[1].opts.title == "Avante", "Expected error to have Avante title")
    assert_contains(errors[1].msg, "Authentication")
  end)

  -- Test dynamic model switching based on content
  it("should switch models based on content context", function()
    local test_cases = {
      {
        content = "What is the weather like?",
        expected_model = "deepseek-chat",
      },
      {
        content = "function calculateSum(a, b) {\n  return a + b;\n}",
        expected_model = "deepseek-coder",
      },
      {
        content = "class MyClass:\n    def __init__(self):\n        pass",
        expected_model = "deepseek-coder",
      },
      {
        content = "Tell me a story",
        expected_model = "deepseek-chat",
      },
    }

    for _, case in ipairs(test_cases) do
      local code_opts = {
        system_prompt = "test",
        messages = {
          { role = "user", content = case.content },
        },
      }

      deepseek.parse_messages(code_opts) -- This sets the model
      local args = deepseek.parse_curl_args({
        parse_api_key = function() return "test_key" end,
      }, code_opts)

      local model_prefix = args.body.model:match("^(deepseek%-%w+)")
      assert.equals(
        model_prefix,
        case.expected_model,
        string.format("Expected model %s but got %s for content: %s", case.expected_model, model_prefix, case.content)
      )
    end
  end)

  -- Test mixed conversation context
  it("should handle mixed conversation contexts", function()
    local code_opts = {
      system_prompt = "test",
      messages = {
        { role = "user", content = "Hi there!" },
        { role = "assistant", content = "Hello! How can I help?" },
        { role = "user", content = "function test() {\n  console.log('test');\n}" },
      },
    }

    local messages = deepseek.parse_messages(code_opts)
    local args = deepseek.parse_curl_args({
      parse_api_key = function() return "test_key" end,
    }, code_opts)

    -- Should switch to coder model when code is detected
    assert.equals(args.body.model:match("^deepseek%-coder"), "deepseek-coder")
  end)

  -- Test edge cases for model switching
  it("should handle edge cases in content detection", function()
    local edge_cases = {
      {
        content = "```python\nprint('hello')\n```\nWhat does this code do?",
        expected_model = "deepseek-coder", -- Should detect code in markdown
      },
      {
        content = "const x = 5; // Just a variable",
        expected_model = "deepseek-coder", -- Single line code
      },
      {
        content = "Here's some text with `code` inline",
        expected_model = "deepseek-chat", -- Inline code shouldn't trigger coder mode
      },
      {
        content = "",
        expected_model = "deepseek-chat", -- Empty content
      },
      {
        content = "   \n  \t  ",
        expected_model = "deepseek-chat", -- Whitespace only
      },
      {
        content = "print('hello')",
        expected_model = "deepseek-coder", -- Single line without terminator
      },
    }

    for _, case in ipairs(edge_cases) do
      local code_opts = {
        system_prompt = "test",
        messages = {
          { role = "user", content = case.content },
        },
      }

      deepseek.parse_messages(code_opts)
      local args = deepseek.parse_curl_args({ parse_api_key = function() return "test_key" end }, code_opts)

      local model_prefix = args.body.model:match("^(deepseek%-%w+)")
      assert.equals(
        model_prefix,
        case.expected_model,
        string.format(
          "Edge case failed - Expected %s but got %s for: %s",
          case.expected_model,
          model_prefix,
          case.content
        )
      )
    end
  end)

  -- Test message history context
  it("should maintain context across conversation", function()
    local conversation = {
      {
        messages = {
          { role = "user", content = "Hi there!" },
          { role = "assistant", content = "Hello! How can I help?" },
          { role = "user", content = "What is programming?" },
        },
        expected_model = "deepseek-chat",
      },
      {
        messages = {
          { role = "user", content = "function test() {}" },
        },
        expected_model = "deepseek-coder",
      },
    }

    for _, case in ipairs(conversation) do
      local code_opts = {
        system_prompt = "test",
        messages = case.messages,
      }

      deepseek.parse_messages(code_opts)
      local args = deepseek.parse_curl_args({ parse_api_key = function() return "test_key" end }, code_opts)

      local model_prefix = args.body.model:match("^(deepseek%-%w+)")
      assert.equals(model_prefix, case.expected_model)
    end
  end)
end)
