# Trigger

provider testing, AI provider integration, API testing, mock services, provider patterns

# Content

## AI Provider Testing Patterns for Avante.nvim

### Provider Test Structure

**Standard Provider Test Layout**:
```lua
describe("{Provider} Provider Integration", function()
  local test_ctx
  
  before_each(function() 
    test_ctx = helpers.setup_test_env()
    helpers.configure_avante_for_testing({
      provider = "{provider}",
      endpoint = "http://localhost:8080/v1/{endpoint}",
      model = "{default_model}"
    })
    vim.env.{PROVIDER}_API_KEY = "test-key"
  end)
  
  after_each(function()
    helpers.cleanup_test_env(test_ctx)
    vim.env.{PROVIDER}_API_KEY = nil
  end)
end)
```

### Provider-Specific Patterns

**OpenAI Provider Testing**:
```lua
-- OpenAI uses choices array structure
local test_response = {
  id = "chatcmpl-test",
  object = "chat.completion",
  choices = [{
    index = 0,
    message = {
      role = "assistant", 
      content = "Test response"
    },
    finish_reason = "stop"
  }],
  usage = {
    prompt_tokens = 10,
    completion_tokens = 15,
    total_tokens = 25
  }
}

-- Test streaming format
local streaming_chunks = [
  'data: {"id":"chatcmpl-test","choices":[{"delta":{"content":"Hello"}}]}',
  'data: [DONE]'
]
```

**Claude Provider Testing**:
```lua
-- Claude uses content array structure
local test_response = {
  id = "msg_test",
  type = "message", 
  role = "assistant",
  content = [{
    type = "text",
    text = "Test response"
  }],
  model = "claude-3-opus-20240229",
  stop_reason = "end_turn",
  usage = {
    input_tokens = 20,
    output_tokens = 25
  }
}

-- Test streaming events
local streaming_events = [
  'event: message_start\ndata: {"type": "message_start"}',
  'event: content_block_delta\ndata: {"delta": {"text": "Hello"}}',
  'event: message_stop\ndata: {"type": "message_stop"}'
]
```

**AWS Bedrock Provider Testing**:
```lua
-- Bedrock requires SigV4 authentication testing
it("should handle AWS SigV4 authentication", function()
  local auth_headers_captured = {}
  
  -- Mock AWS credential and signing
  vim.env.AWS_ACCESS_KEY_ID = "test-access-key"
  vim.env.AWS_SECRET_ACCESS_KEY = "test-secret-key"
  vim.env.AWS_REGION = "us-east-1"
  
  -- Test different Bedrock model formats
  local models = {
    "anthropic.claude-3-opus-20240229-v1:0",
    "meta.llama2-70b-chat-v1",
    "amazon.titan-text-express-v1"
  }
end)
```

### Common Provider Test Scenarios

**Authentication Testing**:
```lua
describe("Authentication", function()
  it("should handle valid API keys", function()
    vim.env.{PROVIDER}_API_KEY = "valid-test-key"
    -- Test successful authentication
  end)
  
  it("should handle invalid API keys", function()
    vim.env.{PROVIDER}_API_KEY = "invalid-key"
    local auth_error = false
    
    local code_opts = {
      on_error = function(err)
        if err:match("API key") or err:match("authentication") then
          auth_error = true
        end
      end
    }
    
    assert.is_true(auth_error)
  end)
end)
```

**Rate Limiting Testing**:
```lua
describe("Rate Limiting", function()
  it("should handle rate limit responses", function()
    vim.env.{PROVIDER}_API_KEY = "rate-limit-key"
    
    local rate_limited = false
    local retry_after = nil
    
    local code_opts = {
      on_error = function(err, headers)
        if err:match("rate limit") then
          rate_limited = true
          retry_after = headers and headers["Retry-After"]
        end
      end
    }
    
    assert.is_true(rate_limited)
    assert.True(retry_after ~= nil)
  end)
end)
```

