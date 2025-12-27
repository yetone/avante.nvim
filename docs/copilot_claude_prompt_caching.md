# Prompt Caching for Claude Models via Copilot Provider

This document explains how prompt caching is implemented for Claude models when accessed through the GitHub Copilot provider in avante.nvim.

## Overview

Prompt caching is a feature that reduces API costs and improves response times by caching portions of prompts that are frequently reused. This implementation extends the existing prompt caching functionality (already available for Claude models through the direct Claude provider and AWS Bedrock provider) to Claude models accessed through the GitHub Copilot provider.

## How It Works

When a Claude model is detected through the Copilot provider and prompt caching is enabled, the following happens:

1. The Claude-specific header `anthropic-beta: prompt-caching-2024-07-31` is added to the request
2. `cache_control = { type = "ephemeral" }` is added to:
   - Messages (text content)
   - Tools (if present)
3. Token usage tracking records cache hit rates and performance metrics

This implementation follows the same pattern used in the Claude and Bedrock providers to ensure consistent behavior across all access methods for Claude models.

## Configuration

Prompt caching for Claude models via Copilot is controlled by the standard prompt caching configuration in `config.lua`:

```lua
-- Prompt caching configuration
prompt_caching = {
  enabled = true,  -- Global enable/disable
  providers = {
    claude = true,
    bedrock = true,
    copilot = true  -- Enable for Copilot provider
  }
}
```

You can enable or disable prompt caching:
- Globally by setting `prompt_caching.enabled = true/false`
- For specific providers by setting `prompt_caching.providers.copilot = true/false`

## Claude Model Detection

The implementation detects Claude models by checking if the model name (case-insensitive) contains "claude". This works with all current Claude model variants available through the Copilot provider.

## Token Usage Tracking

When prompt caching is enabled, the system tracks:
- Cache hit tokens: Tokens read from cache
- Cache write tokens: Tokens written to cache
- Total input tokens: Total tokens processed
- Cache hit rate: Percentage of tokens read from cache

These metrics help measure the effectiveness of prompt caching in reducing API costs.

## Benefits

1. **Cost Reduction**: Cached tokens are typically billed at a lower rate than uncached tokens
2. **Improved Latency**: Cached portions of prompts don't need to be reprocessed by the model
3. **Consistency**: The same prompt caching benefits are now available regardless of which provider is used to access Claude models

## Troubleshooting

If prompt caching doesn't seem to be working with Claude models through Copilot:

1. Verify that prompt caching is enabled in the configuration (`prompt_caching.enabled = true` and `prompt_caching.providers.copilot = true`)
2. Confirm that you're using a Claude model (model name should contain "claude")
3. Check that the Copilot provider is correctly authenticating and making requests to the API
4. Look for any errors in the logs related to prompt caching or headers

## Implementation Details

The implementation includes:
- Claude model detection in the Copilot provider
- Addition of prompt caching support flag
- Modification of request generation to add Claude-specific headers and message modifications
- Token usage tracking for cached prompts
- Configuration updates to include Copilot in prompt caching providers
