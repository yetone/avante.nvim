# MCP Tools Lazy Loading

This document describes the lazy loading mechanism for MCP tools in avante.nvim.

## Overview

The MCP (Model Context Protocol) integration in avante.nvim provides access to a wide range of tools from various MCP servers. However, including detailed descriptions of all these tools in the system prompt can consume a significant number of tokens, which may:

1. Reduce the context available for actual conversation
2. Increase the cost of API calls to LLM providers
3. Slow down the initial loading of the conversation

To address these issues, avante.nvim implements a lazy loading mechanism for MCP tools. This mechanism provides summarized tool descriptions initially and allows the LLM to request detailed information about specific tools when needed.

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
    "server_name": "Name of the MCP server that provides the tool",
    "tool_name": "Name of the tool to load"
  }
}
```

This function:

- Validates the input parameters
- Checks if the tool details are already cached
- Requests detailed tool information from the specified MCP server
- Returns the complete tool description, including all parameters and usage examples

### 3. Caching

To avoid redundant requests, the `load_mcp_tool` function caches the detailed tool descriptions. This ensures that subsequent requests for the same tool are served from the cache, improving performance.

## Configuration

The lazy loading mechanism can be configured in the mcphub.nvim plugin:

```lua
require("mcphub").setup({
  lazy_loading = {
    enabled = true,  -- Enable or disable lazy loading
    cache_size = 50, -- Maximum number of tools to cache
  }
})
```

## Benefits

- **Reduced Token Usage**: By providing summarized tool descriptions initially, the token count of the system prompt is significantly reduced.
- **Improved Performance**: The LLM can load detailed information only for the tools it actually needs to use.
- **Better Context Utilization**: More context is available for the actual conversation, improving the quality of responses.

## When to Use Detailed Tool Information

The LLM should request detailed tool information when:

- The summarized description is not sufficient to understand a tool's functionality
- Specific parameter details or usage examples are needed
- Complex tools with multiple options need to be used
- Edge cases or advanced features need to be explored

## Implementation Notes

The lazy loading mechanism consists of several components:

1. **Tool Summarizer** (`lua/avante/mcp/summarizer.lua`): Extracts concise information from MCP tool descriptions.
2. **Load Tool Function** (`lua/avante/llm_tools/load_mcp_tool.lua`): Allows the LLM to request detailed tool information.
3. **System Prompt Update** (`lua/avante/templates/_mcp-lazy-loading.avanterules`): Explains the lazy loading mechanism to the LLM.
4. **MCP Integration** (in mcphub.nvim): Updates the MCP integration to support lazy loading of tools.

## Future Improvements

Potential future enhancements to the lazy loading mechanism include:

- Smart preloading of frequently used tools
- More advanced summarization algorithms
- Tool usage statistics to improve caching strategies
- Dynamic adjustment of summary length based on token budget
