---@class IntegrationTestHelpers
---Integration test helper utilities for avante.nvim
local M = {}

local uv = vim.uv or vim.loop

---Setup test environment with proper isolation
---@param opts table|nil Optional configuration
---@return table Test environment context
function M.setup_test_env(opts)
  opts = opts or {}
  
  local test_dir = vim.fn.tempname()
  vim.fn.mkdir(test_dir, "p")
  
  -- Create test context
  local ctx = {
    test_dir = test_dir,
    config_backup = nil,
    original_cwd = vim.fn.getcwd(),
    cleanup_funcs = {},
  }
  
  -- Change to test directory
  vim.cmd("cd " .. test_dir)
  
  -- Initialize git repo for testing if needed
  if opts.git then
    vim.fn.system("git init")
    vim.fn.system("git config user.name 'Test User'")
    vim.fn.system("git config user.email 'test@example.com'")
  end
  
  -- Backup current avante config
  local avante_config = require("avante.config")
  ctx.config_backup = vim.deepcopy(avante_config.options)
  
  -- Add cleanup function
  table.insert(ctx.cleanup_funcs, function()
    -- Restore original config
    if ctx.config_backup then
      avante_config.options = ctx.config_backup
    end
    
    -- Restore original directory
    vim.cmd("cd " .. ctx.original_cwd)
    
    -- Clean up test directory
    vim.fn.delete(test_dir, "rf")
  end)
  
  return ctx
end

---Cleanup test environment
---@param ctx table Test environment context from setup_test_env
function M.cleanup_test_env(ctx)
  for _, cleanup_func in ipairs(ctx.cleanup_funcs) do
    pcall(cleanup_func)
  end
end

---Create a mock API response for testing
---@param provider string Provider name (openai, claude, etc.)
---@param response_type string Type of response (chat, streaming, error)
---@param content string|table Response content
---@return table Mock response
function M.create_mock_response(provider, response_type, content)
  local mock_responses = {
    openai = {
      chat = {
        id = "chatcmpl-test",
        object = "chat.completion",
        created = os.time(),
        model = "gpt-4",
        choices = {
          {
            index = 0,
            message = {
              role = "assistant",
              content = type(content) == "string" and content or content.message or "Test response"
            },
            finish_reason = "stop"
          }
        },
        usage = {
          prompt_tokens = 10,
          completion_tokens = 20,
          total_tokens = 30
        }
      },
      streaming = {
        id = "chatcmpl-test",
        object = "chat.completion.chunk",
        created = os.time(),
        model = "gpt-4",
        choices = {
          {
            index = 0,
            delta = {
              role = "assistant",
              content = type(content) == "string" and content or content.message or "Test"
            },
            finish_reason = nil
          }
        }
      },
      error = {
        error = {
          message = type(content) == "string" and content or "Test error",
          type = "invalid_request_error",
          code = "invalid_api_key"
        }
      }
    },
    claude = {
      chat = {
        id = "msg_test",
        type = "message",
        role = "assistant",
        content = {
          {
            type = "text",
            text = type(content) == "string" and content or content.message or "Test response"
          }
        },
        model = "claude-3-opus-20240229",
        stop_reason = "end_turn",
        usage = {
          input_tokens = 10,
          output_tokens = 20
        }
      },
      streaming = {
        type = "content_block_delta",
        index = 0,
        delta = {
          type = "text_delta",
          text = type(content) == "string" and content or content.message or "Test"
        }
      },
      error = {
        type = "error",
        error = {
          type = "invalid_request_error",
          message = type(content) == "string" and content or "Test error"
        }
      }
    }
  }
  
  return mock_responses[provider] and mock_responses[provider][response_type] or {}
end

---Assert that a provider response matches expected format
---@param response table The actual response
---@param provider string Provider name
---@param expected table Expected response structure
function M.assert_provider_response(response, provider, expected)
  assert(response, "Response should not be nil")
  
  if provider == "openai" then
    if expected.type == "chat" then
      assert(response.choices, "OpenAI response should have choices")
      assert(response.choices[1], "OpenAI response should have at least one choice")
      assert(response.choices[1].message, "OpenAI choice should have message")
      if expected.content then
        assert.equals(expected.content, response.choices[1].message.content)
      end
    end
  elseif provider == "claude" then
    if expected.type == "chat" then
      assert(response.content, "Claude response should have content")
      assert(response.content[1], "Claude response should have at least one content block")
      if expected.content then
        assert.equals(expected.content, response.content[1].text)
      end
    end
  end
