# Message Architecture Separation: ModelMessage and UIMessage

This document describes the new separated message architecture that distinguishes between LLM concerns (ModelMessage) and UI rendering concerns (UIMessage).

## Overview

The Avante.nvim plugin has been refactored to separate the monolithic `avante.HistoryMessage` structure into two distinct types:

- **ModelMessage**: Handles pure LLM interaction data
- **UIMessage**: Handles rendering and display-specific data

This separation improves maintainability, testability, and allows independent optimization of LLM and UI concerns.

## Architecture

### Before: Monolithic Structure

```lua
---@class avante.HistoryMessage (OLD)
-- Mixed LLM and UI concerns
local message = {
    -- LLM data
    message = { role = "user", content = "Hello" },
    provider = "claude",
    tool_use_logs = {},
    
    -- UI data  
    displayed_content = "Formatted content",
    visible = true,
    is_dummy = false,
}
```

### After: Separated Structure

```lua
---@class avante.ModelMessage (NEW)
-- Pure LLM concerns
local model_msg = {
    message = { role = "user", content = "Hello" },
    uuid = "uuid-123",
    provider = "claude", 
    tool_use_logs = {},
    tool_use_store = {},
    timestamp = "2023-01-01T00:00:00Z",
    state = "generated",
}

---@class avante.UIMessage (NEW)  
-- Pure UI concerns
local ui_msg = {
    uuid = "uuid-123", -- Reference to ModelMessage
    displayed_content = "Formatted content",
    visible = true,
    is_dummy = false,
    ui_cache = {},
    computed_lines = nil,
    last_rendered_at = 0,
}
```

## Core Components

### 1. ModelMessage (`lua/avante/model_message.lua`)

Responsible for:
- Core LLM message data (role, content)
- Provider metadata (provider, model)
- Tool execution (tool_use_logs, tool_use_store)
- Message lifecycle (state, timestamp)
- Conversation context (turn_id, selected_code)

```lua
local ModelMessage = require("avante.model_message")

-- Create new ModelMessage
local msg = ModelMessage:new("user", "Hello world", {
    provider = "claude",
    model = "claude-3-sonnet",
    is_user_submission = true
})

-- Check for tool usage
if msg:is_tool_use() then
    local tool_use = msg:get_tool_use()
    print("Tool:", tool_use.name, "ID:", tool_use.id)
end
```

### 2. UIMessage (`lua/avante/ui_message.lua`)

Responsible for:
- Display formatting and content
- Visibility and interaction state  
- UI-specific caching and optimization
- Rendering metadata

```lua
local UIMessage = require("avante.ui_message")

-- Create new UIMessage
local ui_msg = UIMessage:new("uuid-123", {
    displayed_content = "Custom display",
    visible = true
})

-- Manage UI state
ui_msg:set_calling(true)
ui_msg:set_displayed_content("Updated content")

-- Cache management
if ui_msg:is_cache_valid(model_timestamp) then
    local lines = ui_msg:get_cached_lines()
    -- Use cached rendering
else
    -- Re-render and cache
    ui_msg:update_cache(new_lines)
end
```

### 3. MessageConverter (`lua/avante/message_converter.lua`)

Provides conversion between message types:

```lua
local MessageConverter = require("avante.message_converter")

-- Convert ModelMessage to UIMessage
local ui_msg = MessageConverter.to_ui_message(model_msg)

-- Convert legacy HistoryMessage to separated types
local model_msg = MessageConverter.history_to_model_message(hist_msg)
local ui_msg = MessageConverter.history_to_ui_message(hist_msg)

-- Batch conversion
local ui_messages = MessageConverter.batch_to_ui_messages(model_messages)

-- Validate conversion integrity
local success, error_msg = MessageConverter.validate_conversion(model_msg, ui_msg)
```

### 4. History Management (`lua/avante/history/init.lua`)

Updated with dual storage pattern:

```lua
local History = require("avante.history.init")

-- Load legacy messages into separated stores
History.load_from_history_messages(history_messages)

-- Add new messages
History.add_model_message(model_msg)  
History.add_ui_message(ui_msg)

-- Retrieve messages
local model_msg = History.get_model_message(uuid)
local ui_messages = History.get_visible_ui_messages()

-- Convert back for compatibility
local history_messages = History.to_history_messages()

-- Access stores directly (for providers/rendering)
local model_store = History.get_model_store()
local ui_store = History.get_ui_store()
```

### 5. Updated Rendering (`lua/avante/history/render.lua`)

New rendering functions that work with separated architecture:

```lua
local Render = require("avante.history.render")

-- Render using separated architecture (NEW)
local lines = Render.render_separated_messages(ui_messages, model_store)

-- Render single message with caching
local message_lines = Render.render_single_message(ui_msg, model_msg, model_store)

-- Legacy rendering still supported
local lines = Render.message_to_lines(history_message, all_messages)
```

