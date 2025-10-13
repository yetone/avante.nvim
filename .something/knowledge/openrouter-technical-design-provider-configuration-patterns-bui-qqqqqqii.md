# UUID
f7789a99-f9f1-4047-bb5e-1dc36b69efe3

# Trigger
OpenRouter technical design, provider configuration patterns, built-in provider implementation, Avante.nvim architecture analysis

# Content
## OpenRouter Technical Design Implementation Findings

### Provider Configuration Structure in Avante.nvim
- Built-in providers defined in `lua/avante/config.lua` within `providers = {}` table (lines 265+)
- Each provider includes standard fields: endpoint, model, timeout, context_window, extra_request_body
- Provider inheritance supported via `__inherited_from` field pointing to base provider name
- Example inheritance pattern: `["claude-haiku"] = { __inherited_from = "claude", model = "claude-3-5-haiku-20241022" }`

### Provider Inheritance System Architecture
- Inheritance handled in `lua/avante/providers/init.lua` metatable `__index` method (lines 151-155)
- Base provider loaded first using `require("avante.providers." .. provider_config.__inherited_from)`
- Configuration merged using `Utils.deep_extend_with_metatable("force", module, base_provider_config, provider_config)`
- Environment variables support both scoped (`AVANTE_*`) and global patterns via `E.parse_envvar()`

### OpenAI Provider OpenRouter Compatibility
- OpenAI provider contains `M.is_openrouter(url)` detection function at line 49
- Automatic OpenRouter header injection in `parse_curl_args` when OpenRouter URL detected (lines 519-523):
  - `headers["HTTP-Referer"] = "https://github.com/yetone/avante.nvim"`
  - `headers["X-Title"] = "Avante.nvim"`
  - `request_body.include_reasoning = true`
- This eliminates need for separate OpenRouter provider implementation

### Configuration File Structure Requirements
- New providers added between existing providers in config.lua providers table
- Type annotations using `---@type AvanteSupportedProvider` for consistency
- Standard fields: endpoint, model, api_key_name, timeout, context_window, extra_request_body
- Inheritance providers can override specific fields while inheriting base functionality

### Environment Variable and API Key Management
- API key parsing through `E.parse_envvar()` supports scoped and global patterns
- Automatic `parse_api_key()` function added to providers via metatable (line 172)
- `is_env_set()` function validates environment setup (lines 177-185)
- User prompted for API key input if not found via secure input UI

### Best Practices for Built-in Provider Implementation
- Minimize code changes by leveraging inheritance patterns
- Use cost-effective default models for immediate user value
- Follow existing provider naming and structure conventions
- Leverage existing compatibility detection rather than reimplementing
- Ensure consistent timeout and context window values across similar providers