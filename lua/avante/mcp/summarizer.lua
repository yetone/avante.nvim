--[[
Tool Summarizer Module for MCP Tools
This module extracts concise information from MCP tool descriptions to reduce token usage.
]]

local M = {}
local config = require("avante.config")

---@param description string The description to extract the first sentence from
---@return string The first sentence or a truncated version if no sentence end is found
function M.extract_first_sentence(description)
  if not description or description == "" then
    return ""
  end

  -- Special case: if the description contains a code block followed by a period
  -- e.g. "A description with code. `code block here`. Second sentence."
  -- We want to include the code block in the first sentence
  local code_block_pattern = "(`[^`]+`)"
  local with_code_blocks = description:match("^(.-%.)%s" .. code_block_pattern .. "%.")
  if with_code_blocks then
    local first_part = description:match("^(.-%.)%s")
    local code_block = description:match(code_block_pattern)
    if first_part and code_block then
      return first_part .. " " .. code_block .. "."
    end
  end

  -- Handle common abbreviations to avoid false sentence endings
  local desc = description:gsub("([Ee]%.g%.)", "%1___ABBR___")
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
  if not schema or type(schema) ~= "table" then
    return
  end

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
  if schema.items and type(schema.items) == "table" then
    process_schema_descriptions(schema.items, process_fn)
  end

  -- Process oneOf, anyOf, allOf arrays
  for _, key in ipairs({"oneOf", "anyOf", "allOf"}) do
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
  if not tool then
    return nil
  end

  -- Create a deep copy of the tool to avoid modifying the original
  local summarized_tool = vim.deepcopy(tool)

  -- Check if we should use extra concise mode
  local extra_concise = config.behaviour and config.behaviour.mcp_extra_concise

  -- If extra_concise is enabled, create a minimal version of the tool
  if extra_concise then
    local minimal_tool = {
      name = summarized_tool.name
    }

    -- Include only the name and summarized description
    if summarized_tool.description then
      minimal_tool.description = M.extract_first_sentence(summarized_tool.description)
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

  -- Process JSON schema format parameters if present
  if summarized_tool.parameters and type(summarized_tool.parameters) == "table" then
    process_schema_descriptions(summarized_tool.parameters, M.extract_first_sentence)
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
