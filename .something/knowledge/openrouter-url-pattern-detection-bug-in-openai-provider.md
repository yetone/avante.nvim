# UUID
5575a3ba-6a94-4f95-9c6d-0fbf9895b090

# Trigger
OpenRouter URL pattern detection bug in OpenAI provider

# Content
Critical bug discovered in `lua/avante/providers/openai.lua` at line 49:

The current `M.is_openrouter(url)` function uses pattern `^https://openrouter%.ai/` which does NOT match the actual OpenRouter API endpoint `https://api.openrouter.ai/api/v1`.

This means automatic header injection for OpenRouter requests is currently broken.

**Fix required**:
```lua
function M.is_openrouter(url) 
  return url:match("^https://api%.openrouter%.ai/") or url:match("^https://openrouter%.ai/")
end
```

This bug must be fixed as part of adding OpenRouter as a built-in provider to ensure automatic header injection works correctly.