-- StreamingJSONParser: 一个能够处理不完整 JSON 流的解析器
local StreamingJSONParser = {}
StreamingJSONParser.__index = StreamingJSONParser

-- Create a new StreamingJSONParser instance
function StreamingJSONParser:new()
  local obj = setmetatable({}, StreamingJSONParser)
  obj:reset()
  return obj
end

-- Reset the parser state
function StreamingJSONParser:reset()
  self.buffer = ""
  self.state = {
    inString = false,
    escaping = false,
    stack = {},
    result = nil,
    currentKey = nil,
    current = nil,
    parentKeys = {},
    stringBuffer = "",
  }
end

-- Get the current partial result
function StreamingJSONParser:getCurrentPartial() return self.state.result end

-- Add a value to the current object or array
function StreamingJSONParser:addValue(value)
  local top = self.state.stack[#self.state.stack]
  top.expectingValue = false

  if top.type == "object" then
    if self.state.current == nil then
      self.state.current = {}
      if self.state.result == nil then self.state.result = self.state.current end
    end
    self.state.current[self.state.currentKey] = value
    top.expectingComma = true
  elseif top.type == "array" then
    if self.state.current == nil then
      self.state.current = {}
      if self.state.result == nil then self.state.result = self.state.current end
    end
    table.insert(self.state.current, value)
    top.expectingComma = true
  end
end

-- Parse literal values (true, false, null)
local function parseLiteral(buffer)
  if buffer == "true" then
    return true
  elseif buffer == "false" then
    return false
  elseif buffer == "null" then
    return nil
  else
    -- Try to parse as number
    local num = tonumber(buffer)
    if num then return num end
  end
  return buffer
end

-- Parse a chunk of JSON data
function StreamingJSONParser:parse(chunk)
  self.buffer = self.buffer .. chunk
  local i = 1
  local len = #self.buffer

  while i <= len do
    local char = self.buffer:sub(i, i)

    -- Handle strings specially (they can contain JSON control characters)
    if self.state.inString then
      if self.state.escaping then
        local escapeMap = {
          ['"'] = '"',
          ["\\"] = "\\",
          ["/"] = "/",
          ["b"] = "\b",
          ["f"] = "\f",
          ["n"] = "\n",
          ["r"] = "\r",
          ["t"] = "\t",
        }
        local escapedChar = escapeMap[char]
        if escapedChar then
          self.state.stringBuffer = self.state.stringBuffer .. escapedChar
        else
          self.state.stringBuffer = self.state.stringBuffer .. char
        end
        self.state.escaping = false
      elseif char == "\\" then
        self.state.escaping = true
      elseif char == '"' then
        -- End of string
        self.state.inString = false

        -- If expecting a key in an object
        if #self.state.stack > 0 and self.state.stack[#self.state.stack].expectingKey then
          self.state.currentKey = self.state.stringBuffer
          self.state.stack[#self.state.stack].expectingKey = false
          self.state.stack[#self.state.stack].expectingColon = true
        -- If expecting a value
        elseif #self.state.stack > 0 and self.state.stack[#self.state.stack].expectingValue then
          self:addValue(self.state.stringBuffer)
        end
        self.state.stringBuffer = ""
      else
        self.state.stringBuffer = self.state.stringBuffer .. char

        -- For partial string handling, update the current object with the partial string value
        if #self.state.stack > 0 and self.state.stack[#self.state.stack].expectingValue and i == len then
          -- If we're at the end of the buffer and still in a string, store the partial value
          if self.state.current and self.state.currentKey then
            self.state.current[self.state.currentKey] = self.state.stringBuffer
          end
        end
      end

      i = i + 1
      goto continue
    end

    -- Skip whitespace when not in a string
    if string.match(char, "%s") then
      i = i + 1
      goto continue
    end

    -- Start of an object
    if char == "{" then
      local newObject = {
        type = "object",
        expectingKey = true,
        expectingComma = false,
        expectingValue = false,
        expectingColon = false,
      }
      table.insert(self.state.stack, newObject)

      -- If we're already in an object/array, save the current state
      if self.state.current then
        table.insert(self.state.parentKeys, { current = self.state.current, key = self.state.currentKey })
      end

      -- Create a new current object
      self.state.current = {}

      -- If this is the root, set result directly
      if self.state.result == nil then
        self.state.result = self.state.current
      elseif #self.state.parentKeys > 0 then
        -- Set as child of the parent
        local parent = self.state.parentKeys[#self.state.parentKeys].current
        local key = self.state.parentKeys[#self.state.parentKeys].key

        if self.state.stack[#self.state.stack - 1].type == "array" then
          table.insert(parent, self.state.current)
        else
          parent[key] = self.state.current
        end
      end

      i = i + 1
      goto continue
    end

    -- End of an object
    if char == "}" then
      table.remove(self.state.stack)

      -- Move back to parent if there is one
      if #self.state.parentKeys > 0 then
        local parentInfo = table.remove(self.state.parentKeys)
        self.state.current = parentInfo.current
        self.state.currentKey = parentInfo.key
      end

      -- If this was the last item on stack, we're complete
      if #self.state.stack == 0 then
        i = i + 1
        self.buffer = self.buffer:sub(i)
        return self.state.result, true
      else
        -- Update parent's expectations
        self.state.stack[#self.state.stack].expectingComma = true
        self.state.stack[#self.state.stack].expectingValue = false
      end

      i = i + 1
      goto continue
    end

    -- Start of an array
    if char == "[" then
      local newArray = { type = "array", expectingValue = true, expectingComma = false }
      table.insert(self.state.stack, newArray)

      -- If we're already in an object/array, save the current state
      if self.state.current then
        table.insert(self.state.parentKeys, { current = self.state.current, key = self.state.currentKey })
      end

      -- Create a new current array
      self.state.current = {}

      -- If this is the root, set result directly
      if self.state.result == nil then
        self.state.result = self.state.current
      elseif #self.state.parentKeys > 0 then
        -- Set as child of the parent
        local parent = self.state.parentKeys[#self.state.parentKeys].current
        local key = self.state.parentKeys[#self.state.parentKeys].key

        if self.state.stack[#self.state.stack - 1].type == "array" then
          table.insert(parent, self.state.current)
        else
          parent[key] = self.state.current
        end
      end

      i = i + 1
      goto continue
    end

    -- End of an array
    if char == "]" then
      table.remove(self.state.stack)

      -- Move back to parent if there is one
      if #self.state.parentKeys > 0 then
        local parentInfo = table.remove(self.state.parentKeys)
        self.state.current = parentInfo.current
        self.state.currentKey = parentInfo.key
      end

      -- If this was the last item on stack, we're complete
      if #self.state.stack == 0 then
        i = i + 1
        self.buffer = self.buffer:sub(i)
        return self.state.result, true
      else
        -- Update parent's expectations
        self.state.stack[#self.state.stack].expectingComma = true
        self.state.stack[#self.state.stack].expectingValue = false
      end

      i = i + 1
      goto continue
    end

    -- Colon between key and value
    if char == ":" then
      if #self.state.stack > 0 and self.state.stack[#self.state.stack].expectingColon then
        self.state.stack[#self.state.stack].expectingColon = false
        self.state.stack[#self.state.stack].expectingValue = true
        i = i + 1
        goto continue
      end
    end

    -- Comma between items
    if char == "," then
      if #self.state.stack > 0 and self.state.stack[#self.state.stack].expectingComma then
        self.state.stack[#self.state.stack].expectingComma = false

        if self.state.stack[#self.state.stack].type == "object" then
          self.state.stack[#self.state.stack].expectingKey = true
        else -- array
          self.state.stack[#self.state.stack].expectingValue = true
        end

        i = i + 1
        goto continue
      end
    end

    -- Start of a key or string value
    if char == '"' then
      self.state.inString = true
      self.state.stringBuffer = ""
      i = i + 1
      goto continue
    end

    -- Start of a non-string value (number, boolean, null)
    if #self.state.stack > 0 and self.state.stack[#self.state.stack].expectingValue then
      local valueBuffer = ""
      local j = i

      -- Collect until we hit a comma, closing bracket, or brace
      while j <= len do
        local currentChar = self.buffer:sub(j, j)
        if currentChar:match("[%s,}%]]") then break end
        valueBuffer = valueBuffer .. currentChar
        j = j + 1
      end

      -- Only process if we have a complete value
      if j <= len and self.buffer:sub(j, j):match("[,}%]]") then
        local value = parseLiteral(valueBuffer)
        self:addValue(value)
        i = j
        goto continue
      end

      -- If we reached the end but didn't hit a delimiter, wait for more input
      break
    end

    i = i + 1

    ::continue::
  end

  -- Update the buffer to remove processed characters
  self.buffer = self.buffer:sub(i)

  -- Return partial result if available, but indicate parsing is incomplete
  return self.state.result, false
end

return StreamingJSONParser
