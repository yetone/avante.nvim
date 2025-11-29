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

-- Internal cache for loaded tool specs (non-avante servers)
M._tool_cache = M._tool_cache or {}

---@type AvanteLLMToolFunc<{ server_name: string, tool_name: string }>
function M.func(input, opts)
  local on_log = opts.on_log
  local on_complete = opts.on_complete

  local message = nil
  local err_msg = nil
  local found_tool = false
  local tool_id = "load_mcp_tool_" .. Utils.uuid() -- Generate a unique ID for this tool call

  -- Validate input parameters
  if not input.server_name then
    err_msg = "server_name is required"
  elseif not input.tool_name then
    err_msg = "tool_name is required"
  end

  -- Early exit if validation failed
  if err_msg ~= nil then
    if on_complete then
      on_complete(nil, err_msg)
      return nil, nil
    else
      return nil, err_msg
    end
  end

  -- Register requested tool for lazy loading tracking (does not guarantee existence)
  LazyLoading.register_requested_tool(input.server_name, input.tool_name)

  -- Handle built-in avante tools specially by adding them to prompt instead of returning spec
  if input.server_name == "avante" then
    local tool_to_add = vim
      .iter(require("avante.llm_tools").get_tools("", {}, false))
      :find(function(tool) return tool.name == input.tool_name end) ---@param tool AvanteLLMTool
    if tool_to_add == nil then
      err_msg = "Internal error: could not load tool " .. input.tool_name
    else
      LazyLoading.register_tool_to_collect(tool_to_add)
      message = "The tool " .. input.tool_name .. " has now been added to the tools section of the prompt."
    end
    if on_complete then
      on_complete(message, err_msg)
      return nil, nil
    else
      return message, err_msg
    end
  end

  -- Non-avante server path: retrieve tool details (and cache)
  local cache_key = input.server_name .. ":" .. input.tool_name
  if M._tool_cache[cache_key] then
    message = M._tool_cache[cache_key]
    if on_log then on_log("Cache hit for " .. cache_key) end
    if on_complete then
      on_complete(message, nil)
      return nil, nil
    else
      return message, nil
    end
  end

  -- Try to access mcphub hub instance
  local hub_ok, mcphub = pcall(require, "mcphub")
  if not hub_ok or not mcphub or not mcphub.get_hub_instance then
    err_msg = "Server '" .. input.server_name .. "' is not available or not connected"
    if on_complete then
      on_complete(nil, err_msg)
      return nil, nil
    else
      return nil, err_msg
    end
  end

  local hub = mcphub.get_hub_instance()
  if not hub or not hub.get_tools then
    err_msg = "Server '" .. input.server_name .. "' is not available or not connected"
    if on_complete then
      on_complete(nil, err_msg)
      return nil, nil
    else
      return nil, err_msg
    end
  end

  local tools = hub:get_tools() or {}
  local server_exists = false
  local found_tool = nil

  for _, tool in ipairs(tools) do
    if tool.server_name == input.server_name then
      server_exists = true
      if tool.name == input.tool_name then
        found_tool = tool
        break
      end
    end
  end

  if not server_exists then
    err_msg = "Server '" .. input.server_name .. "' is not available or not connected"
  elseif not found_tool then
    err_msg = "Tool '" .. input.tool_name .. "' on server '" .. input.server_name .. "' does not exist."
  else
    -- Build minimal spec (tests expect JSON string with name & description)
    local spec_tbl = {
      name = found_tool.name,
      description = found_tool.description,
    }
    message = vim.json.encode(spec_tbl)
    M._tool_cache[cache_key] = message
  end
  if on_log then
    if message then
      on_log(tool_id, "load_mcp_tool", message, "completed")
    elseif err_msg then
      on_log(tool_id, "load_mcp_tool", err_msg, "failed")
    end
  end

  if on_complete then
    on_complete(message, err_msg)
    return nil, nil -- async style
  else
    return message, err_msg
  end
end

return M
