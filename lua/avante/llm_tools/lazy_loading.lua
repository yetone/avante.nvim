--[[
MCP Lazy Loading module
Implements the lazy loading feature for MCP tools. See top-level README
]]

local M = {}
local Config = require("avante.config")

-- Add a registry to track which tools have been requested
M._requested_tools = M._requested_tools or {}

M._available_to_request = M._available_to_request or {}

M._tools_to_collect = M._tools_to_collect or {}

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
  M._available_to_request[key] = { server_name = server_name, name = tool_name }
end

function M.available_tools_with_name(tool_name)
  local available_tools = {}
  for _, tool in pairs(M._available_to_request) do
    if tool.name == tool_name then
      available_tools[#available_tools+1] = tool
    end
  end
  return available_tools
end

function M.servers_with_available_tools_with_name_as_string(tool_name)
  local available_tools = M.available_tools_with_name(tool_name)
  local servers = ""
  for i = 1, #available_tools do
    local tool = available_tools[i]
    servers = servers .. tool.server_name
    if i < #available_tools then
      servers = servers .. ", "
    end
  end
  return servers
end

-- Add a tool to be collected by `generate_prompts`
-- to add to the list of tools in the middle of an LLM action
function M.register_tool_to_collect(tool)
  M._tools_to_collect[#M._tools_to_collect + 1] = tool
  -- print("\n\n Registering \n" .. vim.inspect(tool) .. "\n\n" .. vim.inspect(M._tools_to_collect) .. "\n")
end

--Append any tools to collect to the provided tools list.
--If they are already in the provided tools list, remove
--them from the list of tools to collect, to avoid unnecessary
--effort.
--Returns the extended list of tools
function M.add_loaded_tools(tools)
  -- Sometimes there are no tools needed (e.g. when running on_memory_summarize)
  if tools == nil then return tools end
  local tools_to_collect = M._tools_to_collect
  local tools_that_are_needed = {}
  M._tools_to_collect = {}
  for _, tool in ipairs(tools_to_collect) do
    local matching_tool = vim.iter(tools):find(function(tl) return tl.name == tool.name end)
    if matching_tool == nil then
      -- In this case, we need to add it to tools *and* save it
      -- for later
      M.register_tool_to_collect(tool)
      tools_that_are_needed[#tools_that_are_needed + 1] = tool
    end
  end
  return vim.list_extend(tools, tools_that_are_needed)
end

-- Function to check if a tool has been requested
function M.is_tool_requested(server_name, tool_name)
  local key = server_name .. ":" .. tool_name
  return M._requested_tools[key] == true
end

-- Function to reset requested tools (useful for testing)
function M.reset_requested_tools() M._requested_tools = {} end

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
      "dispatch_agent",
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

function M.get_mcphub_server_hub()
  local ok, mcphub = pcall(require, "mcphub")
  if not ok then return nil end
  local hub = mcphub.get_hub_instance()
  if not hub then return nil end
  return hub
end

function M.get_mcphub_tools()
  local hub = M.get_mcphub_server_hub()
  if not hub then return nil end

  -- Get all tools from the hub
  local all_tools
  if hub.get_tools and type(hub.get_tools) == "function" then
    all_tools = hub:get_tools()
  else
    return nil
  end

  return all_tools
end

function M.get_mcphub_server_map()
  local hub = M.get_mcphub_server_hub()
  if not hub then return nil end

  -- Get all tools from the hub
  local all_tools = M.get_mcphub_tools()
  if not all_tools then return nil end

  -- Group tools by server
  local server_tools_map = {}
  for _, tool in ipairs(all_tools) do
    local server_name = tool.server_name
    if server_name then
      server_tools_map[server_name] = server_tools_map[server_name] or {}
      table.insert(server_tools_map[server_name], tool)
    end
  end
  return server_tools_map
end

function M.get_mcphub_tool(server_name, tool_name)
  -- Get all tools from the hub
  local all_tools = M.get_mcphub_tools()
  if not all_tools then return nil end
  local tool = vim.iter(all_tools):find(function(tl) return tl.name == tool_name and tl.server_name == server_name end)
  return tool
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
  if not hub then return "" end

  -- Check if lazy loading is enabled
  if Config.lazy_loading and Config.lazy_loading.enabled then
    -- Lazy load the summarizer module
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
    summarized_prompt = summarized_prompt
      .. [[The Model Context Protocol (MCP) enables communication between the system and locally running MCP servers that provide additional tools and resources to extend your capabilities.

    ## Connected MCP Servers

    When a server is connected, you can use the server's tools via the `use_mcp_tool` tool, and access the server's resources via the `access_mcp_resource` tool.
    Note: Server names are case sensitive and you should always use the exact full name like `Firecrawl MCP` or `src/user/main/time-mcp` etc

    ]]

    -- Get the built-in tools using get_tools function with for_system_prompt=true
    local built_in_tools = LLMTools._tools

    -- Add built-in tools section to the prompt
    summarized_prompt = summarized_prompt .. "## Built-in Tools\n\n"
    summarized_prompt = summarized_prompt
      .. "To use all the tools in this section, YOU MUST LOAD THEM USING load_mcp_tool "
    summarized_prompt = summarized_prompt
      .. "if you cannot see their spec in the tools section of the prompt. YOU CANNOT "
    summarized_prompt = summarized_prompt .. "access them by running use_mcp_tool. \n\n"
    for _, tool in ipairs(built_in_tools) do
      -- Skip tools that don't have a name
      if tool.name then
        local summarized_tool = M.summarize_tool(tool)
        -- Add server_name to the tool description
        if summarized_tool.description then
          summarized_tool.description = summarized_tool.description .. " (Server: avante)"
          summarized_prompt = summarized_prompt
            .. "- **"
            .. tool.name
            .. "**: "
            .. (summarized_tool.description or "No description")
            .. "\n\n"
          M.register_available_tool("avante", tool.name)
        end
      end
    end
    -- The in-built tool for mcphub
    M.register_available_tool("avante", "use_mcp_tool")

    summarized_prompt = summarized_prompt .. "## MCP Server Details\n\n"
    local server_tools_map = M.get_mcphub_server_map()

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
              local summarized_tool = M.summarize_tool(tool)
              -- Add server_name to the tool description
              if summarized_tool.description then
                summarized_tool.description = summarized_tool.description .. " (Server: " .. server_name .. ")"
                summarized_prompt = summarized_prompt
                  .. "- **"
                  .. tool.name
                  .. "**: "
                  .. summarized_tool.description
                  .. "\n\n"
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

              summarized_prompt = summarized_prompt
                .. "- **"
                .. resource.uri
                .. "** ("
                .. mime
                .. ")\n  "
                .. description
                .. "\n\n"
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
        if server.disabled then table.insert(disabled_servers, server) end
      end
    end
    if #disabled_servers > 0 then
      summarized_prompt = summarized_prompt .. "## Disabled MCP Servers\n\n"
      summarized_prompt = summarized_prompt
        .. "When a server is disabled, it will not be able to provide tools or resources. "
      summarized_prompt = summarized_prompt
        .. "You can start one of the following disabled servers by using the `toggle_mcp_server` tool on `mcphub` MCP Server if it is connected using `use_mcp_tool`\n\n"

      for _, server in ipairs(disabled_servers) do
        if server.name then summarized_prompt = summarized_prompt .. "### " .. server.name .. " (Disabled)\n\n" end
      end
    end

    -- Add instructions about how to use load_mcp_tool
    summarized_prompt = summarized_prompt
      .. [[## Examples

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

    CRITICAL: You must NOT use `use_mcp_tool` when the server is "avante". You must call the tool directly. If the tool
    spec is not available, load it with `load_mcp_tool`

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
  if not ok then return {} end

  -- If lazy loading is enabled, summarize the tools
  if Config.lazy_loading and Config.lazy_loading.enabled then
    local tool = mcphub_ext.mcp_tool()

    -- Summarize the tool
    local summarized_tool = M.summarize_tool(tool)

    -- Add server information to the description
    if summarized_tool.description then
      summarized_tool.description = summarized_tool.description
        .. " (Server: avante, use load_mcp_tool to get full details)"
    end

    return { summarized_tool }
  end

  return { mcphub_ext.mcp_tool() }
end

-- Function to determine if a tool should be included based on lazy loading configuration
---@param tool AvanteLLMTool The tool to check
---@return boolean True if the tool should be included, false otherwise
function M.should_include_tool(server_name, tool_name)
  if server_name == nil then
    server_name = "avante"  -- need to handle direct injection of tools with no server name by sidebar
  end
  return not Config.lazy_loading.enabled or
  M.always_eager()[tool_name] or M.is_tool_requested(server_name, tool_name)
end

---@param server_name string The name of the MCP server
---@param tool_use_input table The tool input containing the tool name to validate
---@param on_complete function The callback function to call with result or error
---@return boolean, string|nil Whether the tool is valid, and an optional error message
function M.validate_mcp_tool(tool_use_input, on_complete)
  local server_name = tool_use_input.server_name
  -- Validate the server is available
  local server_tools_map = M.get_mcphub_server_map()
  if not server_tools_map or not server_tools_map[server_name] then
    local error_msg = string.format("MCP server '%s' is not available. Please enable the server first.", server_name)
    if on_complete then on_complete(false, error_msg) end
    return false, error_msg
  end

  -- Check if the tool exists on the server
  local tool_exists = false
  for _, server_tool in ipairs(server_tools_map[server_name]) do
    if server_tool.name == tool_use_input.tool_name then
      tool_exists = true
      break
    end
  end

  if not tool_exists then
    local error_msg = string.format(
      "Tool '%s' is not on server '%s'. Did you mean one of these servers: "
        .. M.servers_with_available_tools_with_name_as_string(tool_use_input.tool_name)
        .. " ?",
      tool_use_input.tool_name,
      server_name
    ) .. "Don't forget to load the tool with load_mcp_tool if necessary!"
    if on_complete then
      on_complete(false, error_msg)
    end
    return false, error_msg
  end

  -- Validate the target tool has been loaded/requested
  if not M.should_include_tool(server_name, tool_use_input.tool_name) then
    local error_msg = string.format(
      "Tool '%s' on server '%s' has not been loaded. Please use load_mcp_tool to load this tool first.",
      tool_use_input.tool_name,
      server_name
    )
    if on_complete then on_complete(false, error_msg) end
    return false, error_msg
  end

  if on_complete then on_complete(true, nil) end
  return true, nil
end

---@param tools AvanteLLMTool[]
---@param tool_use AvanteLLMToolUse
---@param Config table
---@return boolean, string|nil
function M.check_tool_loading(tools, tool_use, Config)
  local server_name = tool_use.server_name or "avante"

  -- Sanity check to make sure the tool exists.
  local key = server_name .. ":" .. tool_use.name
  if not M._available_to_request[key] then
    local error_msg = "Tool '" .. tool_use.name .. "' is not on server '" .. server_name .. "'. " ..
      "Did you mean one of these servers: " .. M.servers_with_available_tools_with_name_as_string(tool_use.name) .. " ?" ..
      "Don't forget to load the tool with load_mcp_tool if necessary!"
    return false, error_msg
  end
  -- Special handling for use_mcp_tool
  if tool_use.name == "use_mcp_tool" then
    if not (tool_use.input and tool_use.input.server_name and tool_use.input.tool_name) then
      local error_msg = "Please check the spec of use_mcp_tool and provide the right input."
      return false, error_msg
    end
    local tool_input_server_name = tool_use.input.server_name
    if tool_input_server_name == "avante" then
      local error_msg = string.format(
        "Do not use 'use_mcp_tool' for any tool with the 'avante' server.  '%s' is a built-in tool and can be called directly.",
        tool_use.input.tool_name
      )
      return false, error_msg
    end
    -- Validate the MCP tool
    local result, err = M.validate_mcp_tool(tool_use.input, nil)
    if not result then return false, err end
  else
    -- Regular tool loading check
    if not M.should_include_tool(server_name, tool_use.name) then
      local error_msg = string.format(
        "Tool '%s' has not been loaded. Please use load_mcp_tool to load this tool first and then retry. "
          .. "Server: %s.",
        tool_use.name,
        server_name
      )
      return false, error_msg
    end
  end

  return true, nil
end

---@param description string The description to extract the first sentence from
---@return string The first sentence or a truncated version if no sentence end is found
function M.extract_first_sentence(description)
  if not description or description == "" then return "" end

  -- Special case: if the description contains a code block followed by a period
  -- e.g. "A description with code. `code block here`. Second sentence."
  -- We want to include the code block in the first sentence
  local code_block_pattern = "(`[^`]+`)"
  local with_code_blocks = description:match("^(.-%.)%s" .. code_block_pattern .. "%.")
  if with_code_blocks then
    local first_part = description:match("^(.-%.)%s")
    local code_block = description:match(code_block_pattern)
    if first_part and code_block then return first_part .. " " .. code_block .. "." end
  end

  -- Handle common abbreviations to avoid false sentence endings
  local desc = description
    :gsub("([Ee]%.g%.)", "%1___ABBR___")
    :gsub("([Ii]%.e%.)", "%1___ABBR___")
    :gsub("([Ee]tc%.)", "%1___ABBR___")

  -- Special handling for code blocks to ensure they don't get split
  -- First, extract code blocks to ensure they're preserved intact
  local code_blocks = {}
  local code_block_count = 0
  desc = desc:gsub("(`[^`]+`)", function(match)
    code_block_count = code_block_count + 1
    local placeholder = "___CODE_BLOCK_" .. code_block_count .. "___"
    code_blocks[placeholder] = match
    return placeholder
  end)

  -- Find the first sentence end, but make sure it's not within a code block
  local sentence_end = desc:find("[%.%?%!]%s")

  -- If no sentence end is found, take first 100 characters and add ellipsis
  if not sentence_end then
    if #description > 100 then
      return description:sub(1, 100) .. "..."
    else
      return description
    end
  end

  -- Extract the first sentence including the punctuation mark
  local first_sentence = desc:sub(1, sentence_end)

  -- Restore abbreviations
  first_sentence = first_sentence:gsub("___ABBR___", "")

  -- Restore code blocks
  for placeholder, code_block in pairs(code_blocks) do
    first_sentence = first_sentence:gsub(placeholder, code_block)
  end

  return first_sentence
end

---Recursively process schema descriptions in a JSON schema object
---@param schema table The schema object to process
---@param process_fn function The function to apply to descriptions
local function process_schema_descriptions(schema, process_fn)
  if not schema or type(schema) ~= "table" then return end

  -- Process description if present
  if schema.description and type(schema.description) == "string" then
    schema.description = process_fn(schema.description)
  end

  -- Process properties recursively
  if schema.properties and type(schema.properties) == "table" then
    for _, prop in pairs(schema.properties) do
      process_schema_descriptions(prop, process_fn)
    end
  end

  -- Process items in arrays
  if schema.items and type(schema.items) == "table" then process_schema_descriptions(schema.items, process_fn) end

  -- Process oneOf, anyOf, allOf arrays
  for _, key in ipairs({ "oneOf", "anyOf", "allOf" }) do
    if schema[key] and type(schema[key]) == "table" then
      for _, subschema in ipairs(schema[key]) do
        process_schema_descriptions(subschema, process_fn)
      end
    end
  end
end

---@param tool table The tool to summarize
---@return table The summarized tool
function M.summarize_tool(tool)
  if not tool then return nil end

  -- Create a deep copy of the tool to avoid modifying the original
  local summarized_tool = vim.deepcopy(tool)

  -- Check if we should use extra concise mode
  local extra_concise = Config.lazy_loading and Config.lazy_loading.mcp_extra_concise

  -- If extra_concise is enabled, create a minimal version of the tool
  if extra_concise then
    local minimal_tool = {
      name = summarized_tool.name,
    }

    -- Include only the name and summarized description
    -- Some tools have a property description, others have a function get_description
    local description = summarized_tool.description or (summarized_tool.get_description and summarized_tool.get_description())
    if description then
      minimal_tool.description = M.extract_first_sentence(description)
    end

    return minimal_tool
  end

  -- Regular summarization mode
  -- Summarize the description
  if summarized_tool.description then
    summarized_tool.description = M.extract_first_sentence(summarized_tool.description)
  end

  -- Summarize parameter descriptions in traditional format
  if summarized_tool.param and summarized_tool.param.fields then
    for _, field in ipairs(summarized_tool.param.fields) do
      if field.description then field.description = M.extract_first_sentence(field.description) end
    end
  end

  -- Summarize return descriptions
  if summarized_tool.returns then
    for _, ret in ipairs(summarized_tool.returns) do
      if ret.description then ret.description = M.extract_first_sentence(ret.description) end
    end
  end

  -- Process JSON schema format parameters if present
  if summarized_tool.parameters and type(summarized_tool.parameters) == "table" then
    process_schema_descriptions(summarized_tool.parameters, M.extract_first_sentence)
  end

  return summarized_tool
end

---@param tools table[] A collection of tools to summarize
---@return table[] Summarized tools
function M.summarize_tools(tools)
  if not tools or type(tools) ~= "table" then return {} end

  local summarized_tools = {}
  for _, tool in ipairs(tools) do
    table.insert(summarized_tools, M.summarize_tool(tool))
  end

  return summarized_tools
end

return M
