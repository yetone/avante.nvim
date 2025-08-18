-- JSON Streaming Parser for Lua
local JsonParser = {}

-- 流式解析器状态
local StreamParser = {}
StreamParser.__index = StreamParser

-- JSON 解析状态枚举
local PARSE_STATE = {
  READY = "ready",
  PARSING = "parsing",
  INCOMPLETE = "incomplete",
  ERROR = "error",
  OBJECT_START = "object_start",
  OBJECT_KEY = "object_key",
  OBJECT_VALUE = "object_value",
  ARRAY_START = "array_start",
  ARRAY_VALUE = "array_value",
  STRING = "string",
  NUMBER = "number",
  LITERAL = "literal",
}

-- 创建新的流式解析器实例
function StreamParser.new()
  local parser = {
    buffer = "", -- 缓冲区存储未处理的内容
    position = 1, -- 当前解析位置
    state = PARSE_STATE.READY, -- 解析状态
    stack = {}, -- 解析栈，存储嵌套的对象和数组
    results = {}, -- 已完成的 JSON 对象列表
    current = nil, -- 当前正在构建的对象
    current_key = nil, -- 当前对象的键
    escape_next = false, -- 下一个字符是否被转义
    string_delimiter = nil, -- 字符串分隔符 (' 或 ")
    last_error = nil, -- 最后的错误信息
    incomplete_string = "", -- 未完成的字符串内容
    incomplete_number = "", -- 未完成的数字内容
    incomplete_literal = "", -- 未完成的字面量内容
    depth = 0, -- 当前嵌套深度
  }
  setmetatable(parser, StreamParser)
  return parser
end

-- 重置解析器状态
function StreamParser:reset()
  self.buffer = ""
  self.position = 1
  self.state = PARSE_STATE.READY
  self.stack = {}
  self.results = {}
  self.current = nil
  self.current_key = nil
  self.escape_next = false
  self.string_delimiter = nil
  self.last_error = nil
  self.incomplete_string = ""
  self.incomplete_number = ""
  self.incomplete_literal = ""
  self.depth = 0
end

-- 获取解析器状态信息
function StreamParser:getStatus()
  return {
    state = self.state,
    completed_objects = #self.results,
    stack_depth = #self.stack,
    buffer_size = #self.buffer,
    current_depth = self.depth,
    last_error = self.last_error,
    has_incomplete = self.state == PARSE_STATE.INCOMPLETE,
    position = self.position,
  }
end

-- 辅助函数：检查字符是否为空白字符
local function isWhitespace(char) return char == " " or char == "\t" or char == "\n" or char == "\r" end

-- 辅助函数：检查字符是否为数字开始字符
local function isNumberStart(char) return char == "-" or (char >= "0" and char <= "9") end

-- 辅助函数：检查字符是否为数字字符
local function isNumberChar(char)
  return (char >= "0" and char <= "9") or char == "." or char == "e" or char == "E" or char == "+" or char == "-"
end

-- 辅助函数：解析 JSON 字符串转义
local function unescapeJsonString(str)
  local result = str:gsub("\\(.)", function(char)
    if char == "n" then
      return "\n"
    elseif char == "r" then
      return "\r"
    elseif char == "t" then
      return "\t"
    elseif char == "b" then
      return "\b"
    elseif char == "f" then
      return "\f"
    elseif char == "\\" then
      return "\\"
    elseif char == "/" then
      return "/"
    elseif char == '"' then
      return '"'
    else
      return "\\" .. char -- 保持未知转义序列
    end
  end)

  -- 处理 Unicode 转义序列 \uXXXX
  result = result:gsub("\\u(%x%x%x%x)", function(hex)
    local codepoint = tonumber(hex, 16)
    if codepoint then
      -- 简单的 UTF-8 编码（仅支持基本多文种平面）
      if codepoint < 0x80 then
        return string.char(codepoint)
      elseif codepoint < 0x800 then
        return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + (codepoint % 0x40))
      else
        return string.char(
          0xE0 + math.floor(codepoint / 0x1000),
          0x80 + math.floor((codepoint % 0x1000) / 0x40),
          0x80 + (codepoint % 0x40)
        )
      end
    end
    return "\\u" .. hex -- 保持原样如果解析失败
  end)

  return result
end

-- 辅助函数：解析数字
local function parseNumber(str)
  local num = tonumber(str)
  if num then return num end
  return nil
end

-- 辅助函数：解析字面量（true, false, null）
local function parseLiteral(str)
  if str == "true" then
    return true
  elseif str == "false" then
    return false
  elseif str == "null" then
    return nil
  else
    return nil, "Invalid literal: " .. str
  end
