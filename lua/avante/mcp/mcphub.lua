--[[
MCPHub Integration Module
Provides integration between avante.nvim and mcphub.nvim with lazy loading support.
]]

local M = {}
local Config = require("avante.config")

-- Add a registry to track which tools have been requested
M._requested_tools = M._requested_tools or {}

M._available_to_request = M._available_to_request or {}

-- Function to register a tool as requested
-- Returns true if successful, false if not
function M.register_requested_tool(server_name, tool_name)
  local key = server_name .. ":" .. tool_name
  if M._available_to_request[key] then
    M._requested_tools[key] = true
    return true
  end
  return false
end

-- Function to register a tool as availale
function M.register_available_tool(server_name, tool_name)
  local key = server_name .. ":" .. tool_name
  M._available_to_request[key] = true
end


-- Function to check if a tool has been requested
function M.is_tool_requested(server_name, tool_name)
  local key = server_name .. ":" .. tool_name
  return M._requested_tools[key] == true
end

-- Function to reset requested tools (useful for testing)
function M.reset_requested_tools()
  M._requested_tools = {}
end

function M.always_eager()
    -- Define critical tools that should always be eagerly loaded regardless of user configuration
    local critical_tools = {
      "think",
      "attempt_completion",
      "load_mcp_tool",
      "use_mcp_tool",
      "add_todos",
      "update_todo_status",
      "list_tools",
    }

    -- Merge user configuration with critical tools
    local user_always_eager = Config.lazy_loading.always_eager or {}
    local always_eager = {}

    -- Add all critical tools to the always_eager list
    for _, tool_name in ipairs(critical_tools) do
      always_eager[tool_name] = true
    end

    -- Add user-configured always_eager tools
    for _, tool_name in ipairs(user_always_eager) do
      always_eager[tool_name] = true
    end
    return always_eager
end

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
    local LLMTools = require("avante.llm_tools")

    -- Get all MCP servers
    local servers = {}
    -- Use the correct API method as per mcphub documentation
    if hub.get_servers and type(hub.get_servers) == "function" then
      -- Use method-style call to get non-disabled servers
      servers = hub:get_servers(false)
    end
    local summarized_prompt = "\n# MCP SERVERS\n\n"

    -- Add description of the MCP system
    summarized_prompt = summarized_prompt .. [[The Model Context Protocol (MCP) enables communication between the system and locally running MCP servers that provide additional tools and resources to extend your capabilities.

    ## Connected MCP Servers

    When a server is connected, you can use the server's tools via the `use_mcp_tool` tool, and access the server's resources via the `access_mcp_resource` tool.
    Note: Server names are case sensitive and you should always use the exact full name like `Firecrawl MCP` or `src/user/main/time-mcp` etc

    ]]

    -- Get the built-in tools using get_tools function with for_system_prompt=true
    local built_in_tools = LLMTools.get_tools("", {}, true)

    -- Add built-in tools section to the prompt
    summarized_prompt = summarized_prompt .. "## Built-in Tools\n\n"
    for _, tool in ipairs(built_in_tools) do
      -- Skip tools that don't have a name
      if tool.name then
        local summarized_tool = Summarizer.summarize_tool(tool)
        -- Add server_name to the tool description
        if summarized_tool.description then
          summarized_tool.description = summarized_tool.description ..
          " (Server: avante)"
          summarized_prompt = summarized_prompt .. "- **" .. tool.name .. "**: " ..
          (summarized_tool.description or "No description") .. "\n\n"
          M.register_available_tool("avante", tool.name)

        end

      end
    end

    summarized_prompt = summarized_prompt .. "## MCP Server Details\n\n"

    -- Get all tools from the hub
    local all_tools = {}
    if hub.get_tools and type(hub.get_tools) == "function" then
      all_tools = hub:get_tools()
    end

    -- Group tools by server
    local server_tools_map = {}
    for _, tool in ipairs(all_tools) do
      local server_name = tool.server_name
      if server_name then
        server_tools_map[server_name] = server_tools_map[server_name] or {}
        table.insert(server_tools_map[server_name], tool)
      end
    end

    -- For each server, summarize its information and tools
    for _, server in ipairs(servers) do
      -- Skip servers that don't have a name
      if server.name then
        local server_name = server.name
        local server_resources = server.capabilities and server.capabilities.resources or {}
        local server_tools = server_tools_map[server_name] or {}

        -- Add server information to the prompt
        summarized_prompt = summarized_prompt .. "### " .. server_name .. "\n\n"
        summarized_prompt = summarized_prompt .. (server.description or "No description available") .. "\n\n"

        -- Summarize the tools and add server_name to each tool
        if #server_tools > 0 then
          summarized_prompt = summarized_prompt .. "#### Available Tools\n\n"

          for _, tool in ipairs(server_tools) do
            -- Skip tools that don't have a name
            if tool.name then
              local summarized_tool = Summarizer.summarize_tool(tool)
              -- Add server_name to the tool description
              if summarized_tool.description then
                summarized_tool.description = summarized_tool.description ..
                " (Server: " .. server_name .. ")"
                summarized_prompt = summarized_prompt .. "- **" .. tool.name .. "**: " ..
                summarized_tool.description .. "\n\n"
                M.register_available_tool(server.name, tool.name)
              end

            end
          end
        end

        -- Add resources information
        if #server_resources > 0 then
          summarized_prompt = summarized_prompt .. "#### Available Resources\n\n"

          for _, resource in ipairs(server_resources) do
            -- Skip resources that don't have a URI
            if resource.uri then
              local mime = resource.mime or "unknown"
              local description = resource.description or "No description available"

              summarized_prompt = summarized_prompt .. "- **" .. resource.uri .. "** (" .. mime .. ")\n  " ..
              description .. "\n\n"
            end
          end
        end

        summarized_prompt = summarized_prompt .. "\n"
      end
    end

    -- Add information about disabled servers if any
    local disabled_servers = {}
    -- Use the correct API method as per mcphub documentation
    if hub.get_servers and type(hub.get_servers) == "function" then
      -- Get all servers including disabled ones
      local all_servers = hub:get_servers(true)
      -- Filter out active servers to get only disabled ones
      for _, server in ipairs(all_servers) do
        if server.disabled then
          table.insert(disabled_servers, server)
        end
      end
    end
    if #disabled_servers > 0 then
      summarized_prompt = summarized_prompt .. "## Disabled MCP Servers\n\n"
      summarized_prompt = summarized_prompt .. "When a server is disabled, it will not be able to provide tools or resources. "
      summarized_prompt = summarized_prompt .. "You can start one of the following disabled servers by using the `toggle_mcp_server` tool on `mcphub` MCP Server if it is connected using `use_mcp_tool`\n\n"

      for _, server in ipairs(disabled_servers) do
        if server.name then
          summarized_prompt = summarized_prompt .. "### " .. server.name .. " (Disabled)\n\n"
        end
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


-- Function to determine if a tool should be included based on lazy loading configuration
---@param tool AvanteLLMTool The tool to check
---@return boolean True if the tool should be included, false otherwise
function M.should_include_tool(server_name, tool_name)
  return not Config.lazy_loading.enabled or
  M.always_eager()[tool_name] or M.is_tool_requested(server_name, tool_name)
end
return M
