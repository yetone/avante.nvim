local Config = require("avante.config")
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

Tool use is formatted using XML-style tags. Each tool use is wrapped in a <tool_use> tag. The tool use content is a valid JSON with tool name and tool input. Here's the structure:

<tool_use>
{
  "name": "tool_name",
  "input": {
    "parameter1_name": "value1",
    "parameter2_name": "value2",
    ...
  }
}
</tool_use>

For example:

<tool_use>
{"name": "attempt_completion", "input": {"result": "I have completed the task..."}}
</tool_use>


<tool_use>
{"name": "bash", "input": {"path": "./src", "command": "npm run dev"}}
</tool_use>

ALWAYS ADHERE TO this format for the tool use to ensure proper parsing and execution.

## RULES
- When outputting the JSON for tool_use, you MUST first output the "name" field and then the "input" field.
- The value of "input" MUST be VALID JSON.
- If the "input" JSON object contains a "path" field, you MUST output the "path" field before any other fields.

## OUTPUT FORMAT
Please remember you are not allowed to use any format related to function calling or fc or tool_code.

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
        if field.choices then
          tool_prompt = tool_prompt .. "    - Choices: "
          for i, choice in ipairs(field.choices) do
            tool_prompt = tool_prompt .. string.format("%s", choice)
            if i ~= #field.choices then tool_prompt = tool_prompt .. ", " end
          end
          tool_prompt = tool_prompt .. "\n"
        end
      end
      if tool.param.usage then
        tool_prompt = tool_prompt .. "Usage:\n<tool_use>"
        local tool_use = {
          name = tool.name,
          input = tool.param.usage,
        }
        local tool_use_json = vim.json.encode(tool_use)
        tool_prompt = tool_prompt .. tool_use_json .. "</tool_use>\n"
      end
      tools_prompts = tools_prompts .. tool_prompt .. "\n"
    end

    system_prompt = system_prompt .. tools_prompts

    system_prompt = system_prompt
      .. [[
# Tool Use Examples

## Example 1: Requesting to execute a command

<tool_use>{"name": "bash", "input": {"path": "./src", "command": "npm run dev"}}</tool_use>
]]

    if Config.behaviour.enable_fastapply then
      system_prompt = system_prompt
        .. [[
## Example 2: Requesting to create a new file

<tool_use>{"name": "edit_file", "input": {"path": "src/frontend-config.json", "instructions": "write the following content to the file", "code_edit": "// ... existing code ...\nFIRST_EDIT\n// ... existing code ...\nSECOND_EDIT\n// ... existing code ...\nTHIRD_EDIT\n// ... existing code ...\n\n"}}</tool_use>

## Example 3: Requesting to make targeted edits to a file

<tool_use>{"name": "edit_file", "input": {"path": "src/frontend-config.json", "instructions": "write the following content to the file", "code_edit": "// ... existing code ...\nFIRST_EDIT\n// ... existing code ...\nSECOND_EDIT\n// ... existing code ...\nTHIRD_EDIT\n// ... existing code ...\n\n"}}</tool_use>
]]
    else
      system_prompt = system_prompt
        .. [[
## Example 2: Requesting to create a new file

<tool_use>{"name": "write_to_file", "input": {"path": "src/frontend-config.json", "the_content": "{\n  \"apiEndpoint\": \"https://api.example.com\",\n  \"theme\": {\n    \"primaryColor\": \"#007bff\",\n    \"secondaryColor\": \"#6c757d\",\n    \"fontFamily\": \"Arial, sans-serif\"\n  },\n  \"features\": {\n    \"darkMode\": true,\n    \"notifications\": true,\n    \"analytics\": false\n  },\n  \"version\": \"1.0.0\"\n}"}}</tool_use>

## Example 3: Requesting to make targeted edits to a file

<tool_use>{"name": "replace_in_file", "input": {"path": "src/components/App.tsx", "the_diff": "------- SEARCH\nimport React from 'react';\n=======\nimport React, { useState } from 'react';\n+++++++ REPLACE\n\n------- SEARCH\nfunction handleSubmit() {\n  saveData();\n  setLoading(false);\n}\n\n=======\n+++++++ REPLACE\n\n------- SEARCH\nreturn (\n  <div>\n=======\nfunction handleSubmit() {\n  saveData();\n  setLoading(false);\n}\n\nreturn (\n  <div>\n+++++++ REPLACE\n"}}</tool_use>
]]
    end

    system_prompt = system_prompt
      .. [[
## Example 4: Complete current task

<tool_use>{"name": "attempt_completion", "input": {"result": "I've successfully created the requested React component with the following features:\n- Responsive layout\n- Dark/light mode toggle\n- Form validation\n- API integration"}}</tool_use>

## Example 5: Add todos

<tool_use>{"name": "add_todos", "input": {"todos": [{"id": "1", "content": "Implement a responsive layout", "status": "todo", "priority": "low"}, {"id": "2", "content": "Add dark/light mode toggle", "status": "todo", "priority": "medium"}]}}</tool_use>

## Example 6: Update todo status

<tool_use>{"name": "update_todo_status", "input": {"id": "1", "status": "done"}}</tool_use>
]]
  end
  return system_prompt
