# UUID
db88f4c4-bb2f-4e9a-9de9-db3163fa3197

# Trigger
OpenRouter provider implementation, provider inheritance patterns in Avante.nvim, OpenAI provider OpenRouter compatibility

# Content
## OpenRouter Provider Implementation Strategy

When implementing OpenRouter as a built-in provider in Avante.nvim:

1. **Use Provider Inheritance**: Set `__inherited_from = "openai"` to leverage existing OpenAI provider functionality
2. **Leverage Existing Detection**: OpenAI provider already has `M.is_openrouter(url)` detection at line 49 
3. **Automatic Header Injection**: OpenRouter-specific headers are automatically added in `parse_curl_args` when OpenRouter URL detected:
   - `HTTP-Referer: https://github.com/yetone/avante.nvim`  
   - `X-Title: Avante.nvim`
   - `include_reasoning: true`

## Configuration Pattern
```lua
openrouter = {
  __inherited_from = "openai",
  endpoint = "https://api.openrouter.ai/api/v1",
  model = "openai/gpt-4o-mini",
  api_key_name = "OPENROUTER_API_KEY",
  timeout = 30000,
  context_window = 128000,
  extra_request_body = {
    temperature = 0.75,
    max_tokens = 4096,
  },
}
```

## Provider Inheritance System
- Inheritance handled in `lua/avante/providers/init.lua:151-155`
- Base provider loaded first, then overrides applied via `Utils.deep_extend_with_metatable`
- Environment variables support both scoped (`AVANTE_*`) and global patterns
- Automatic tokenizer setup and API key validation

## Best Practices
- Always provide sensible default model for immediate usability
- Follow existing provider configuration patterns for consistency  
- Use cost-effective models as defaults (e.g., gpt-4o-mini vs gpt-4o)
- Leverage existing compatibility layers rather than reimplementing