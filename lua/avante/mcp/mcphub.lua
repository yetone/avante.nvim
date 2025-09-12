--[[
MCPHub Integration Module
Provides integration between avante.nvim and mcphub.nvim with lazy loading support.
]]

local M = {}
local Config = require("avante.config")

-- Add a registry to track which tools have been requested
M._requested_tools = M._requested_tools or {}

-- Function to register a tool as requested
function M.register_requested_tool(server_name, tool_name)
  local key = server_name .. ":" .. tool_name
  M._requested_tools[key] = true
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

-- Function to get MCPHub prompt with lazy loading support
---@return string
function M.get_system_prompt()

  -- Check if lazy loading is enabled
  if Config.lazy_loading and Config.lazy_loading.enabled then
    -- Lazy load the summarizer module
    local Summarizer = require("avante.mcp.summarizer")
    local LLMTools = require("avante.llm_tools")

    -- Get the built-in tools using get_tools function with for_system_prompt=true
    local tools = LLMTools.get_tools("", {}, true)

    -- Add built-in tools section to the prompt
    local summarized_prompt =  "## Additional tools that can be requested using load_mcp_tool. \n\n"
    for _, tool in ipairs(tools) do
      summarized_prompt = summarized_prompt .. "- **" .. tool.name .. "**: " ..
        (tool.description or "No description") .. "\n\n"
    end
    return summarized_prompt
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
function M.should_include_tool(tool)
  return not Config.lazy_loading.enabled or
         vim.tbl_contains(Config.lazy_loading.always_eager or {}, tool.name) or
         (tool.server_name and M.is_tool_requested(tool.server_name, tool.name)) or
         (not tool.server_name and M.is_tool_requested("avante", tool.name))
end
return M
