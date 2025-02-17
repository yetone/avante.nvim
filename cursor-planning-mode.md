Cursor planning mode
====================

Because avante.nvim has always used Aider’s method for planning applying, but its prompts are very picky with models and require ones like claude-3.5-sonnet or gpt-4o to work properly.

Therefore, I have adopted Cursor’s method to implement planning applying. For details on the implementation, please refer to: [🚀 Introducing Fast Apply - Replicate Cursor's Instant Apply model](https://www.reddit.com/r/LocalLLaMA/comments/1ga25gj/introducing_fast_apply_replicate_cursors_instant/)

So you need to first run the `FastApply` model mentioned above:

```bash
ollama pull hf.co/Kortix/FastApply-7B-v1.0_GGUF:Q4_K_M
```

Then enable it in avante.nvim:

```lua
{
    --- ... existing configurations
    cursor_applying_provider = 'fastapply',
    behaviour = {
        --- ... existing behaviours
        enable_cursor_planning_mode = true,
    },
    vendors = {
        --- ... existing vendors
        fastapply = {
            __inherited_from = 'openai',
            api_key_name = '',
            endpoint = 'http://localhost:11434/v1',
            model = 'hf.co/Kortix/FastApply-7B-v1.0_GGUF:Q4_K_M',
        },
    },
    --- ... existing configurations
}
```