end

---Simulate API calls with mock responses
---@param provider string Provider name
---@param endpoint string API endpoint
---@param payload table Request payload
---@param mock_response table Mock response to return
---@return table Mock API call result
function M.simulate_api_call(provider, endpoint, payload, mock_response)
  -- Simulate network delay
  vim.wait(10)
  
  return {
    status = 200,
    body = vim.fn.json_encode(mock_response),
    headers = {
      ["content-type"] = "application/json"
    }
  }
end

---Start mock HTTP server for testing
---@param port number Port number
---@param routes table Route configurations
---@return table Mock server handle
function M.start_mock_server(port, routes)
  -- This would integrate with Docker-based Wiremock in practice
  -- For now, we'll simulate with in-memory mock
  local server = {
    port = port,
    routes = routes,
    running = true
  }
  
  return server
end

---Stop mock HTTP server
---@param server table Server handle from start_mock_server
function M.stop_mock_server(server)
  server.running = false
end

---Wait for condition with timeout
---@param condition function Function that returns true when condition is met
---@param timeout number Timeout in milliseconds
---@param interval number Check interval in milliseconds
---@return boolean Whether condition was met within timeout
function M.wait_for_condition(condition, timeout, interval)
  timeout = timeout or 5000
  interval = interval or 100
  
  local start_time = uv.hrtime()
  while (uv.hrtime() - start_time) / 1000000 < timeout do
    if condition() then
      return true
    end
    vim.wait(interval)
  end
  return false
end

---Create test buffer with content
---@param content string|table Buffer content (string or lines array)
---@param filetype string|nil Buffer filetype
---@return number Buffer number
function M.create_test_buffer(content, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  
  local lines
  if type(content) == "string" then
    lines = vim.split(content, "\n")
  else
    lines = content
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  if filetype then
    vim.api.nvim_buf_set_option(buf, "filetype", filetype)
  end
  
  return buf
end

---Get test fixture content
---@param fixture_name string Name of the fixture file
---@return string|table Fixture content
function M.get_fixture(fixture_name)
  local fixtures_dir = vim.fn.expand("tests/integration/fixtures")
  local fixture_path = fixtures_dir .. "/" .. fixture_name
  
  if vim.fn.filereadable(fixture_path) == 1 then
    local content = vim.fn.readfile(fixture_path)
    if fixture_name:match("%.json$") then
      return vim.fn.json_decode(table.concat(content, "\n"))
    else
      return table.concat(content, "\n")
    end
  end
  
  error("Fixture not found: " .. fixture_name)
end

---Configure avante for integration testing
---@param provider_config table Provider-specific configuration
function M.configure_avante_for_testing(provider_config)
  local config = require("avante.config")
  
  -- Base test configuration
  local test_config = {
    provider = provider_config.provider or "openai",
    auto_suggestions = false,
    auto_set_highlight_group = false,
    support_paste_from_clipboard = false,
    vendors = {}
  }
  
  -- Add provider-specific configuration
  if provider_config.provider == "openai" then
    test_config.vendors.openai = {
      endpoint = provider_config.endpoint or "http://localhost:8080/v1/chat/completions",
      model = provider_config.model or "gpt-4",
      api_key_name = "OPENAI_API_KEY",
      parse_curl_args = function(opts, code_opts)
        return {
          url = opts.endpoint,
          headers = {
            ["Authorization"] = "Bearer test-key",
            ["Content-Type"] = "application/json",
          },
          body = vim.fn.json_encode({
            model = opts.model,
            messages = code_opts.messages,
            stream = code_opts.stream,
          }),
        }
      end,
    }
  elseif provider_config.provider == "claude" then
    test_config.vendors.claude = {
      endpoint = provider_config.endpoint or "http://localhost:8080/v1/messages",
      model = provider_config.model or "claude-3-opus-20240229",
      api_key_name = "ANTHROPIC_API_KEY",
      parse_curl_args = function(opts, code_opts)
        return {
          url = opts.endpoint,
          headers = {
            ["x-api-key"] = "test-key",
            ["Content-Type"] = "application/json",
            ["anthropic-version"] = "2023-06-01",
          },
          body = vim.fn.json_encode({
            model = opts.model,
            messages = code_opts.messages,
            max_tokens = 4096,
            stream = code_opts.stream,
          }),
        }
      end,
    }
  end
  
  -- Update avante configuration
  config.override(test_config)
end

return M