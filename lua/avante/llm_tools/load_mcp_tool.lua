--[[
Load MCP Tool
This tool allows the LLM to request detailed information about specific MCP tools on demand.
This includes both mcphub server tools and built-in avante tools.
]]

local M = {}
local Config = require("avante.config")
local LazyLoading = require("avante.llm_tools.lazy_loading")

M.name = "load_mcp_tool"
M.description =
  'Load detailed information about a specific MCP tool. Use this tool when you need more details about a tool\'s functionality, parameters, or usage than what is provided in the summarized description. To load built-in avante tools, use "avante" as the server_name.'
M.enabled = function() return Config.lazy_loading and Config.lazy_loading.enabled end
M.param = {
  type = "table",
  fields = {
    {
      name = "server_name",
      description = 'Name of the MCP server that provides the tool. Use "avante" for built-in avante tools.',
      type = "string",
    },
    {
      name = "tool_name",
      description = "Name of the tool to load",
      type = "string",
    },
  },
  usage = {
    server_name = 'Name of the MCP server that provides the tool. Use "avante" for built-in avante tools.',
    tool_name = "Name of the tool to load",
  },
}

M.returns = {
  {
    name = "tool_spec",
    description = "If loading the tool was successful, returns the tool specification, unless the tool is a built-in avante tool, in which case the tool will be added to the tools section of the prompt.",
    type = "string",
  },
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

  local message = nil
  local err_msg = nil
  local found_tool = false

  -- Validate input parameters
  if not input.server_name then
    err_msg = "server_name is required"
  end
  if not input.tool_name then
    err_msg = "tool_name is required"
  end

  -- Register this tool as requested. This means it will appear
  -- in subsequent queries to the model but not in the current
  -- streaming session.
  if err_msg == nil then
    found_tool = LazyLoading.register_requested_tool(input.server_name, input.tool_name)
  end

  --- Here we make sure that tools are available in the ongoing conversation
  --- For internal tools, we add them to the tools in the prompt. For MCPHub
  --- tools, we reply with the tool spec so that the LLM can call the tool
  --- using use_mcp_tool.
  if found_tool then
    if input.server_name == "avante" then
      local tool_to_add = vim.iter(require('avante.llm_tools').get_tools("", {}, false)):find(function(tool)
        return tool.name == input.tool_name end) ---@param tool AvanteLLMTool
      if tool_to_add == nil then
        err_msg = "Internal error: could not load tool " .. input.tool_name
        -- print(vim.inspect(input))
        -- print(vim.inspect(M.get_tools("", {}, false)))
        found_tool = false
      else
        LazyLoading.register_tool_to_collect(tool_to_add)
        -- vim.list_extend(tools, tool_to_add)
        message = "The tool " .. input.tool_name .. " has now been added to the tools section of the prompt."
      end
    else
      local tool = LazyLoading.get_mcphub_tool(input.server_name, input.tool_name)
      if tool then
        local MCPHubPrompt = require('mcphub.utils.prompt')
        local utils = require("mcphub.utils")
        local result = "This is is the input schema for the tool " .. input.tool_name .. " from the server " .. input.server_name
        result = result .. "\n **YOU WILL NEED THIS SCHEMA TO CALL THE TOOL***"
        result = result .. string.format("\n\n- %s: %s", tool.name, MCPHubPrompt.get_description(tool):gsub("\n", "\n  "))
        local inputSchema = MCPHubPrompt.get_inputSchema(tool)
        result = result
            .. "\n\n  Input Schema:\n\n  ```json\n  "
            .. utils.pretty_json(vim.json.encode(inputSchema)):gsub("\n", "\n  ")
            .. "\n  ```"
        message = result .. "\n Use this tool indirectly by using the 'use_mcp_tool' tool \n"
      else
        found_tool = false
      end

    end
  end
  if not found_tool then
    if err_msg == nil then
      err_msg = "Tool '" .. input.tool_name .. "' on server '" .. input.server_name .. "' does not exist."
    end
  end
  if on_log then
    if message then
      if not opts.tool_use_id then
        error("Tool use ID is missing in opts for load_mcp_tool")
      end
      on_log(opts.tool_use_id, "load_mcp_tool", message, "completed")
    elseif err_msg then
      if not opts.tool_use_id then
        error("Tool use ID is missing in opts for load_mcp_tool")
      end
      on_log(opts.tool_use_id, "load_mcp_tool", err_msg, "failed")
    end
  end

  if on_complete then
    on_complete(message, err_msg)
    return nil, nil  -- Will be handled asynchronously
  else
    return message, err_msg
  end
end

return M