end

--- Get the content of AGENTS.md or CLAUDE.md or OPENCODE.md
---@return string | nil
function M.get_agents_rules_prompt()
  local Utils = require("avante.utils")
  local project_root = Utils.get_project_root()
  local file_names = {
    "AGENTS.md",
    "CLAUDE.md",
    "OPENCODE.md",
    ".cursorrules",
    ".windsurfrules",
    Utils.join_paths(".github", "copilot-instructions.md"),
  }
  for _, file_name in ipairs(file_names) do
    local file_path = Utils.join_paths(project_root, file_name)
    if vim.fn.filereadable(file_path) == 1 then
      local content = vim.fn.readfile(file_path)
      if content then return table.concat(content, "\n") end
    end
  end
  return nil
end

---@param selected_files AvanteSelectedFile[]
---@return string | nil
function M.get_cursor_rules_prompt(selected_files)
  local Utils = require("avante.utils")
  local project_root = Utils.get_project_root()
  local accumulated_content = ""

  ---@type string[]
  local mdc_files = vim.fn.globpath(Utils.join_paths(project_root, ".cursor/rules"), "*.mdc", false, true)
  for _, file_path in ipairs(mdc_files) do
    ---@type string[]
    local content = vim.fn.readfile(file_path)
    if content[1] ~= "---" or content[5] ~= "---" then goto continue end
    local header, body = table.concat(content, "\n", 2, 4), table.concat(content, "\n", 6)
    local _description, globs, alwaysApply = header:match("description:%s*(.*)\nglobs:%s*(.*)\nalwaysApply:%s*(.*)")

    if not globs then goto continue end
    globs = vim.trim(globs)
    -- TODO: When empty string, this means the agent should request for this rule ad-hoc.
    if globs == "" then goto continue end
    local globs_array = vim.split(globs, ",%s*")
    local path_regexes = {} ---@type string[]
    for _, glob in ipairs(globs_array) do
      path_regexes[#path_regexes + 1] = glob:gsub("%*%*", ".+"):gsub("%*", "[^/]*")
      path_regexes[#path_regexes + 1] = glob:gsub("%*%*/", ""):gsub("%*", "[^/]*")
    end
    local always_apply = alwaysApply == "true"

    if always_apply then
      accumulated_content = accumulated_content .. "\n" .. body
    else
      local matched = false
      for _, selected_file in ipairs(selected_files) do
        for _, path_regex in ipairs(path_regexes) do
          if string.match(selected_file.path, path_regex) then
            accumulated_content = accumulated_content .. "\n" .. body
            matched = true
            break
          end
        end
        if matched then break end
      end
    end
    ::continue::
  end
  return accumulated_content ~= "" and accumulated_content or nil
end

return M
