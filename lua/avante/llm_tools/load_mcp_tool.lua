--[[
Load MCP Tool
This tool allows the LLM to request detailed information about specific MCP tools on demand.
This includes both mcphub server tools and built-in avante tools.
]]

local M = {}
local Config = require("avante.config")

M.name = "load_mcp_tool"
M.description = "Load detailed information about a specific MCP tool. Use this tool when you need more details about a tool's functionality, parameters, or usage than what is provided in the summarized description. To load built-in avante tools, use \"avante\" as the server_name."

M.param = {
  type = "table",
  fields = {
    {
      name = "server_name",
      description = "Name of the MCP server that provides the tool. Use \"avante\" for built-in avante tools.",
      type = "string",
    },
    {
      name = "tool_name",
      description = "Name of the tool to load",
      type = "string",
    },
  },
  usage = {
    server_name = "Name of the MCP server that provides the tool. Use \"avante\" for built-in avante tools.",
    tool_name = "Name of the tool to load",
  },
}

M.returns = {
  {
    name = "tool_details",
    description = "Detailed information about the requested tool",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the tool could not be loaded",
    type = "string",
    optional = true,
  },
}

-- Tool cache to avoid redundant requests
-- Define as a global variable for the module to ensure persistence between calls
M._tool_cache = M._tool_cache or {}

---@type AvanteLLMToolFunc<{ server_name: string, tool_name: string }>
function M.func(input, opts)
  local on_log = opts.on_log
  local on_complete = opts.on_complete

  -- Validate input parameters
  if not input.server_name then
    return nil, "server_name is required"
  end
  if not input.tool_name then
    return nil, "tool_name is required"
  end

  if on_log then on_log("server_name: " .. input.server_name) end
  if on_log then on_log("tool_name: " .. input.tool_name) end

  -- Check cache first
  local cache_key = input.server_name .. ":" .. input.tool_name
  if M._tool_cache[cache_key] then
    if on_log then on_log("Tool found in cache: " .. cache_key) end

    -- If this is an asynchronous request, use on_complete
    if on_complete then
      on_complete(M._tool_cache[cache_key], nil)
      return nil, nil
    else
      return M._tool_cache[cache_key], nil
    end
  end

  if on_log then on_log("Tool not found in cache: " .. cache_key) end

  -- Special handling for built-in avante tools
  if input.server_name == "avante" then
    if on_log then on_log("Loading built-in avante tool: " .. input.tool_name) end

    -- Find the tool in avante's built-in tools
    local found = false
    local tool_details = nil

    -- Lazy-load the tool module
    local ok, tool_module = pcall(require, "avante.llm_tools." .. input.tool_name)
    if ok and tool_module then
      found = true
      tool_details = tool_module
    else
      -- If not found as a separate module, check in the _tools array
      local llm_tools = require("avante.llm_tools")
      for _, tool in ipairs(llm_tools._tools) do
        if tool.name == input.tool_name then
          found = true
          tool_details = tool
          break
        end
      end
    end

    if found and tool_details then
      -- Format tool details into a readable format
      local formatted_details = vim.json.encode(tool_details)

      -- Store in cache for future requests
      M._tool_cache[cache_key] = formatted_details

      -- Handle both synchronous and asynchronous modes
      if on_complete then
        on_complete(formatted_details, nil)
        return nil, nil  -- Will be handled asynchronously
      else
        return formatted_details, nil
      end
    else
      local err_msg = "Built-in tool '" .. input.tool_name .. "' not found"
      if on_complete then
        on_complete(nil, err_msg)
        return nil, nil  -- Will be handled asynchronously
      else
        return nil, err_msg
      end
    end
  end

  -- Handle mcphub tools
  local ok, mcphub = pcall(require, "mcphub")
  if not ok then
    return nil, "mcphub.nvim is not available"
  end

  -- Verify server exists and is connected
  local servers = {}
  -- Handle both method-style and function-style calls
  if type(mcphub.get_active_servers) == "function" then
    servers = mcphub.get_active_servers()
  elseif type(mcphub.get_active_servers) == "table" then
    servers = mcphub.get_active_servers
  end

  local server_exists = false
  for _, server in ipairs(servers) do
    if server.name == input.server_name then
      server_exists = true
      break
    end
  end

  if not server_exists then
    local err_msg = "Server '" .. input.server_name .. "' is not available or not connected"
    if on_complete then
      on_complete(nil, err_msg)
      return nil, nil  -- Will be handled asynchronously
    else
      return nil, err_msg
    end
  end

  -- Get all tools and find the requested one
  local tools = {}
  local hub = mcphub.get_hub_instance and mcphub.get_hub_instance()
  if not hub then
    local err_msg = "mcphub hub instance not available"
    if on_complete then
      on_complete(nil, err_msg)
      return nil, nil  -- Will be handled asynchronously
    else
      return nil, err_msg
    end
  end

  -- Handle both method-style and function-style calls
  if type(hub.get_tools) == "function" then
    tools = hub:get_tools()
  elseif type(hub.get_tools) == "table" then
    tools = hub.get_tools
  else
    tools = {}
  end

  local found_tool = nil

  for _, tool in ipairs(tools) do
    if (tool.server_name == input.server_name or not tool.server_name) and tool.name == input.tool_name then
      found_tool = tool
      break
    end
  end

  if found_tool then
    -- Format tool details into a readable format
    local formatted_details = vim.json.encode(found_tool)

    -- Store in cache for future requests
    M._tool_cache[cache_key] = formatted_details

    if on_complete then
      on_complete(formatted_details, nil)
      return nil, nil  -- Will be handled asynchronously
    else
      return formatted_details, nil
    end
  else
    local err_msg = "Tool '" .. input.tool_name .. "' not found on server '" .. input.server_name .. "'"
    if on_complete then
      on_complete(nil, err_msg)
      return nil, nil  -- Will be handled asynchronously
    else
      return nil, err_msg
    end
  end
end

return M
