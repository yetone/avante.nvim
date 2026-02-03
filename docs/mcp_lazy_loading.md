# MCP Tools Lazy Loading

This document describes the lazy loading feature for MCP tools in avante.nvim, which optimizes token usage and improves performance.

## Overview

The MCP (Model Context Protocol) Lazy Loading feature provides summarized tool descriptions initially and allows the LLM to request detailed information about specific tools when needed. This approach:

1. Reduces token usage in system prompts
2. Provides more context for actual conversation
3. Improves performance by loading tool details on demand

## How It Works

When lazy loading is enabled:

1. Each tool description is summarized to include only the essential information in the system prompt
2. Only critical tools (and tools listed in `config.lazy_loading.always_eager`) are included in the tools section of the prompt by default
3. Other tools are only included in the tools section if they've been specifically requested via `load_mcp_tool`
4. When the LLM requests detailed information about a specific tool using the `load_mcp_tool` function, that tool is:
   - Added to the registry of requested tools
   - Included in the tools section of subsequent prompts
   - Provided with its full description

## Configuration

Lazy loading is disabled by default. You can enable it in your avante.nvim setup:

```lua
require('avante').setup({
  lazy_loading = {
    -- Whether to enable lazy loading for built-in avante MCP tools
    enabled = true,
    -- List of tools that should always be loaded eagerly (not lazily)
    -- These tools should always be available without requiring a separate load
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

If you have mcphub enabled, the lazy loader integrates with MCPHub to provide summarized tool descriptions for all connected MCP servers. The integration:

1. Gets all active MCP servers from MCPHub
2. Summarizes the tools for each server
3. Adds server information to each tool description
4. Provides a structured system prompt with all the summarized tools

This integration ensures that the LLM has access to all the tools provided by MCPHub while minimizing token usage.