## Usage Patterns

### For LLM Provider Integration

Providers continue to work with ModelMessage data:

```lua
-- Provider receives ModelMessage data
local function provider_integration(model_messages)
    local llm_messages = {}
    for _, model_msg in ipairs(model_messages) do
        -- Access pure LLM data
        table.insert(llm_messages, model_msg.message)
        -- Access tool context
        if model_msg.tool_use_logs then
            -- Handle tool logs
        end
    end
    return llm_messages
end
```

### For UI Rendering

Rendering system works with UIMessage:

```lua
-- Rendering uses UIMessage for display
local function render_conversation(ui_messages, model_store)
    local lines = {}
    for _, ui_msg in ipairs(ui_messages) do
        if ui_msg.visible then
            -- Check cache first
            local cached = ui_msg:get_cached_lines(model_store[ui_msg.uuid].timestamp)
            if cached then
                vim.list_extend(lines, cached)
            else
                -- Render and cache
                local model_msg = model_store[ui_msg.uuid]
                local message_lines = render_message(ui_msg, model_msg)
                ui_msg:update_cache(message_lines)
                vim.list_extend(lines, message_lines)
            end
        end
    end
    return lines
end
```

### Migration from Legacy Code

For code using the old HistoryMessage:

```lua
-- OLD CODE
local function process_messages(history_messages)
    for _, msg in ipairs(history_messages) do
        if msg.message.role == "user" then
            -- Process user message
            local content = msg.message.content
            local is_visible = msg.visible
        end
    end
end

-- NEW CODE  
local function process_messages_separated()
    local model_messages = History.get_all_model_messages()
    local ui_store = History.get_ui_store()
    
    for _, model_msg in ipairs(model_messages) do
        if model_msg.message.role == "user" then
            -- Process user message (LLM concerns)
            local content = model_msg.message.content
            
            -- Access UI state separately
            local ui_msg = ui_store[model_msg.uuid]
            local is_visible = ui_msg.visible
        end
    end
end
```

## Benefits

### 1. Separation of Concerns
- LLM logic isolated from UI rendering
- Independent development and testing
- Clear boundaries between data types

### 2. Performance Optimization
- UI caching without affecting LLM data
- Lazy rendering with cache validation
- Independent optimization of each concern

### 3. Maintainability  
- Focused classes with single responsibilities
- Easier to understand and modify
- Type safety through Lua annotations

### 4. Testability
- Unit test each message type in isolation
- Mock UI concerns when testing LLM logic
- Validate conversion integrity

## Backward Compatibility

The implementation maintains backward compatibility through:

1. **Legacy Message Support**: Original `avante.HistoryMessage` types still work
2. **Conversion Layer**: Seamless conversion between old and new formats  
3. **Adapter Pattern**: Existing provider integrations continue to work
4. **Gradual Migration**: Code can be migrated incrementally

## Best Practices

### 1. Use Appropriate Types
```lua
-- For LLM processing
local model_msg = ModelMessage:new("user", content, { provider = "claude" })

-- For UI display
local ui_msg = MessageConverter.to_ui_message(model_msg)
ui_msg:set_displayed_content("Formatted content")
```

### 2. Leverage Caching
```lua
-- Check cache before rendering
if ui_msg:is_cache_valid(model_msg.timestamp) then
    return ui_msg:get_cached_lines()
else
    local lines = expensive_rendering(model_msg)
    ui_msg:update_cache(lines)
    return lines
end
```

### 3. Validate Conversions
```lua
local ui_msg = MessageConverter.to_ui_message(model_msg)
local success, error_msg = MessageConverter.validate_conversion(model_msg, ui_msg)
if not success then
    error("Conversion failed: " .. error_msg)
end
```

### 4. Use Store References
```lua
-- Get direct store access for performance
local model_store = History.get_model_store()
local ui_store = History.get_ui_store()

-- Avoid repeated lookups in loops
for uuid, ui_msg in pairs(ui_store) do
    local model_msg = model_store[uuid]
    -- Process efficiently
end
```

## Testing

The implementation includes comprehensive tests:

- `tests/message_converter_spec.lua` - Conversion logic testing
- `tests/model_message_spec.lua` - ModelMessage functionality  
- `tests/ui_message_spec.lua` - UIMessage functionality
- `tests/history_separated_spec.lua` - History management testing

Run tests with your preferred Lua testing framework to ensure functionality.

## Future Enhancements

This architecture enables future improvements:

1. **Advanced UI Caching**: More sophisticated caching strategies
2. **Streaming Optimizations**: Better handling of real-time message updates  
3. **Provider Isolation**: Complete isolation of different LLM providers
4. **Performance Monitoring**: Independent performance metrics for UI vs LLM
5. **Plugin Extensions**: Easier extension points for UI customization