# Integration Tests for Avante.nvim

This directory contains comprehensive integration tests for the Avante.nvim plugin, covering end-to-end AI provider communication, UI workflows, and multi-provider functionality.

## Overview

Integration tests validate the complete functionality of Avante.nvim by testing:

- **Provider Integration**: Communication with AI service providers (OpenAI, Claude, Bedrock, etc.)
- **Workflow Testing**: End-to-end user workflows (chat, code completion, ask functionality)
- **UI Component Testing**: Sidebar interactions, message display, and user input handling
- **Multi-provider Support**: Dynamic provider switching and configuration management
- **Error Handling**: Network failures, API errors, rate limiting, and recovery mechanisms

## Test Architecture

### Mock Service Infrastructure

Integration tests use Docker-based mock services to ensure reliable, deterministic testing:

- **Wiremock**: HTTP API mocking for OpenAI, Claude, and other REST-based providers
- **LocalStack**: AWS service mocking for Bedrock integration
- **Ollama Mock**: Local model provider simulation

### Test Structure

```
tests/integration/
├── helpers/           # Test utilities and helper functions
├── providers/         # Provider-specific integration tests  
├── workflows/         # End-to-end workflow tests
├── ui/               # UI component integration tests
├── fixtures/         # Test data and mock responses
├── mock_services/    # Mock service configurations
└── README.md         # This documentation
```

## Running Integration Tests

### Prerequisites

- Docker and Docker Compose
- Neovim v0.10.0 or later
- plenary.nvim plugin
- Make

### Quick Start

```bash
# Run all integration tests
make integration-test

# Run provider tests only
make test-providers

# Run workflow tests only  
make test-workflows

# Run UI tests only
make test-ui

# Run all tests (unit + integration)
make test-all
```

### Manual Setup

1. Start mock services:
```bash
make integration-test-setup
```

2. Run specific test files:
```bash
nvim --headless -c "PlenaryBustedFile tests/integration/providers/openai_spec.lua"
```

3. Cleanup:
```bash
make integration-test-teardown
```

## Test Categories

### Provider Integration Tests

Located in `tests/integration/providers/`, these tests validate:

- **Authentication**: API key validation and error handling
- **Request Formatting**: Proper message formatting for each provider's API
- **Response Parsing**: Correct handling of streaming and non-streaming responses
- **Error Scenarios**: Rate limiting, network failures, invalid models
- **Model Selection**: Support for different model variants

#### Supported Providers

- **OpenAI** (`openai_spec.lua`): GPT-4, GPT-3.5, streaming, tools
- **Claude** (`claude_spec.lua`): Claude-3 variants, prompt caching, streaming
- **AWS Bedrock** (`bedrock_spec.lua`): Claude on Bedrock, SigV4 auth
- **Azure OpenAI** (`azure_spec.lua`): Deployment endpoints, API versions
- **Google Gemini** (`gemini_spec.lua`): Vertex AI integration
- **Ollama** (`ollama_spec.lua`): Local model management

### Workflow Integration Tests

Located in `tests/integration/workflows/`, these tests cover:

- **Chat Workflow** (`chat_spec.lua`): Full conversation flows
- **Code Completion** (`completion_spec.lua`): Real-time code suggestions
- **Ask Functionality** (`ask_spec.lua`): Context-aware questioning
- **Provider Switching**: Dynamic provider changes during conversations

### UI Integration Tests

Located in `tests/integration/ui/`, these tests validate:

- **Sidebar Rendering**: Chat interface display and interactions
- **Message Display**: Markdown formatting, code highlighting
- **User Input**: Keyboard shortcuts, command handling
- **Buffer Integration**: Code context inclusion and diff application

## Mock Service Configuration

### Wiremock Mappings

Mock API endpoints are configured in `mock_services/mappings/`:

- `openai-chat.json`: OpenAI chat completions endpoint
- `claude-chat.json`: Claude messages endpoint  
- Provider-specific error scenarios and rate limiting

### Response Templates

Mock responses in `mock_services/files/` use Wiremock templating:

- Dynamic response generation based on request content
- Realistic timing and token usage simulation
- Error response simulation with appropriate HTTP status codes

### Docker Compose Setup

`docker-compose.test.yml` defines the test environment:

- **Wiremock**: Port 8080, with health checks and volume mounts
- **LocalStack**: Port 4566, for AWS service mocking
- **Ollama Mock**: Port 11434, for local model testing

## Test Utilities

### Integration Test Helpers

`helpers/init.lua` provides utility functions:

