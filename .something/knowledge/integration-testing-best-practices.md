# Trigger

integration testing, test patterns, testing best practices, provider testing, workflow testing

# Content

## Integration Testing Best Practices for Avante.nvim

### Test Structure and Organization

**Use Consistent Test File Naming**:
- Provider tests: `{provider}_spec.lua` (e.g., `openai_spec.lua`, `claude_spec.lua`)
- Workflow tests: `{workflow}_spec.lua` (e.g., `chat_spec.lua`, `completion_spec.lua`)
- UI tests: `{component}_spec.lua` (e.g., `sidebar_spec.lua`)

**Follow Test Isolation Pattern**:
```lua
describe("Test Suite", function()
  local test_ctx

  before_each(function()
    test_ctx = helpers.setup_test_env({ git = false })
    helpers.configure_avante_for_testing({
      provider = "openai",
      endpoint = "http://localhost:8080/v1/chat/completions"
    })
  end)

  after_each(function()
    helpers.cleanup_test_env(test_ctx)
  end)
end)
```

### Mock Service Testing

**Always Use Mock Services for Integration Tests**:
- Use Docker Compose with Wiremock for HTTP API mocking
- Configure realistic response timing and data patterns
- Test both success and error scenarios with appropriate mock mappings

**Mock Service Configuration**:
```lua
-- Configure provider to use mock endpoint
helpers.configure_avante_for_testing({
  provider = "openai",
  endpoint = "http://localhost:8080/v1/chat/completions",
  model = "gpt-4"
})

-- Set test API keys (even for mocks)
vim.env.OPENAI_API_KEY = "test-key"
```

### Provider Testing Guidelines

**Test All Provider Scenarios**:
1. **Success Cases**: Valid requests with expected responses
2. **Authentication Errors**: Invalid API keys, expired tokens
3. **Rate Limiting**: 429 responses with retry-after headers
4. **Network Errors**: Timeout, connection failures
5. **Model Errors**: Invalid model names, unsupported features

**Provider-Specific Patterns**:
```lua
-- OpenAI pattern
local test_response = {
  choices = {{ message = { role = "assistant", content = "Test response" } }}
}

-- Claude pattern
local test_response = {
  content = {{ type = "text", text = "Test response" }}
}

helpers.assert_provider_response(response, "openai", {
  type = "chat",
  content = "Expected content"
})
```

### Workflow Testing Practices

**Test Complete User Workflows**:
- Initialize components properly
- Simulate user interactions realistically
- Validate state changes and UI updates
- Test error recovery and resilience

**Use Realistic Test Data**:
```lua
-- Use fixture files for consistent test data
local code_sample = helpers.get_fixture("code_samples/javascript_function.js")

-- Create test buffers with proper content
local test_buf = helpers.create_test_buffer(code_sample, "javascript")
```

### Error Handling Testing

**Test Error Scenarios Comprehensively**:
```lua
it("should handle network timeouts", function()
  local timeout_error = false

  local code_opts = {
    timeout = 1000,
    on_error = function(err)
      if err:match("timeout") then
        timeout_error = true
      end
    end
  }

  -- Simulate timeout
  assert.is_true(timeout_error)
end)
```

### Async Testing Patterns

**Use Wait Conditions for Async Operations**:
```lua
-- Wait for async operations to complete
helpers.wait_for_condition(function()
  return response_received
end, 5000, 100) -- 5s timeout, 100ms check interval

-- Test streaming responses
for _, chunk in ipairs(test_chunks) do
  if code_opts.on_chunk then
    code_opts.on_chunk(chunk)
  end
end
```

### Test Performance and Reliability

**Ensure Tests Complete Quickly**:
- Use mock services to avoid network delays
- Set appropriate timeouts (< 10 minutes total execution)
- Implement proper cleanup to prevent resource leaks

**Test Isolation Requirements**:
- Each test should be independent and repeatable
- Clean up temporary files, buffers, and configurations
- Reset global state between tests

### CI/CD Integration

**Make Tests CI/CD Friendly**:
- Use environment variables for configuration
- Provide clear error messages and debugging information
- Generate test reports and collect artifacts
- Ensure tests work in headless environments

### Debugging Integration Tests

**Include Debugging Helpers**:
```lua
-- Add debugging output when tests fail
if not success then
  print("Test failed - Mock service logs:")
  vim.fn.system("docker-compose -f docker-compose.test.yml logs wiremock")
end
```

**Common Debugging Steps**:
1. Check mock service health: `curl http://localhost:8080/__admin/health`
2. Verify mock mappings: `curl http://localhost:8080/__admin/mappings`
3. Check service logs: `docker-compose logs`
4. Run individual test files for isolation
5. Validate environment variables and configuration
