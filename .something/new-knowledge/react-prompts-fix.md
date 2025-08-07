# Trigger

ReAct prompts double invocation fix, ReAct callback loops, tool_use double calls

# Content

When `use_ReAct_prompts = true`, the system was experiencing double LLM API invocations after tool completion due to multiple callback triggers. This was fixed by implementing:

1. **State Management**: Added ReAct-specific state tracking in `lua/avante/llm.lua` to monitor processing status
2. **Duplicate Prevention**: Implemented logic to prevent duplicate `tool_use` callbacks when tools are already being processed
3. **Parser Enhancement**: Enhanced `ReAct_parser2.lua` to return metadata about tool completion state
4. **Provider Coordination**: Updated OpenAI and Gemini providers to use shared state and only trigger callbacks when appropriate
5. **Feature Flag**: Added `experimental.fix_react_double_invocation` configuration option for gradual rollout

The fix reduces API usage by approximately 50% for ReAct workflows while maintaining full functionality. All changes are backward compatible and can be disabled via configuration.

**Key Files Modified:**
- `lua/avante/llm.lua`: State management and callback prevention
- `lua/avante/providers/openai.lua`: ReAct-aware callback logic  
- `lua/avante/providers/gemini.lua`: Consistent ReAct handling
- `lua/avante/libs/ReAct_parser2.lua`: Enhanced metadata support
- `lua/avante/config.lua`: Feature flag configuration

**Testing:** Comprehensive unit tests added for parser functionality and state management to prevent regressions.