**Streaming Response Testing**:
```lua
describe("Streaming Responses", function()
  it("should handle streaming chunks correctly", function()
    local chunks_received = {}
    local stream_complete = false
    
    local code_opts = {
      stream = true,
      on_chunk = function(chunk)
        table.insert(chunks_received, chunk)
      end,
      on_complete = function()
        stream_complete = true
      end
    }
    
    -- Simulate provider-specific streaming format
    -- ... provider-specific streaming simulation
    
    assert.True(#chunks_received > 0)
    assert.is_true(stream_complete)
  end)
end)
```

**Model Selection Testing**:
```lua
describe("Model Selection", function()
  it("should support different model variants", function()
    local models_tested = {}
    local provider_models = {
      openai = ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"],
      claude = ["claude-3-opus-20240229", "claude-3-sonnet-20240229"],
      bedrock = ["anthropic.claude-3-opus-20240229-v1:0"]
    }
    
    for _, model in ipairs(provider_models[current_provider]) do
      -- Test each model configuration
      table.insert(models_tested, model)
    end
    
    assert.equals(#provider_models[current_provider], #models_tested)
  end)
end)
```

### Error Scenario Testing

**Network Error Handling**:
```lua
describe("Network Errors", function()
  it("should handle connection timeouts", function()
    local timeout_error = false
    
    local code_opts = {
      timeout = 1000,
      on_error = function(err)
        if err:match("timeout") or err:match("connection") then
          timeout_error = true
        end
      end
    }
    
    assert.is_true(timeout_error)
  end)
  
  it("should handle DNS resolution failures", function()
    helpers.configure_avante_for_testing({
      endpoint = "http://nonexistent-domain.local/api"
    })
    
    local dns_error = false
    local code_opts = {
      on_error = function(err)
        if err:match("resolve") or err:match("DNS") then
          dns_error = true
        end
      end
    }
    
    assert.is_true(dns_error)
  end)
end)
```

**API Error Response Testing**:
```lua
describe("API Errors", function()
  it("should handle model not found errors", function()
    local model_error = false
    
    helpers.configure_avante_for_testing({
      model = "nonexistent-model"
    })
    
    local code_opts = {
      on_error = function(err, status_code)
        if status_code == 404 and err:match("model") then
          model_error = true
        end
      end
    }
    
    assert.is_true(model_error)
  end)
  
  it("should handle quota exceeded errors", function()
    -- Test quota/billing errors specific to provider
  end)
end)
```

### Mock Service Validation

**Test Mock Service Responses**:
```lua
describe("Mock Service Validation", function()
  it("should receive expected mock responses", function()
    local response = helpers.simulate_api_call(
      "openai",
      "/v1/chat/completions", 
      { model = "gpt-4", messages = [{ role = "user", content = "test" }] },
      helpers.create_mock_response("openai", "chat", "Mock response")
    )
    
    assert.equals(200, response.status)
    assert.True(response.body:match("Mock response"))
  end)
end)
```

### Provider Configuration Testing

**Test Provider-Specific Configuration**:
```lua
describe("Provider Configuration", function()
  it("should handle provider-specific options", function()
    -- OpenAI-specific options
    helpers.configure_avante_for_testing({
      provider = "openai",
      temperature = 0.7,
      max_tokens = 2048,
      top_p = 0.9
    })
    
    -- Claude-specific options  
    helpers.configure_avante_for_testing({
      provider = "claude",
      max_tokens = 4096,
      system_message = "You are a helpful assistant"
    })
    
    -- Validate configuration is applied correctly
  end)
end)
```

### Performance Testing

**Test Response Time Requirements**:
```lua
describe("Performance", function()
  it("should respond within acceptable time limits", function()
    local start_time = vim.loop.hrtime()
    local response_time = nil
    
    local code_opts = {
      on_complete = function()
        response_time = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to ms
      end
    }
    
    helpers.wait_for_condition(function()
      return response_time ~= nil
    end, 10000)
    
    assert.True(response_time < 5000) -- Should respond within 5 seconds
  end)
end)
```