end

-- 跳过空白字符
function StreamParser:skipWhitespace()
  while self.position <= #self.buffer and isWhitespace(self.buffer:sub(self.position, self.position)) do
    self.position = self.position + 1
  end
end

-- 获取当前字符
function StreamParser:getCurrentChar()
  if self.position <= #self.buffer then return self.buffer:sub(self.position, self.position) end
  return nil
end

-- 前进一个字符位置
function StreamParser:advance() self.position = self.position + 1 end

-- 设置错误状态
function StreamParser:setError(message)
  self.state = PARSE_STATE.ERROR
  self.last_error = message
end

-- 推入栈
function StreamParser:pushStack(value, type)
  -- Save the current key when pushing to stack
  table.insert(self.stack, { value = value, type = type, key = self.current_key })
  self.current_key = nil -- Reset for the new context
  self.depth = self.depth + 1
end

-- 弹出栈
function StreamParser:popStack()
  if #self.stack > 0 then
    local item = table.remove(self.stack)
    self.depth = self.depth - 1
    return item
  end
  return nil
end

-- 获取栈顶元素
function StreamParser:peekStack()
  if #self.stack > 0 then return self.stack[#self.stack] end
  return nil
end

-- 添加值到当前容器
function StreamParser:addValue(value)
  local parent = self:peekStack()

  if not parent then
    -- 顶层值，直接添加到结果
    table.insert(self.results, value)
    self.current = nil
  elseif parent.type == "object" then
    -- 添加到对象
    if self.current_key then
      parent.value[self.current_key] = value
      self.current_key = nil
    else
      self:setError("Object value without key")
      return false
    end
  elseif parent.type == "array" then
    -- 添加到数组
    table.insert(parent.value, value)
  else
    self:setError("Invalid parent type: " .. tostring(parent.type))
    return false
  end

  return true
end

-- 解析字符串
function StreamParser:parseString()
  local delimiter = self:getCurrentChar()

  if delimiter ~= '"' and delimiter ~= "'" then
    self:setError("Expected string delimiter")
    return nil
  end

  self.string_delimiter = delimiter
  self:advance() -- 跳过开始引号

  local content = self.incomplete_string

  while self.position <= #self.buffer do
    local char = self:getCurrentChar()

    if self.escape_next then
      content = content .. char
      self.escape_next = false
      self:advance()
    elseif char == "\\" then
      content = content .. char
      self.escape_next = true
      self:advance()
    elseif char == delimiter then
      -- 字符串结束
      self:advance() -- 跳过结束引号
      local unescaped = unescapeJsonString(content)
      self.incomplete_string = ""
      self.string_delimiter = nil
      self.escape_next = false
      return unescaped
    else
      content = content .. char
      self:advance()
    end
  end

  -- 字符串未完成
  self.incomplete_string = content
  self.state = PARSE_STATE.INCOMPLETE
  return nil
end

-- 继续解析未完成的字符串
function StreamParser:continueStringParsing()
  local content = self.incomplete_string
  local delimiter = self.string_delimiter

  while self.position <= #self.buffer do
    local char = self:getCurrentChar()

    if self.escape_next then
      content = content .. char
      self.escape_next = false
      self:advance()
    elseif char == "\\" then
      content = content .. char
      self.escape_next = true
      self:advance()
    elseif char == delimiter then
      -- 字符串结束
      self:advance() -- 跳过结束引号
      local unescaped = unescapeJsonString(content)
      self.incomplete_string = ""
      self.string_delimiter = nil
      self.escape_next = false
      return unescaped
    else
      content = content .. char
      self:advance()
    end
  end

  -- 字符串仍未完成
  self.incomplete_string = content
  self.state = PARSE_STATE.INCOMPLETE
  return nil
end

-- 解析数字
function StreamParser:parseNumber()
  local content = self.incomplete_number

  while self.position <= #self.buffer do
    local char = self:getCurrentChar()

    if isNumberChar(char) then
      content = content .. char
      self:advance()
    else
      -- 数字结束
      local number = parseNumber(content)
      if number then
        self.incomplete_number = ""
        return number
      else
        self:setError("Invalid number format: " .. content)
        return nil
      end
    end
  end

  -- 数字可能未完成，但也可能已经是有效数字
  local number = parseNumber(content)
  if number then
    self.incomplete_number = ""
    return number
  else
    -- 数字未完成
    self.incomplete_number = content
    self.state = PARSE_STATE.INCOMPLETE
    return nil
  end
