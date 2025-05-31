-- XML Parser for Lua
local XmlParser = {}

-- 流式解析器状态
local StreamParser = {}
StreamParser.__index = StreamParser

-- 创建新的流式解析器实例
function StreamParser.new()
  local parser = {
    buffer = "", -- 缓冲区存储未处理的内容
    stack = {}, -- 标签栈
    results = {}, -- 已完成的元素列表
    current = nil, -- 当前正在处理的元素
    root = nil, -- 当前根元素
    position = 1, -- 当前解析位置
    state = "ready", -- 解析状态: ready, parsing, incomplete, error
    incomplete_tag = nil, -- 未完成的标签信息
    last_error = nil, -- 最后的错误信息
  }
  setmetatable(parser, StreamParser)
  return parser
end

-- 重置解析器状态
function StreamParser:reset()
  self.buffer = ""
  self.stack = {}
  self.results = {}
  self.current = nil
  self.root = nil
  self.position = 1
  self.state = "ready"
  self.incomplete_tag = nil
  self.last_error = nil
end

-- 获取解析器状态信息
function StreamParser:getStatus()
  return {
    state = self.state,
    completed_elements = #self.results,
    stack_depth = #self.stack,
    buffer_size = #self.buffer,
    incomplete_tag = self.incomplete_tag,
    last_error = self.last_error,
    has_incomplete = self.state == "incomplete" or self.incomplete_tag ~= nil,
  }
end

-- 辅助函数：去除字符串首尾空白
local function trim(s) return s:match("^%s*(.-)%s*$") end

-- 辅助函数：解析属性
local function parseAttributes(attrStr)
  local attrs = {}
  if not attrStr or attrStr == "" then return attrs end

  -- 匹配属性模式：name="value" 或 name='value'
  for name, value in attrStr:gmatch("([-_%w]+)%s*=%s*[\"']([^\"']*)[\"']") do
    attrs[name] = value
  end
  return attrs
end

-- 辅助函数：HTML实体解码
local function decodeEntities(str)
  local entities = {
    ["&lt;"] = "<",
    ["&gt;"] = ">",
    ["&amp;"] = "&",
    ["&quot;"] = '"',
    ["&apos;"] = "'",
  }

  for entity, char in pairs(entities) do
    str = str:gsub(entity, char)
  end

  -- 处理数字实体 &#123; 和 &#x1A;
  str = str:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    return num and string.char(num) or ""
  end)
  str = str:gsub("&#x(%x+);", function(n)
    local num = tonumber(n, 16)
    return num and string.char(num) or ""
  end)

  return str
end

