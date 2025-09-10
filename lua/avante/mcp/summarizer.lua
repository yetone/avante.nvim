--[[
Tool Summarizer Module for MCP Tools
This module extracts concise information from MCP tool descriptions to reduce token usage.
]]

local M = {}

---@param description string The description to extract the first sentence from
---@return string The first sentence or a truncated version if no sentence end is found
function M.extract_first_sentence(description)
  if not description or description == "" then
    return ""
  end
  
  -- Handle common abbreviations to avoid false sentence endings
  local desc = description:gsub("([Ee]%.g%.)", "%1___ABBR___")
                         :gsub("([Ii]%.e%.)", "%1___ABBR___")
                         :gsub("([Ee]tc%.)", "%1___ABBR___")
  
  -- Find the first sentence end
  local sentence_end = desc:find("[%.%?%!]%s")
  
  -- If no sentence end is found, take first 100 characters and add ellipsis
  if not sentence_end then
    if #description > 100 then
      return description:sub(1, 100) .. "..."
    else
      return description
    end
  end
  
  -- Extract the first sentence and restore abbreviations
  local first_sentence = desc:sub(1, sentence_end)
  return first_sentence:gsub("___ABBR___", "")
end

---@param tool table The tool to summarize
---@return table The summarized tool
function M.summarize_tool(tool)
  if not tool then
    return nil
  end
  
  -- Create a deep copy of the tool to avoid modifying the original
  local summarized_tool = vim.deepcopy(tool)
  
  -- Summarize the description
  if summarized_tool.description then
    summarized_tool.description = M.extract_first_sentence(summarized_tool.description)
  end
  
  -- Summarize parameter descriptions
  if summarized_tool.param and summarized_tool.param.fields then
    for _, field in ipairs(summarized_tool.param.fields) do
      if field.description then
        field.description = M.extract_first_sentence(field.description)
      end
    end
  end
  
  -- Summarize return descriptions
  if summarized_tool.returns then
    for _, ret in ipairs(summarized_tool.returns) do
      if ret.description then
        ret.description = M.extract_first_sentence(ret.description)
      end
    end
  end
  
  return summarized_tool
end

---@param tools table[] A collection of tools to summarize
---@return table[] Summarized tools
function M.summarize_tools(tools)
  if not tools or type(tools) ~= "table" then
    return {}
  end
  
  local summarized_tools = {}
  for _, tool in ipairs(tools) do
    table.insert(summarized_tools, M.summarize_tool(tool))
  end
  
  return summarized_tools
end

return M