```lua
-- Setup isolated test environment
local ctx = helpers.setup_test_env({ git = false })

-- Configure provider for testing
helpers.configure_avante_for_testing({
  provider = "openai",
  endpoint = "http://localhost:8080/v1/chat/completions"
})

-- Create mock responses
local mock_response = helpers.create_mock_response("openai", "chat", "Test response")

-- Assert provider responses
helpers.assert_provider_response(response, "openai", { content = "Expected text" })

-- Wait for conditions
helpers.wait_for_condition(function() return test_complete end, 5000)

-- Cleanup
helpers.cleanup_test_env(ctx)
```

### Test Fixtures

Test data in `fixtures/` includes:

- **Code Samples**: Multi-language code examples for context testing
- **API Responses**: Realistic provider response examples
- **Configurations**: Various avante configuration scenarios

## CI/CD Integration

### GitHub Actions

`.github/workflows/integration.yml` provides automated testing:

- **Multi-version Testing**: Neovim v0.10.0 and nightly
- **Parallel Execution**: Provider, workflow, and UI tests run in parallel
- **Artifact Collection**: Test results and logs preserved
- **Service Health Checks**: Ensures mock services are ready before testing

### Test Reporting

Integration tests generate reports including:

- Test execution time and coverage
- Provider-specific success rates  
- Error analysis and failure patterns
- Performance metrics and regression detection

## Best Practices

### Writing Integration Tests

1. **Use Test Isolation**: Always use `setup_test_env()` and cleanup
   ```lua
   before_each(function()
     test_ctx = helpers.setup_test_env()
   end)
   
   after_each(function()
     helpers.cleanup_test_env(test_ctx)
   end)
   ```

2. **Mock External Dependencies**: Use provided mock services
   ```lua
   helpers.configure_avante_for_testing({
     provider = "openai",
     endpoint = "http://localhost:8080/v1/chat/completions"
   })
   ```

3. **Test Both Success and Failure Cases**:
   ```lua
   it("should handle authentication errors", function()
     vim.env.OPENAI_API_KEY = "invalid-key"
     -- Test error handling
   end)
   ```

4. **Use Realistic Test Data**: Leverage fixtures for consistent testing
   ```lua
   local code_sample = helpers.get_fixture("code_samples/javascript_function.js")
   ```

5. **Validate Complete Workflows**: Test end-to-end user scenarios
   ```lua
   -- Test complete chat conversation
   avante.ask({ question = "Explain this code", bufnr = test_buf })
   helpers.wait_for_condition(function() return response_received end)
   ```

### Debugging Integration Tests

1. **Check Mock Service Logs**:
   ```bash
   docker-compose -f docker-compose.test.yml logs wiremock
   ```

2. **Verify Service Health**:
   ```bash
   curl http://localhost:8080/__admin/health
   ```

3. **Inspect Mock Mappings**:
   ```bash
   curl http://localhost:8080/__admin/mappings
   ```

4. **Run Individual Tests**:
   ```bash
   nvim --headless -c "PlenaryBustedFile tests/integration/providers/openai_spec.lua"
   ```

## Troubleshooting

### Common Issues

**Mock Services Not Starting**:
- Check Docker is running: `docker --version`
- Verify ports aren't in use: `lsof -i :8080`
- Check Docker Compose logs: `docker-compose -f docker-compose.test.yml logs`

**Test Failures**:
- Ensure API keys are set (even mock values)
- Verify Neovim version compatibility
- Check plenary.nvim is installed correctly

**Slow Test Execution**:
- Mock services may need warmup time
- Increase timeout values in `helpers.wait_for_condition()`
- Check system resources and Docker performance

**Provider-specific Issues**:
- Verify mock mappings match expected request format
- Check response templates use correct JSON structure  
- Ensure provider configuration matches test setup

### Getting Help

1. **Check Existing Issues**: Review integration test failures in CI/CD
2. **Review Logs**: Mock service logs often contain helpful debugging info
3. **Validate Environment**: Ensure all prerequisites are properly installed
4. **Test Isolation**: Run single tests to identify specific failure points

## Contributing

When adding new integration tests:

1. **Follow Existing Patterns**: Use established test structure and helpers
2. **Add Mock Services**: Configure appropriate mock endpoints for new providers
3. **Update Documentation**: Document new test categories and usage
4. **Test CI/CD**: Ensure new tests work in GitHub Actions environment
5. **Add Fixtures**: Provide realistic test data for new scenarios

### Adding New Provider Tests

1. Create provider-specific test file: `tests/integration/providers/newprovider_spec.lua`
2. Add mock service mappings: `mock_services/mappings/newprovider-*.json`
3. Create response templates: `mock_services/files/newprovider-*.json`
4. Update helper functions if needed: `helpers/init.lua`
5. Add to CI/CD workflow: `.github/workflows/integration.yml`

This comprehensive integration test suite ensures Avante.nvim works reliably across all supported AI providers and user workflows.