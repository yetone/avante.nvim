local M = {}

---@param provider_conf AvanteDefaultBaseProvider
---@param opts AvantePromptOptions
---@return string
function M.get_ReAct_system_prompt(provider_conf, opts)
  local system_prompt = opts.system_prompt
  local disable_tools = provider_conf.disable_tools or false
  if not disable_tools and opts.tools then
    local tools_prompts = [[
====

TOOL USE

You have access to a set of tools that are executed upon the user's approval. You can use one tool per message, and will receive the result of that tool use in the user's response. You use tools step-by-step to accomplish a given task, with each tool use informed by the result of the previous tool use.

# Tool Use Formatting

Tool use is formatted using XML-style tags. The tool name is enclosed in opening and closing tags, and each parameter is similarly enclosed within its own set of tags. Here's the structure:

<tool_name>
<parameter1_name>value1</parameter1_name>
<parameter2_name>value2</parameter2_name>
...
</tool_name>

For example:

<view>
<path>src/main.js</path>
</view>

Always adhere to this format for the tool use to ensure proper parsing and execution.

# Tools

]]
    for _, tool in ipairs(opts.tools) do
      local tool_prompt = ([[
## {{name}}
Description: {{description}}
Parameters:
]]):gsub("{{name}}", tool.name):gsub(
        "{{description}}",
        tool.get_description and tool.get_description() or (tool.description or "")
      )
      for _, field in ipairs(tool.param.fields) do
        if field.optional then
          tool_prompt = tool_prompt .. string.format(" - %s: %s\n", field.name, field.description)
        else
          tool_prompt = tool_prompt
            .. string.format(
              " - %s: (required) %s\n",
              field.name,
              field.get_description and field.get_description() or (field.description or "")
            )
        end
      end
      if tool.param.usage then
        tool_prompt = tool_prompt
          .. ("Usage:\n<{{name}}>\n"):gsub("{{([%w_]+)}}", function(name) return tool[name] end)
        for k, v in pairs(tool.param.usage) do
          tool_prompt = tool_prompt .. "<" .. k .. ">" .. tostring(v) .. "</" .. k .. ">\n"
        end
        tool_prompt = tool_prompt .. ("</{{name}}>\n"):gsub("{{([%w_]+)}}", function(name) return tool[name] end)
      end
      tools_prompts = tools_prompts .. tool_prompt .. "\n"
    end

    system_prompt = system_prompt .. tools_prompts

    system_prompt = system_prompt
      .. [[
# Tool Use Examples

## Example 1: Requesting to execute a command

<bash>
<path>./src</path>
<command>npm run dev</command>
</bash>

## Example 2: Requesting to create a new file

<write_to_file>
<path>src/frontend-config.json</path>
<content>
{
  "apiEndpoint": "https://api.example.com",
  "theme": {
    "primaryColor": "#007bff",
    "secondaryColor": "#6c757d",
    "fontFamily": "Arial, sans-serif"
  },
  "features": {
    "darkMode": true,
    "notifications": true,
    "analytics": false
  },
  "version": "1.0.0"
}
</content>
</write_to_file>

## Example 3: Requesting to make targeted edits to a file

<replace_in_file>
<path>src/components/App.tsx</path>
<diff>
<<<<<<< SEARCH
import React from 'react';
=======
import React, { useState } from 'react';
>>>>>>> REPLACE

<<<<<<< SEARCH
function handleSubmit() {
  saveData();
  setLoading(false);
}

=======
>>>>>>> REPLACE

<<<<<<< SEARCH
return (
  <div>
=======
function handleSubmit() {
  saveData();
  setLoading(false);
}

return (
  <div>
>>>>>>> REPLACE
</diff>
</replace_in_file>
]]
  end
  return system_prompt
end

return M
