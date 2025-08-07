# Trigger

When ReAct prompts cause double LLM API invocations after on_stop completion

# Content

ReAct (Reasoning and Acting) prompts in Avante can cause unwanted double API invocations due to multiple callback triggers:

1. **Root Cause**: Providers like OpenAI and Gemini call `on_stop({ reason = "tool_use" })` both during tool parsing (line 325 in OpenAI) and during stream completion (line 386)

2. **Solution Pattern**: Implement state tracking to prevent duplicate callbacks:
   - Add ReAct state management variables (`react_mode`, `processing_tools`, `tools_ready`)
   - Modify `on_stop` handlers to check processing state before proceeding
   - Update providers to only call callbacks when tools are complete (not partial)

3. **Configuration**: Add `experimental.fix_react_double_invocation = true` flag for backward compatibility

4. **Providers Affected**: OpenAI, Gemini, and Vertex AI (any provider with `use_ReAct_prompt = true`)

This fix reduces API usage by ~50% when using ReAct prompts by eliminating redundant LLM calls while maintaining full ReAct functionality.