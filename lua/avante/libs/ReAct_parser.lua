local M = {}

-- Helper function to parse a parameter tag like <param_name>value</param_name>
-- Returns {name = string, value = string, next_pos = number} or nil if incomplete
local function parse_parameter(text, start_pos)
  local i = start_pos
  local len = #text

  -- Skip whitespace
  while i <= len and string.match(string.sub(text, i, i), "%s") do
    i = i + 1
  end

  if i > len or string.sub(text, i, i) ~= "<" then return nil end

  -- Find parameter name
  local param_name_start = i + 1
  local param_name_end = string.find(text, ">", param_name_start)

  if not param_name_end then
    return nil -- Incomplete parameter tag
  end

  local param_name = string.sub(text, param_name_start, param_name_end - 1)
  i = param_name_end + 1

  -- Find parameter value (everything until closing tag)
  local param_close_tag = "</" .. param_name .. ">"
  local param_value_start = i
  local param_close_pos = string.find(text, param_close_tag, i, true)

  if not param_close_pos then
    -- Incomplete parameter value, return what we have
    local param_value = string.sub(text, param_value_start)
    return {
      name = param_name,
      value = param_value,
      next_pos = len + 1,
    }
  end

  local param_value = string.sub(text, param_value_start, param_close_pos - 1)
  i = param_close_pos + #param_close_tag

  return {
    name = param_name,
    value = param_value,
    next_pos = i,
  }
end

-- Helper function to parse tool use content starting after <tool_use>
-- Returns {content = ToolUseContent, next_pos = number} or nil if incomplete
local function parse_tool_use(text, start_pos)
  local i = start_pos
  local len = #text

  -- Skip whitespace
  while i <= len and string.match(string.sub(text, i, i), "%s") do
    i = i + 1
  end

  if i > len then
    return nil -- No content after <tool_use>
  end

  -- Check if we have opening tag for tool name
  if string.sub(text, i, i) ~= "<" then
    return nil -- Invalid format
  end

  -- Find tool name
  local tool_name_start = i + 1
  local tool_name_end = string.find(text, ">", tool_name_start)

  if not tool_name_end then
    return nil -- Incomplete tool name tag
  end

  local tool_name = string.sub(text, tool_name_start, tool_name_end - 1)
  i = tool_name_end + 1

  -- Parse tool parameters
  local tool_input = {}
  local partial = false

  -- Look for tool closing tag or </tool_use>
  local tool_close_tag = "</" .. tool_name .. ">"
  local tool_use_close_tag = "</tool_use>"

  while i <= len do
    -- Skip whitespace before checking for closing tags
    while i <= len and string.match(string.sub(text, i, i), "%s") do
      i = i + 1
    end

    if i > len then
      partial = true
      break
    end

    -- Check for tool closing tag first
    local tool_close_pos = string.find(text, tool_close_tag, i, true)
    local tool_use_close_pos = string.find(text, tool_use_close_tag, i, true)

    if tool_close_pos and tool_close_pos == i then
      -- Found tool closing tag
      i = tool_close_pos + #tool_close_tag

      -- Skip whitespace
      while i <= len and string.match(string.sub(text, i, i), "%s") do
        i = i + 1
      end

      -- Check for </tool_use>
      if i <= len and string.find(text, tool_use_close_tag, i, true) == i then
        i = i + #tool_use_close_tag
        partial = false
      else
        partial = true
      end
      break
    elseif tool_use_close_pos and tool_use_close_pos == i then
      -- Found </tool_use> without tool closing tag (malformed, but handle it)
      i = tool_use_close_pos + #tool_use_close_tag
      partial = false
      break
    else
      -- Parse parameter tag
      local param_result = parse_parameter(text, i)
      if param_result then
        tool_input[param_result.name] = param_result.value
        i = param_result.next_pos
      else
        -- Incomplete parameter, mark as partial
        partial = true
        break
      end
    end
  end

  -- If we reached end of text without proper closing, it's partial
  if i > len then partial = true end

  return {
    content = {
      type = "tool_use",
      tool_name = tool_name,
      tool_input = tool_input,
      partial = partial,
    },
    next_pos = i,
  }
end

--- Parse the text into a list of TextContent and ToolUseContent
--- The text is a string.
--- For example:
--- parse("Hello, world!")
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world!",
---     partial = false,
---   },
--- }
---
--- parse("Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path><content>foo</content></write></tool_use>")
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
--- parse("Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path><content>foo</content></write></tool_use>I am another tool.<tool_use><write><path>path/to/file.txt</path><content>bar</content></write></tool_use>hello")
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
--- parse("Hello, world! I am a tool.<tool_use><write")
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world! I am a tool.",
---     partial = false,
---   }
--- }
---
--- parse("Hello, world! I am a tool.<tool_use><write>")
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
--- parse("Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt")
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
--- parse("Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path><content>foo bar")
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
--- parse("Hello, world! I am a tool.<write><path>path/to/file.txt</path><content>foo bar")
--- returns
--- {
---   {
---     type = "text",
---     text = "Hello, world! I am a tool.<write><path>path/to/file.txt</path><content>foo bar",
---     partial = false,
---   }
--- }
---
--- parse("Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path><content><button>foo</button></content></write></tool_use>")
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
---       content = "<button>foo</button>",
---     },
---     partial = false,
---   },
--- }
---
--- parse("Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path><content><button>foo")
--- returns
--- {
---   {
---       text = "Hello, world! I am a tool.",
---       partial = false,
---   },
---   {
---     type = "tool_use",
---     tool_name = "write",
---     tool_input = {
---       path = "path/to/file.txt",
---       content = "<button>foo",
---     },
---     partial = true,
---   },
--- }
---
---@param text string
---@return (avante.TextContent|avante.ToolUseContent)[]
function M.parse(text)
  local result = {}
  local current_text = ""
  local i = 1
  local len = #text

  -- Helper function to add text content to result
  local function add_text_content()
    if current_text ~= "" then
      table.insert(result, {
        type = "text",
        text = current_text,
        partial = false,
      })
      current_text = ""
    end
  end

  -- Helper function to find the next occurrence of a pattern
  local function find_pattern(pattern, start_pos) return string.find(text, pattern, start_pos, true) end

  while i <= len do
    -- Check for <tool_use> tag
    local tool_use_start = find_pattern("<tool_use>", i)

    if tool_use_start and tool_use_start == i then
      -- Found <tool_use> at current position
      add_text_content()
      i = i + 10 -- Skip "<tool_use>"

      -- Parse tool use content
      local tool_use_result = parse_tool_use(text, i)
      if tool_use_result then
        table.insert(result, tool_use_result.content)
        i = tool_use_result.next_pos
      else
        -- Incomplete tool_use, break
        break
      end
    else
      -- Regular text character
      if tool_use_start then
        -- There's a <tool_use> ahead, add text up to that point
        current_text = current_text .. string.sub(text, i, tool_use_start - 1)
        i = tool_use_start
      else
        -- No more <tool_use> tags, add rest of text
        current_text = current_text .. string.sub(text, i)
        break
      end
    end
  end

  -- Add any remaining text
  add_text_content()

  return result
end

return M