end

-- 解析字面量
function StreamParser:parseLiteral()
  local content = self.incomplete_literal

  while self.position <= #self.buffer do
    local char = self:getCurrentChar()

    if char and char:match("[%w]") then
      content = content .. char
      self:advance()
    else
      -- 字面量结束
      local value, err = parseLiteral(content)
      if err then
        self:setError(err)
        return nil
      end
      self.incomplete_literal = ""
      return value
    end
  end

  -- 检查当前内容是否已经是完整的字面量
  local value, err = parseLiteral(content)
  if not err then
    self.incomplete_literal = ""
    return value
  end

  -- 字面量未完成
  self.incomplete_literal = content
  self.state = PARSE_STATE.INCOMPLETE
  return nil
end

-- 流式解析器方法：添加数据到缓冲区并解析
function StreamParser:addData(data)
  if not data or data == "" then return end

  self.buffer = self.buffer .. data
  self:parseBuffer()
end

-- 解析缓冲区中的数据
function StreamParser:parseBuffer()
  -- 如果当前状态是不完整，先尝试继续之前的解析
  if self.state == PARSE_STATE.INCOMPLETE then
    if self.incomplete_string ~= "" and self.string_delimiter then
      -- Continue parsing the incomplete string
      local str = self:continueStringParsing()
      if str then
        local parent = self:peekStack()
        if parent and parent.type == "object" and not self.current_key then
          self.current_key = str
        else
          if not self:addValue(str) then return end
        end
      elseif self.state == PARSE_STATE.ERROR then
        return
      elseif self.state == PARSE_STATE.INCOMPLETE then
        return
      end
    elseif self.incomplete_number ~= "" then
      local num = self:parseNumber()
      if num then
        if not self:addValue(num) then return end
      elseif self.state == PARSE_STATE.ERROR then
        return
      elseif self.state == PARSE_STATE.INCOMPLETE then
        return
      end
    elseif self.incomplete_literal ~= "" then
      local value = self:parseLiteral()
      if value ~= nil or self.incomplete_literal == "null" then
        if not self:addValue(value) then return end
      elseif self.state == PARSE_STATE.ERROR then
        return
      elseif self.state == PARSE_STATE.INCOMPLETE then
        return
      end
    end
  end

  self.state = PARSE_STATE.PARSING

  while self.position <= #self.buffer and self.state == PARSE_STATE.PARSING do
    self:skipWhitespace()

    if self.position > #self.buffer then break end

    local char = self:getCurrentChar()

    if not char then break end

    -- 根据当前状态和字符进行解析
    if char == "{" then
      -- 对象开始
      local obj = {}
      self:pushStack(obj, "object")
      self.current = obj
      -- Reset current_key for the new object context
      self.current_key = nil
      self:advance()
    elseif char == "}" then
      -- 对象结束
      local parent = self:popStack()
      if not parent or parent.type ~= "object" then
        self:setError("Unexpected }")
        return
      end

      -- Restore the key context from when this object was pushed
      self.current_key = parent.key

      if not self:addValue(parent.value) then return end
      self:advance()
    elseif char == "[" then
      -- 数组开始
      local arr = {}
      self:pushStack(arr, "array")
      self.current = arr
      self:advance()
    elseif char == "]" then
      -- 数组结束
      local parent = self:popStack()
      if not parent or parent.type ~= "array" then
        self:setError("Unexpected ]")
        return
      end

      -- Restore the key context from when this array was pushed
      self.current_key = parent.key

      if not self:addValue(parent.value) then return end
      self:advance()
    elseif char == '"' then
      -- 字符串（只支持双引号，这是标准JSON）
      local str = self:parseString()
      if self.state == PARSE_STATE.INCOMPLETE then
        return
      elseif self.state == PARSE_STATE.ERROR then
        return
      end

      local parent = self:peekStack()
      -- Check if we're directly inside an object and need a key
      if parent and parent.type == "object" and not self.current_key then
        -- 对象的键
        self.current_key = str
      else
        -- 值
        if not self:addValue(str) then return end
      end
    elseif char == ":" then
      -- 键值分隔符
      if not self.current_key then
        self:setError("Unexpected :")
        return
      end
      self:advance()
    elseif char == "," then
      -- 值分隔符
      self:advance()
    elseif isNumberStart(char) then
      -- 数字
      local num = self:parseNumber()
      if self.state == PARSE_STATE.INCOMPLETE then
        return
      elseif self.state == PARSE_STATE.ERROR then
        return
      end

      if num ~= nil and not self:addValue(num) then return end
    elseif char:match("[%a]") then
      -- 字面量 (true, false, null)
      local value = self:parseLiteral()
      if self.state == PARSE_STATE.INCOMPLETE then
        return
      elseif self.state == PARSE_STATE.ERROR then
        return
      end

      if not self:addValue(value) then return end
    else
      self:setError("Unexpected character: " .. char .. " at position " .. self.position)
      return
    end
  end

  -- 如果解析完成且没有错误，设置为就绪状态
  if self.state == PARSE_STATE.PARSING and #self.stack == 0 then
    self.state = PARSE_STATE.READY
  elseif self.state == PARSE_STATE.PARSING and #self.stack > 0 then
    self.state = PARSE_STATE.INCOMPLETE
  end
