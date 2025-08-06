# Trigger

ReAct prompts causing double LLM API invocations, duplicate tool_use callbacks

# Content

When ReAct prompts (use_ReAct_prompt = true) are enabled, the system can cause unwanted duplicate LLM API calls after request termination. The issue occurs because:

1. Partial tool parsing triggers immediate on_stop callbacks with reason "tool_use" 
2. Stream completion logic doesn't check tool readiness before triggering callbacks
3. No state tracking prevents duplicate callback execution

The fix involves:

1. **State tracking in LLM core**: Add react_mode, processing_tools, tools_pending, and react_tools_ready flags to opts.session_ctx in lua/avante/llm.lua
2. **Duplicate callback prevention**: Check processing_tools state in on_stop handler before executing tool_use callbacks
3. **Provider-specific fixes**: 
   - OpenAI: Don't trigger callbacks for partial tools in ReAct mode, check tool completion state before callbacks
   - Gemini: Apply same ReAct-aware tool completion checks
4. **Enhanced ReAct parser**: Return metadata about tool completion state including tool_count, partial_tool_count, all_tools_complete

Key implementation points:
- Only trigger tool_use callbacks when all_tools_complete is true in ReAct mode  
- Reset processing_tools flag when tool processing completes
- Add comprehensive debug logging for ReAct callback flows
- Maintain backward compatibility for non-ReAct modes