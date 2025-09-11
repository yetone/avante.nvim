--[[
MCPHub Integration Module
Provides integration between avante.nvim and mcphub.nvim with lazy loading support.
]]

local M = {}
local Config = require("avante.config")

-- Function to get MCPHub prompt with lazy loading support
---@return string
function M.get_system_prompt()
  -- Try to load mcphub
  local ok, mcphub = pcall(require, "mcphub")
  if not ok then
    return "" -- MCPHub not available
  end

  -- Get MCPHub instance
  local hub = mcphub.get_hub_instance()
  if not hub then
    return ""
  end

  -- Check if lazy loading is enabled
  if Config.lazy_loading and Config.lazy_loading.enabled then
    -- Lazy load the summarizer module
    local Summarizer = require("avante.mcp.summarizer")

    -- Get all MCP servers
    local servers = {}
    -- Handle both method-style and function-style calls
        local get_active_servers = hub.get_active_servers
        if type(get_active_servers) == "function" then
          servers = get_active_servers(hub)
        elseif type(get_active_servers) == "table" then
          servers = get_active_servers
    end
    local summarized_prompt = "\n# MCP SERVERS\n\n"

    -- Add description of the MCP system
    summarized_prompt = summarized_prompt .. [[The Model Context Protocol (MCP) enables communication between the system and locally running MCP servers that provide additional tools and resources to extend your capabilities.

## Connected MCP Servers

When a server is connected, you can use the server's tools via the `use_mcp_tool` tool, and access the server's resources via the `access_mcp_resource` tool.
Note: Server names are case sensitive and you should always use the exact full name like `Firecrawl MCP` or `src/user/main/time-mcp` etc

]]

    -- For each server, get its tools and summarize them
    for _, server in ipairs(servers) do
      local server_name = server.name
      local server_tools = server.tools or {}
      local server_resources = server.resources or {}

      -- Add server information to the prompt
      summarized_prompt = summarized_prompt .. "### " .. server_name .. "\n\n"
      summarized_prompt = summarized_prompt .. server.description .. "\n\n"

      -- Summarize the tools and add server_name to each tool
      if #server_tools > 0 then
        summarized_prompt = summarized_prompt .. "#### Available Tools\n\n"

        for _, tool in ipairs(server_tools) do
          local summarized_tool = Summarizer.summarize_tool(tool)
          -- Add server_name to the tool description
          if summarized_tool.description then
            summarized_tool.description = summarized_tool.description ..
              " (Server: " .. server_name .. ", use load_mcp_tool to get full details)"
          end

          summarized_prompt = summarized_prompt .. "- **" .. tool.name .. "**: " ..
            (summarized_tool.description or "No description") .. "\n\n"
        end
      end

      -- Add resources information
      if #server_resources > 0 then
        summarized_prompt = summarized_prompt .. "#### Available Resources\n\n"

        for _, resource in ipairs(server_resources) do
          summarized_prompt = summarized_prompt .. "- **" .. resource.uri .. "** (" .. resource.mime .. ")\n  " ..
            resource.description .. "\n\n"
        end
      end

      summarized_prompt = summarized_prompt .. "\n"
    end

    -- Add information about disabled servers if any
    local disabled_servers = {}
    -- Handle both method-style and function-style calls
    local get_disabled_servers = hub.get_disabled_servers
    if type(get_disabled_servers) == "function" then
      disabled_servers = get_disabled_servers(hub)
    elseif type(get_disabled_servers) == "table" then
      disabled_servers = get_disabled_servers
    end
    if #disabled_servers > 0 then
      summarized_prompt = summarized_prompt .. "## Disabled MCP Servers\n\n"
      summarized_prompt = summarized_prompt .. "When a server is disabled, it will not be able to provide tools or resources. "
      summarized_prompt = summarized_prompt .. "You can start one of the following disabled servers by using the `toggle_mcp_server` tool on `mcphub` MCP Server if it is connected using `use_mcp_tool`\n\n"

      for _, server in ipairs(disabled_servers) do
        summarized_prompt = summarized_prompt .. "### " .. server.name .. " (Disabled)\n\n"
      end
    end

    -- Add instructions about how to use load_mcp_tool
    summarized_prompt = summarized_prompt .. [[## Examples

### `use_mcp_tool`

When you need to call a tool on an MCP Server, use the `use_mcp_tool` tool:

Pseudocode:

use_mcp_tool
  server_name: string (One of the available server names)
  tool_name: string (name of the tool in the server to call)
  tool_input: object (Arguments for the tool call)

### `access_mcp_resource`

When you need to access a resource from a MCP Server, use the `access_mcp_resource` tool:

Pseudocode:

access_mcp_resource
  server_name: string (One of the available server names)
  uri: string (uri for the resource)

### Toggling a MCP Server

When you need to start a disabled MCP Server or vice-versa, use the `toggle_mcp_server` tool on `mcphub` MCP Server using `use_mcp_tool`:

CRITICAL: You need to use the `use_mcp_tool` tool to call the `toggle_mcp_server` tool on `mcphub` MCP Server when `mcphub` server is "Connected" else ask the user to enable `mcphub` server.

Pseudocode:

use_mcp_tool
  server_name: "mcphub"
  tool_name: "toggle_mcp_server"
  tool_input:
    server_name: string (One of the available server names to start or stop)
    action: string (one of `start` or `stop`)
]]

    return summarized_prompt
  end

  -- If lazy loading is disabled, return the original prompt
  -- Handle both method-style and function-style calls
  local get_active_servers_prompt = hub.get_active_servers_prompt
  if type(get_active_servers_prompt) == "function" then
    return get_active_servers_prompt(hub)
  elseif type(get_active_servers_prompt) == "table" then
    return get_active_servers_prompt
  else
    return ""
  end
end

-- Function to get custom tools for MCPHub
---@return table[]
function M.get_custom_tools()
  local ok, mcphub_ext = pcall(require, "mcphub.extensions.avante")
  if not ok then
    return {}
  end

  -- If lazy loading is enabled, summarize the tools
  if Config.lazy_loading and Config.lazy_loading.enabled then
    local Summarizer = require("avante.mcp.summarizer")
    local tool = mcphub_ext.mcp_tool()

    -- Summarize the tool
    local summarized_tool = Summarizer.summarize_tool(tool)

    -- Add server information to the description
    if summarized_tool.description then
      summarized_tool.description = summarized_tool.description .. " (Server: avante, use load_mcp_tool to get full details)"
    end

    return {summarized_tool}
  end

  return {mcphub_ext.mcp_tool()}
end

return M
