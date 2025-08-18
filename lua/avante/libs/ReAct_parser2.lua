local JsonParser = require("avante.libs.jsonparser")

---@class avante.TextContent
---@field type "text"
---@field text string
---@field partial boolean
---
---@class avante.ToolUseContent
---@field type "tool_use"
---@field tool_name string
---@field tool_input table
---@field partial boolean

local M = {}

--- Parse the text into a list of TextContent and ToolUseContent
--- The text is a string.
--- For example:
--- parse([[Hello, world!]])
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world!",
---     partial = false,
---   },
--- }
---
--- parse([[Hello, world! I am a tool.<tool_use>{"name": "write", "input": {"path": "path/to/file.txt", "content": "foo"}}</tool_use>]])
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world! I am a tool.",
---     partial = false,
---   },
---   {
---     type = "tool_use",
---     tool_name = "write",
---     tool_input = {
---       path = "path/to/file.txt",
---       content = "foo",
---     },
---     partial = false,
---   },
--- }
---
--- parse([[Hello, world! I am a tool.<tool_use>{"name": "write", "input": {"path": "path/to/file.txt", "content": "foo"}}</tool_use>I am another tool.<tool_use>{"name": "write", "input": {"path": "path/to/file.txt", "content": "bar"}}</tool_use>hello]])
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world! I am a tool.",
---     partial = false,
---   },
---   {
---     type = "tool_use",
---     tool_name = "write",
---     tool_input = {
---       path = "path/to/file.txt",
---       content = "foo",
---     },
---     partial = false,
---   },
---   {
---     type = "text",
---     text = "I am another tool.",
---     partial = false,
---   },
---   {
---     type = "tool_use",
---     tool_name = "write",
---     tool_input = {
---       path = "path/to/file.txt",
---       content = "bar",
---     },
---     partial = false,
---   },
---   {
---     type = "text",
---     text = "hello",
---     partial = false,
---   },
--- }
---
--- parse([[Hello, world! I am a tool.<tool_use>{"name"]])
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world! I am a tool.",
---     partial = false,
---   }
--- }
---
--- parse([[Hello, world! I am a tool.<tool_use>{"name": "write"]])
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world! I am a tool.",
---     partial = false,
---   },
---   {
---     type = "tool_use",
---     tool_name = "write",
---     tool_input = {},
---     partial = true,
---   },
--- }
---
--- parse([[Hello, world! I am a tool.<tool_use>{"name": "write", "input": {"path": "path/to/file.txt"]])
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world! I am a tool.",
---     partial = false,
---   },
---   {
---     type = "tool_use",
---     tool_name = "write",
---     tool_input = {
---       path = "path/to/file.txt",
---     },
---     partial = true,
---   },
--- }
---
--- parse([[Hello, world! I am a tool.<tool_use>{"name": "write", "input": {"path": "path/to/file.txt", "content": "foo bar]])
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world! I am a tool.",
---     partial = false,
---   },
---   {
---     type = "tool_use",
---     tool_name = "write",
---     tool_input = {
---       path = "path/to/file.txt",
---       content = "foo bar",
---     },
---     partial = true,
---   },
--- }
---
--- parse([[Hello, world! I am a tool.{"name": "write", "input": {"path": "path/to/file.txt", "content": foo bar]])
--- returns
--- {
---   {
---     type = "text",
---     text = [[Hello, world! I am a tool.{"name": "write", "input": {"path": "path/to/file.txt", "content": foo bar]],
---     partial = false,
---   }
--- }
---
---@param text string
---@return (avante.TextContent|avante.ToolUseContent)[]
function M.parse(text)
  local result = {}
  local pos = 1
  local len = #text

  while pos <= len do
    local tool_start = text:find("<tool_use>", pos, true)

    if not tool_start then
      -- No more tool_use tags, add remaining text if any
      if pos <= len then
        local remaining_text = text:sub(pos)
        if remaining_text ~= "" then
          table.insert(result, {
            type = "text",
            text = remaining_text,
            partial = false,
          })
        end
      end
      break
    end

    -- Add text before tool_use tag if any
    if tool_start > pos then
      local text_content = text:sub(pos, tool_start - 1)
      if text_content ~= "" then
        table.insert(result, {
          type = "text",
          text = text_content,
          partial = false,
        })
      end
    end

    -- Find the closing tag
    local json_start = tool_start + 10 -- length of "<tool_use>"
    local tool_end = text:find("</tool_use>", json_start, true)

    if not tool_end then
      -- No closing tag found, treat as partial tool_use
      local json_text = text:sub(json_start)

      json_text = json_text:gsub("^\n+", "")
      json_text = json_text:gsub("\n+$", "")
      json_text = json_text:gsub("^%s+", "")
      json_text = json_text:gsub("%s+$", "")

      -- Try to parse complete JSON first
      local success, json_data = pcall(function() return vim.json.decode(json_text) end)

      if success and json_data and json_data.name then
        table.insert(result, {
          type = "tool_use",
          tool_name = json_data.name,
          tool_input = json_data.input or {},
          partial = true,
        })
      else
        local jsn = JsonParser.parse(json_text)

        if jsn and jsn.name then
          table.insert(result, {
            type = "tool_use",
            tool_name = jsn.name,
            tool_input = jsn.input or {},
            partial = true,
          })
        end
      end
      break
    end

    -- Extract JSON content
    local json_text = text:sub(json_start, tool_end - 1)
    local success, json_data = pcall(function() return vim.json.decode(json_text) end)

    if success and json_data and json_data.name then
      table.insert(result, {
        type = "tool_use",
        tool_name = json_data.name,
        tool_input = json_data.input or {},
        partial = false,
      })
      pos = tool_end + 11 -- length of "</tool_use>"
    else
      -- Invalid JSON, treat the whole thing as text
      local invalid_text = text:sub(tool_start, tool_end + 10)
      table.insert(result, {
        type = "text",
        text = invalid_text,
        partial = false,
      })
      pos = tool_end + 11
    end
  end

  return result
end

return M
