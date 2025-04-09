Cursor planning mode
====================

Because avante.nvim has always used Aider’s method for planning applying, but its prompts are very picky with models and require ones like claude-3.5-sonnet or gpt-4o to work properly.

Therefore, I have adopted Cursor’s method to implement planning applying, which should work on most models. If you encounter issues with your current model, I highly recommend switching to cursor planning mode to resolve them.

For details on the implementation, please refer to: [🚀 Introducing Fast Apply - Replicate Cursor's Instant Apply model](https://www.reddit.com/r/LocalLLaMA/comments/1ga25gj/introducing_fast_apply_replicate_cursors_instant/)

~~So you need to first run the `FastApply` model mentioned above:~~

~~```bash~~
ollama pull hf.co/Kortix/FastApply-7B-v1.0_GGUF:Q4_K_M
~~```~~

An interesting fact is that I found the `FastApply` model mentioned above doesn't work well. First, it's too slow, and second, it's not accurate for processing long code file. It often includes `// ... existing code ...` comments in the generated final code, resulting in incorrect code generation.

The best model I found for applying is `llama-3.3-70b-versatile` on [Groq](https://console.groq.com/playground), it's both fast and accurate, it's perfect!

Then enable it in avante.nvim:

```lua
{
    --- ... existing configurations
    provider = 'claude', -- In this example, use Claude for planning, but you can also use any provider you want.
    cursor_applying_provider = 'groq', -- In this example, use Groq for applying, but you can also use any provider you want.
    behaviour = {
        --- ... existing behaviours
        enable_cursor_planning_mode = true, -- enable cursor planning mode!
    },
    vendors = {
        --- ... existing vendors
        groq = { -- define groq provider
            __inherited_from = 'openai',
            api_key_name = 'GROQ_API_KEY',
            endpoint = 'https://api.groq.com/openai/v1/',
            model = 'llama-3.3-70b-versatile',
            max_completion_tokens = 32768, -- remember to increase this value, otherwise it will stop generating halfway
        },
    },
    --- ... existing configurations
}
```
