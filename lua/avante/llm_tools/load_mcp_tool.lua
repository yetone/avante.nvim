--[[
Load MCP Tool
This tool allows the LLM to request detailed information about specific MCP tools on demand.
This includes both mcphub server tools and built-in avante tools.
]]

local M = {}
local Config = require("avante.config")
local MCPHub = require("avante.mcp.mcphub")

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
    name = "error",
    description = "Error message if the tool could not be loaded",
    type = "string",
    optional = true,
  },
}

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

  -- Register this tool as requested
  found_tool = MCPHub.register_requested_tool(input.server_name, input.tool_name)

  if found_tool then
    if on_complete then
      on_complete(nil)
      return nil  -- Will be handled asynchronously
    else
      return nil
    end
  else
    local err_msg = "Tool '" .. input.tool_name .. "' on server '" .. input.server_name .. "' does not exist."
    if on_complete then
      on_complete(err_msg)
      return nil  -- Will be handled asynchronously
    else
      return err_msg
    end
  end
end

return M
