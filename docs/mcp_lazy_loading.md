# MCP Tools Lazy Loading
# MCP Lazy Loading

This document describes the lazy loading feature for MCP tools in avante.nvim, which optimizes token usage and improves performance.

## Overview

The MCP (Model Context Protocol) Lazy Loading feature provides summarized tool descriptions initially and allows the LLM to request detailed information about specific tools when needed. This approach:

1. Reduces token usage in system prompts
2. Provides more context for actual conversation
3. Improves performance by loading tool details on demand

## How It Works

When lazy loading is enabled:

1. Each tool description is summarized to include only the essential information in the system prompt
2. Only critical tools (configured in `lazy_loading.always_eager`) are included in the tools section of the prompt by default
3. Other tools are only included in the tools section if they've been specifically requested via `load_mcp_tool`
4. When the LLM requests detailed information about a specific tool using the `load_mcp_tool` function, that tool is:
   - Added to the registry of requested tools
   - Included in the tools section of subsequent prompts
   - Provided with its full description

## Configuration

Lazy loading is enabled by default. You can configure it in your avante.nvim setup:

```lua
require('avante').setup({
  lazy_loading = {
    -- Whether to enable lazy loading for built-in avante MCP tools
    enabled = true,
    -- List of tools that should always be loaded eagerly (not lazily)
    -- These tools are critical and should always be available without requiring a separate load
    always_eager = {
      "write_file",       -- If you want write_file to be always eager
    },
  },
})
```

## Using the `load_mcp_tool` Function

The LLM can request detailed information about a specific tool using the `load_mcp_tool` function:

```json
{
  "name": "load_mcp_tool",
  "parameters": {
    "server_name": "Name of the MCP server that provides the tool (e.g., \"neovim\", \"mcphub\", or \"avante\" for built-in tools)",
    "tool_name": "Name of the tool to load"
  }
}
```

This will return the complete tool description, including full parameter details and usage examples.

## MCPHub Integration

avante.nvim integrates with MCPHub to provide summarized tool descriptions for all connected MCP servers. The integration:

1. Gets all active MCP servers from MCPHub
2. Summarizes the tools for each server
3. Adds server information to each tool description
4. Provides a structured system prompt with all the summarized tools

This integration ensures that the LLM has access to all the tools provided by MCPHub while minimizing token usage.

This document describes the lazy loading mechanism for MCP tools in avante.nvim.

## Overview

The MCP (Model Context Protocol) integration in avante.nvim provides access to a wide range of tools from various MCP servers. Additionally, avante.nvim includes many built-in tools that provide core functionality. However, including detailed descriptions of all these tools in the system prompt can consume a significant number of tokens, which may:

1. Reduce the context available for actual conversation
2. Increase the cost of API calls to LLM providers
3. Slow down the initial loading of the conversation

To address these issues, avante.nvim implements a lazy loading mechanism for both MCP server tools and built-in avante tools. This mechanism provides summarized tool descriptions initially and allows the LLM to request detailed information about specific tools when needed.

## How It Works

### 1. Tool Summarization

When the system prompt is generated, all MCP tools are summarized using the `avante.mcp.summarizer` module. This module:

- Extracts the first sentence from each description
- Preserves the essential information while reducing verbosity
- Maintains the tool name, type, and parameter names

### 2. On-Demand Loading

When the LLM needs more detailed information about a specific tool, it can use the `load_mcp_tool` function:

```json
{
  "name": "load_mcp_tool",
  "parameters": {
    "server_name": "Name of the MCP server that provides the tool. Use \"avante\" for built-in avante tools.",
    "tool_name": "Name of the tool to load"
  }
}
```

This function:

- Validates the input parameters
- Checks if the tool details are already cached
- For MCP server tools: Requests detailed tool information from the specified MCP server
- For built-in avante tools: Loads the tool module from avante.nvim when "avante" is specified as the server_name
- Returns the complete tool description, including all parameters and usage examples

### 3. Caching

To avoid redundant requests, the `load_mcp_tool` function caches the detailed tool descriptions. This ensures that subsequent requests for the same tool are served from the cache, improving performance.

## Configuration

The lazy loading mechanism is built into avante.nvim and is enabled by default for both MCP server tools and built-in avante tools.

### Built-in Avante Tools Configuration

For built-in avante tools, you can configure which tools should always be loaded eagerly (not lazily) using the `lazy_loading` configuration in your avante.nvim setup:

```lua
require("avante").setup({
  -- Other configuration options...

  lazy_loading = {
    -- Whether to enable lazy loading for built-in avante MCP tools
    enabled = true,
    -- List of tools that should always be loaded eagerly (not lazily)
    -- These tools are critical and should always be available without requiring a separate load
    always_eager = {
      "think",             -- Thinking tool should always be available
      "attempt_completion", -- Completion tool should always be available
      "load_mcp_tool",      -- The tool itself needs to be available to load other tools
      "add_todos",          -- Task management tools should be always available
      "update_todo_status", -- Task management tools should be always available
      -- Add any other tools you want to always load eagerly
    },
  },

  behaviour = {
    -- Other behaviour options...

    -- When true, MCP tool summarizer will only include name and description (no input/output schema)
    -- This provides an even more concise representation of tools to further reduce token usage
    mcp_extra_concise = false,
  },
})
```

By default, the following tools are always loaded eagerly:
- `think`
- `attempt_completion`
- `load_mcp_tool`
- `add_todos`
- `update_todo_status`

All other built-in tools will be summarized and lazily loaded when needed.

### Integration with mcphub.nvim

The lazy loading mechanism in avante.nvim attempts to interact with mcphub.nvim to retrieve detailed tool information from MCP servers. The basic functionality of lazy loading will work with avante.nvim's internal implementation, regardless of how mcphub.nvim is configured.

## Benefits

- **Reduced Token Usage**: By providing summarized tool descriptions initially and only including critical tools in the tools section by default, the token count of the prompt is significantly reduced.
- **Improved Performance**: The LLM can load detailed information and access only the tools it actually needs to use.
- **Better Context Utilization**: More context is available for the actual conversation, improving the quality of responses.
- **Optimized Tool Management**: Tools are only included in the tools section of the prompt when they're either critical or specifically requested, preventing tool overload.

## When to Use Detailed Tool Information

The LLM should request detailed tool information when:

- The summarized description is not sufficient to understand a tool's functionality
- Specific parameter details or usage examples are needed
- Complex tools with multiple options need to be used
- Edge cases or advanced features need to be explored

## Implementation Notes

The lazy loading mechanism consists of several components:

1. **Tool Summarizer** (`lua/avante/mcp/summarizer.lua`): Extracts concise information from MCP tool descriptions to reduce token usage.
2. **Load Tool Function** (`lua/avante/llm_tools/load_mcp_tool.lua`): Allows the LLM to request detailed tool information when needed.
3. **System Prompt Update** (`lua/avante/templates/_mcp-lazy-loading.avanterules`): Explains the lazy loading mechanism to the LLM.
4. **MCP Integration**: The `load_mcp_tool` function communicates with mcphub.nvim to retrieve detailed tool information on demand.

## Future Improvements

Potential future enhancements to the lazy loading mechanism include:

- Smart preloading of frequently used tools
- More advanced summarization algorithms
- Tool usage statistics to improve caching strategies
- Dynamic adjustment of summary length based on token budget