end

-- 获取所有已完成的 JSON 对象
function StreamParser:getAllObjects()
  -- 如果有不完整的数据，自动完成解析
  if
    self.state == PARSE_STATE.INCOMPLETE
    or self.incomplete_string ~= ""
    or self.incomplete_number ~= ""
    or self.incomplete_literal ~= ""
    or #self.stack > 0
  then
    self:finalize()
  end
  return self.results
end

-- 获取已完成的对象（保留向后兼容性）
function StreamParser:getCompletedObjects() return self.results end

-- 获取当前未完成的对象（保留向后兼容性）
function StreamParser:getCurrentObject()
  if #self.stack > 0 then return self.stack[1].value end
  return self.current
end

-- 强制完成解析（将未完成的内容标记为不完整但仍然返回）
function StreamParser:finalize()
  -- 如果有未完成的字符串、数字或字面量，尝试解析
  if self.incomplete_string ~= "" or self.string_delimiter then
    -- 未完成的字符串，进行转义处理以便用户使用
    -- 虽然字符串不完整，但用户需要使用转义后的内容
    local unescaped = unescapeJsonString(self.incomplete_string)
    local parent = self:peekStack()
    if parent and parent.type == "object" and not self.current_key then
      self.current_key = unescaped
    else
      self:addValue(unescaped)
    end
    self.incomplete_string = ""
    self.string_delimiter = nil
    self.escape_next = false
  end

  if self.incomplete_number ~= "" then
    -- 未完成的数字，尝试解析当前内容
    local number = parseNumber(self.incomplete_number)
    if number then
      self:addValue(number)
      self.incomplete_number = ""
    end
  end

  if self.incomplete_literal ~= "" then
    -- 未完成的字面量，尝试解析当前内容
    local value, err = parseLiteral(self.incomplete_literal)
    if not err then
      self:addValue(value)
      self.incomplete_literal = ""
    end
  end

  -- 将栈中的所有未完成对象标记为不完整并添加到结果
  -- 从栈底开始处理，确保正确的嵌套结构
  local stack_items = {}
  while #self.stack > 0 do
    local item = self:popStack()
    table.insert(stack_items, 1, item) -- 插入到开头，保持原始顺序
  end

  -- 重新构建嵌套结构
  local root_object = nil
  for i, item in ipairs(stack_items) do
    if item and item.value then
      -- 标记为不完整
      if type(item.value) == "table" then item.value._incomplete = true end

      if i == 1 then
        -- 第一个（最外层）对象
        root_object = item.value
      else
        -- 嵌套对象，需要添加到父对象中
        local parent_item = stack_items[i - 1]
        if parent_item and parent_item.value then
          if parent_item.type == "object" and item.key then
            parent_item.value[item.key] = item.value
          elseif parent_item.type == "array" then
            table.insert(parent_item.value, item.value)
          end
        end
      end
    end
  end

  -- 只添加根对象到结果
  if root_object then table.insert(self.results, root_object) end

  self.current = nil
  self.current_key = nil
  self.state = PARSE_STATE.READY
end

-- 获取当前解析深度
function StreamParser:getCurrentDepth() return self.depth end

-- 检查是否有错误
function StreamParser:hasError() return self.state == PARSE_STATE.ERROR end

-- 获取错误信息
function StreamParser:getError() return self.last_error end

-- 创建流式解析器实例
function JsonParser.createStreamParser() return StreamParser.new() end

-- 简单的一次性解析函数（非流式）
function JsonParser.parse(jsonString)
  local parser = StreamParser.new()
  parser:addData(jsonString)
  parser:finalize()

  if parser:hasError() then return nil, parser:getError() end

  local results = parser:getAllObjects()
  if #results == 1 then
    return results[1]
  elseif #results > 1 then
    return results
  else
    return nil, "No valid JSON found"
  end
end

return JsonParser