-- 检查是否为有效的XML标签
local function isValidXmlTag(tag, xmlContent, tagStart)
  -- 排除明显不是XML标签的内容，比如数学表达式 < 或 >
  -- 检查标签是否包含合理的XML标签格式
  if not tag:match("^<[^<>]*>$") then return false end

  -- 检查是否是合法的标签格式
  if tag:match("^</[-_%w]+>$") then return true end -- 结束标签
  if tag:match("^<[-_%w]+[^>]*/>$") then return true end -- 自闭合标签
  if tag:match("^<[-_%w]+[^>]*>$") then
    -- 对于开始标签，进行额外的上下文检查
    local tagName = tag:match("^<([-_%w]+)")

    -- 检查是否存在对应的结束标签
    local closingTag = "</" .. tagName .. ">"
    local hasClosingTag = xmlContent:find(closingTag, tagStart)

    -- 如果是单个标签且没有结束标签，可能是文本中的引用
    if not hasClosingTag then
      -- 检查前后文本，如果像是在描述而不是实际的XML结构，则不认为是有效标签
      local beforeText = xmlContent:sub(math.max(1, tagStart - 50), tagStart - 1)
      local afterText = xmlContent:sub(tagStart + #tag, math.min(#xmlContent, tagStart + #tag + 50))

      -- 如果前面有"provided in the"、"in the"等描述性文字，可能是文本引用
      if
        beforeText:match("provided in the%s*$")
        or beforeText:match("in the%s*$")
        or beforeText:match("see the%s*$")
        or beforeText:match("use the%s*$")
      then
        return false
      end

      -- 如果后面紧跟着"tag"等描述性词汇，可能是文本引用
      if afterText:match("^%s*tag") then return false end
    end

    return true
  end

  return false
end

-- 流式解析器方法：添加数据到缓冲区并解析
function StreamParser:addData(data)
  if not data or data == "" then return end

  self.buffer = self.buffer .. data
  self:parseBuffer()
end

-- 获取当前解析深度
function StreamParser:getCurrentDepth() return #self.stack end

-- 解析缓冲区中的数据
function StreamParser:parseBuffer()
  self.state = "parsing"

  while self.position <= #self.buffer do
    local remaining = self.buffer:sub(self.position)

    -- 查找下一个标签
    local tagStart, tagEnd = remaining:find("<[^>]*>")

    if not tagStart then
      -- 检查是否有未完成的开始标签（以<开始但没有>结束）
      local incompleteStart = remaining:find("<[^>]*$")
      if incompleteStart then
        local incompleteContent = remaining:sub(incompleteStart)
        -- 确保这确实是一个未完成的标签，而不是文本中的<符号
        if incompleteContent:match("^<[%w_-]") then
          -- 尝试解析未完成的开始标签
          local tagName = incompleteContent:match("^<([%w_-]+)")
          if tagName then
            -- 处理未完成标签前的文本
            if incompleteStart > 1 then
              local precedingText = trim(remaining:sub(1, incompleteStart - 1))
              if precedingText ~= "" then
                if self.current then
                  -- 如果当前在某个标签内，添加到该标签的文本内容
                  precedingText = decodeEntities(precedingText)
                  if self.current._text then
                    self.current._text = self.current._text .. precedingText
                  else
                    self.current._text = precedingText
                  end
                else
                  -- 如果是顶层文本，作为独立元素添加
                  local textElement = {
                    _name = "_text",
                    _text = decodeEntities(precedingText),
                  }
                  table.insert(self.results, textElement)
                end
              end
            end

            -- 创建未完成的元素
            local element = {
              _name = tagName,
              _attr = {},
              _state = "incomplete_start_tag",
            }

            if not self.root then
              self.root = element
              self.current = element
            elseif self.current then
              table.insert(self.stack, self.current)
              if not self.current[tagName] then self.current[tagName] = {} end
              table.insert(self.current[tagName], element)
              self.current = element
            end

            self.incomplete_tag = {
              start_pos = self.position + incompleteStart - 1,
              content = incompleteContent,
              element = element,
            }
            self.state = "incomplete"
            return
          end
        end
      end

      -- 处理剩余的文本内容
      if remaining ~= "" then
        if self.current then
          -- 检查当前深度，如果在第一层子元素中，保持原始文本
          local currentDepth = #self.stack
          if currentDepth >= 1 then
            -- 在第一层子元素中，保持原始文本不变
            if self.current._text then
              self.current._text = self.current._text .. remaining
            else
              self.current._text = remaining
            end
          else
            -- 在根级别，进行正常的文本处理
            local text = trim(remaining)
            if text ~= "" then
              text = decodeEntities(text)
              if self.current._text then
                self.current._text = self.current._text .. text
              else
                self.current._text = text
              end
            end
          end
        else
          -- 如果是顶层文本，作为独立元素添加
          local text = trim(remaining)
          if text ~= "" then
            local textElement = {
              _name = "_text",
              _text = decodeEntities(text),
            }
            table.insert(self.results, textElement)
          end
        end
      end
      self.position = #self.buffer + 1
      break
    end

    local tag = remaining:sub(tagStart, tagEnd)
    local actualTagStart = self.position + tagStart - 1
    local actualTagEnd = self.position + tagEnd - 1

    -- 检查是否为有效的XML标签
    if not isValidXmlTag(tag, self.buffer, actualTagStart) then
      -- 如果不是有效标签，将其作为普通文本处理
      local text = remaining:sub(1, tagEnd)
      if text ~= "" then
        if self.current then
          -- 检查当前深度，如果在第一层子元素中，保持原始文本
          local currentDepth = #self.stack
          if currentDepth >= 1 then
            -- 在第一层子元素中，保持原始文本不变
            if self.current._text then
              self.current._text = self.current._text .. text
            else
              self.current._text = text
            end
          else
            -- 在根级别，进行正常的文本处理
            text = trim(text)
            if text ~= "" then
              text = decodeEntities(text)
              if self.current._text then
                self.current._text = self.current._text .. text
              else
                self.current._text = text
              end
            end
          end
        else
          -- 顶层文本作为独立元素
          text = trim(text)
          if text ~= "" then
            local textElement = {
              _name = "_text",
              _text = decodeEntities(text),
            }
            table.insert(self.results, textElement)
          end
        end
      end
      self.position = actualTagEnd + 1
      goto continue
    end

    -- 处理标签前的文本内容
    if tagStart > 1 then
      local precedingText = remaining:sub(1, tagStart - 1)
      if precedingText ~= "" then
        if self.current then
          -- 如果当前在某个标签内，添加到该标签的文本内容
          -- 检查当前深度，如果在第一层子元素中，不要进行实体解码和trim
          local currentDepth = #self.stack
          if currentDepth >= 1 then
            -- 在第一层子元素中，保持原始文本不变
            if self.current._text then
              self.current._text = self.current._text .. precedingText
            else
              self.current._text = precedingText
            end
          else
            -- 在根级别，进行正常的文本处理
            precedingText = trim(precedingText)
            if precedingText ~= "" then
              precedingText = decodeEntities(precedingText)
              if self.current._text then
                self.current._text = self.current._text .. precedingText
              else
                self.current._text = precedingText
              end
            end
          end
        else
          -- 如果是顶层文本，作为独立元素添加
          precedingText = trim(precedingText)
          if precedingText ~= "" then
            local textElement = {
              _name = "_text",
              _text = decodeEntities(precedingText),
            }
            table.insert(self.results, textElement)
          end
        end
      end
    end

    -- 检查当前深度，如果已经在第一层子元素中，将所有标签作为文本处理
    local currentDepth = #self.stack
    if currentDepth >= 1 then
      -- 检查是否是当前元素的结束标签
      if tag:match("^</[-_%w]+>$") and self.current then
        local tagName = tag:match("^</([-_%w]+)>$")
        if self.current._name == tagName then
          -- 这是当前元素的结束标签，正常处理
          if not self:processTag(tag) then
            self.state = "error"
            return
          end
        else
          -- 不是当前元素的结束标签，作为文本处理
          if self.current._text then
            self.current._text = self.current._text .. tag
          else
            self.current._text = tag
          end
        end
      else
        -- 在第一层子元素中，将标签作为文本处理
        if self.current then
          if self.current._text then
            self.current._text = self.current._text .. tag
          else
            self.current._text = tag
          end
        end
      end
    else
      -- 处理标签
      if not self:processTag(tag) then
        self.state = "error"
        return
      end
    end

    self.position = actualTagEnd + 1
    ::continue::
  end

  -- 检查当前是否有未关闭的元素
  if self.current and self.current._state ~= "complete" then
    self.current._state = "incomplete_unclosed"
    self.state = "incomplete"
  elseif self.state ~= "incomplete" and self.state ~= "error" then
    self.state = "ready"
  end
end

-- 处理单个标签
function StreamParser:processTag(tag)
  if tag:match("^</[-_%w]+>$") then
    -- 结束标签
    local tagName = tag:match("^</([-_%w]+)>$")
    if self.current and self.current._name == tagName then
      -- 标记当前元素为完成状态
      self.current._state = "complete"
      self.current = table.remove(self.stack)
      -- 只有当栈为空且当前元素也为空时，说明完成了一个根级元素
      if #self.stack == 0 and not self.current and self.root then
        table.insert(self.results, self.root)
        self.root = nil
      end
    else
      self.last_error = "Mismatched closing tag: " .. tagName
      return false
    end
  elseif tag:match("^<[-_%w]+[^>]*/>$") then
    -- 自闭合标签
    local tagName, attrs = tag:match("^<([-_%w]+)([^>]*)/>")
    local element = {
      _name = tagName,
      _attr = parseAttributes(attrs),
      _state = "complete",
      children = {},
    }

    if not self.root then
      -- 直接作为根级元素添加到结果中
      table.insert(self.results, element)
    elseif self.current then
      if not self.current.children then self.current.children = {} end
      table.insert(self.current.children, element)
    end
  elseif tag:match("^<[-_%w]+[^>]*>$") then
    -- 开始标签
    local tagName, attrs = tag:match("^<([-_%w]+)([^>]*)>")
    local element = {
      _name = tagName,
      _attr = parseAttributes(attrs),
      _state = "incomplete_open", -- 标记为未完成（等待结束标签）
      children = {},
    }

    if not self.root then
      self.root = element
      self.current = element
    elseif self.current then
      table.insert(self.stack, self.current)
      if not self.current.children then self.current.children = {} end
      table.insert(self.current.children, element)
      self.current = element
    end
  end

  return true
end

-- 获取所有元素（已完成的和当前正在处理的）
function StreamParser:getAllElements()
  local all_elements = {}

  -- 添加所有已完成的元素
  for _, element in ipairs(self.results) do
    table.insert(all_elements, element)
  end

  -- 如果有当前正在处理的元素，也添加进去
  if self.root then table.insert(all_elements, self.root) end

  return all_elements
end

-- 获取已完成的元素（保留向后兼容性）
function StreamParser:getCompletedElements() return self.results end

-- 获取当前未完成的元素（保留向后兼容性）
function StreamParser:getCurrentElement() return self.root end

-- 强制完成解析（将未完成的内容作为已完成处理）
function StreamParser:finalize()
  -- 首先处理当前正在解析的元素
  if self.current then
    -- 递归设置所有未完成元素的状态
    local function markIncompleteElements(element)
      if element._state and element._state:match("incomplete") then element._state = "incomplete_unclosed" end
      -- 处理 children 数组中的子元素
      if element.children and type(element.children) == "table" then
        for _, child in ipairs(element.children) do
          if type(child) == "table" and child._name then markIncompleteElements(child) end
        end
      end
    end

    -- 标记当前元素及其所有子元素为未完成状态，但保持层次结构
    markIncompleteElements(self.current)

    -- 向上遍历栈，标记所有祖先元素
    for i = #self.stack, 1, -1 do
      local ancestor = self.stack[i]
      if ancestor._state and ancestor._state:match("incomplete") then ancestor._state = "incomplete_unclosed" end
    end
  end

  -- 只有当存在根元素时才添加到结果中
  if self.root then
    table.insert(self.results, self.root)
    self.root = nil
  end

  self.current = nil
  self.stack = {}
  self.state = "ready"
  self.incomplete_tag = nil
end

-- 创建流式解析器实例
function XmlParser.createStreamParser() return StreamParser.new() end

return XmlParser
