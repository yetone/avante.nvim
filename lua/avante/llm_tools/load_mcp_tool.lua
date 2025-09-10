--[[
Load MCP Tool
This tool allows the LLM to request detailed information about specific MCP tools on demand.
]]

local M = {}

M.name = "load_mcp_tool"
M.description = "Load detailed information about a specific MCP tool. Use this tool when you need more details about a tool's functionality, parameters, or usage than what is provided in the summarized description."

M.param = {
  type = "table",
  fields = {
    {
      name = "server_name",
      description = "Name of the MCP server that provides the tool",
      type = "string",
    },
    {
      name = "tool_name",
      description = "Name of the tool to load",
      type = "string",
    },
  },
  usage = {
    server_name = "Name of the MCP server that provides the tool",
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
local tool_cache = {}

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
  if tool_cache[cache_key] then
    if on_log then on_log("Tool found in cache") end
    return tool_cache[cache_key], nil
  end
  
  -- Get mcphub instance
  local ok, mcphub = pcall(require, "mcphub")
  if not ok then
    return nil, "mcphub.nvim is not available"
  end
  
  -- Verify server exists and is connected
  local servers = mcphub.get_active_servers()
  local server_exists = false
  for _, server in ipairs(servers) do
    if server.name == input.server_name then
      server_exists = true
      break
    end
  end
  
  if not server_exists then
    return nil, "Server '" .. input.server_name .. "' is not available or not connected"
  end
  
  -- Handle asynchronous requests
  if not on_complete then
    return nil, "on_complete is required for this tool"
  end
  
  -- Request tool details from the server
  mcphub.get_server_tool_details(input.server_name, input.tool_name, function(tool_details, err)
    if err then
      on_complete(nil, err)
      return
    end
    
    if not tool_details then
      on_complete(nil, "Tool '" .. input.tool_name .. "' not found on server '" .. input.server_name .. "'")
      return
    end
    
    -- Format tool details into a readable format
    local formatted_details = vim.json.encode(tool_details)
    
    -- Store in cache for future requests
    tool_cache[cache_key] = formatted_details
    
    on_complete(formatted_details, nil)
  end)
  
  return nil, nil  -- Will be handled asynchronously
end

return M
