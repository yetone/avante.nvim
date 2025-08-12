# UUID
67d1d765-5820-4dbd-89ff-56b1b5c53a18

# Trigger
Avante.nvim history storage architecture, history refactoring, ChatHistory data model

# Content
Avante.nvim uses a dual-format history storage system with the following key components:

## Current Architecture
- **Storage Path**: `~/.local/state/avante/projects/{project_name}/history/` with JSON files
- **Data Models**: `ChatHistoryEntry` (legacy) and `HistoryMessage` (modern) coexist
- **File Organization**: Individual JSON files per conversation with metadata.json for latest tracking
- **Tool Processing**: Complex tool invocation tracking with synthetic message generation

## Key Files and Responsibilities
- `lua/avante/history/init.lua`: Core history logic, tool processing, message conversion
- `lua/avante/history/message.lua`: HistoryMessage class with synthetic message creation
- `lua/avante/history/helpers.lua`: Utility functions for message type detection
- `lua/avante/path.lua`: Storage path management and file operations
- `lua/avante/history_selector.lua`: UI for history selection and management

## Storage Structure
```
~/.local/state/avante/
└── projects/
    └── {project_dirname}/
        └── history/
            ├── metadata.json          # Latest filename tracking
            ├── 0.json                 # Conversation files
            ├── 1.json
            └── ...
```

## Tool Processing Logic
The system maintains sophisticated tool interaction tracking:
- **HistoryToolInfo**: Maps tool IDs to tool invocation details (kind, use, result, path)
- **HistoryFileInfo**: Tracks file state across multiple tool operations (last_tool_id, edit_tool_id)
- **collect_tool_info()**: Two-phase processing to link tool invocations with results
- **Synthetic Messages**: Auto-generated post-edit views and diagnostics for conversation context
- **Tool Chain Optimization**: Converts old tool interactions to text summaries to reduce context size

## Migration Considerations
- Legacy `ChatHistoryEntry.entries[]` format needs conversion to `HistoryMessage.messages[]`
- Tool invocation chains require careful preservation during migration
- File numbering system and metadata tracking must be maintained
- Tool state tracking logic (`collect_tool_info`, synthetic message generation) must be preserved
- Backward compatibility essential for existing installations

This architecture serves as the foundation for refactoring to a unified, more efficient storage system while preserving the complex tool interaction logic that enables AI-assisted code editing.