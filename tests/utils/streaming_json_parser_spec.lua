local StreamingJSONParser = require("avante.utils.streaming_json_parser")

describe("StreamingJSONParser", function()
  local parser

  before_each(function() parser = StreamingJSONParser:new() end)

  describe("initialization", function()
    it("should create a new parser with empty state", function()
      assert.is_not_nil(parser)
      assert.equals("", parser.buffer)
      assert.is_not_nil(parser.state)
      assert.is_false(parser.state.inString)
      assert.is_false(parser.state.escaping)
      assert.is_table(parser.state.stack)
      assert.equals(0, #parser.state.stack)
      assert.is_nil(parser.state.result)
      assert.is_nil(parser.state.currentKey)
      assert.is_nil(parser.state.current)
      assert.is_table(parser.state.parentKeys)
    end)
  end)

  describe("parse", function()
    it("should parse a complete simple JSON object", function()
      local result, complete = parser:parse('{"key": "value"}')
      assert.is_true(complete)
      assert.is_table(result)
      assert.equals("value", result.key)
    end)

    it("should parse breaklines", function()
      local result, complete = parser:parse('{"key": "value\nv"}')
      assert.is_true(complete)
      assert.is_table(result)
      assert.equals("value\nv", result.key)
    end)

    it("should parse a complete simple JSON array", function()
      local result, complete = parser:parse("[1, 2, 3]")
      assert.is_true(complete)
      assert.is_table(result)
      assert.equals(1, result[1])
      assert.equals(2, result[2])
      assert.equals(3, result[3])
    end)

    it("should handle streaming JSON in multiple chunks", function()
      local result1, complete1 = parser:parse('{"name": "John')
      assert.is_false(complete1)
      assert.is_table(result1)
      assert.equals("John", result1.name)

      local result2, complete2 = parser:parse('", "age": 30}')
      assert.is_true(complete2)
      assert.is_table(result2)
      assert.equals("John", result2.name)
      assert.equals(30, result2.age)
    end)

    it("should handle streaming string field", function()
      local result1, complete1 = parser:parse('{"name": {"first": "John')
      assert.is_false(complete1)
      assert.is_table(result1)
      assert.equals("John", result1.name.first)
    end)

    it("should parse nested objects", function()
      local json = [[{
        "person": {
          "name": "John",
          "age": 30,
          "address": {
            "city": "New York",
            "zip": "10001"
          }
        }
      }]]

      local result, complete = parser:parse(json)
      assert.is_true(complete)
      assert.is_table(result)
      assert.is_table(result.person)
      assert.equals("John", result.person.name)
      assert.equals(30, result.person.age)
      assert.is_table(result.person.address)
      assert.equals("New York", result.person.address.city)
      assert.equals("10001", result.person.address.zip)
    end)

    it("should parse nested arrays", function()
      local json = [[{
        "matrix": [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9]
        ]
      }]]

      local result, complete = parser:parse(json)
      assert.is_true(complete)
      assert.is_table(result)
      assert.is_table(result.matrix)
      assert.equals(3, #result.matrix)
      assert.equals(1, result.matrix[1][1])
      assert.equals(5, result.matrix[2][2])
      assert.equals(9, result.matrix[3][3])
    end)

    it("should handle boolean values", function()
      local result, complete = parser:parse('{"success": true, "failed": false}')
      assert.is_true(complete)
      assert.is_table(result)
      assert.is_true(result.success)
      assert.is_false(result.failed)
    end)

    it("should handle null values", function()
      local result, complete = parser:parse('{"value": null}')
      assert.is_true(complete)
      assert.is_table(result)
      assert.is_nil(result.value)
    end)

    it("should handle escaped characters in strings", function()
      local result, complete = parser:parse('{"text": "line1\\nline2\\t\\"quoted\\""}')
      assert.is_true(complete)
      assert.is_table(result)
      assert.equals('line1\nline2\t"quoted"', result.text)
    end)

    it("should handle numbers correctly", function()
      local result, complete = parser:parse('{"integer": 42, "float": 3.14, "negative": -10, "exponent": 1.2e3}')
      assert.is_true(complete)
      assert.is_table(result)
      assert.equals(42, result.integer)
      assert.equals(3.14, result.float)
      assert.equals(-10, result.negative)
      assert.equals(1200, result.exponent)
    end)

    it("should handle streaming complex JSON", function()
      local chunks = {
        '{"data": [{"id": 1, "info": {"name":',
        ' "Product A", "active": true}}, {"id": 2, ',
        '"info": {"name": "Product B", "active": false',
        '}}], "total": 2}',
      }

      local complete = false
      local result

      for _, chunk in ipairs(chunks) do
        result, complete = parser:parse(chunk)
      end

      assert.is_true(complete)
      assert.is_table(result)
      assert.equals(2, #result.data)
      assert.equals(1, result.data[1].id)
      assert.equals("Product A", result.data[1].info.name)
      assert.is_true(result.data[1].info.active)
      assert.equals(2, result.data[2].id)
      assert.equals("Product B", result.data[2].info.name)
      assert.is_false(result.data[2].info.active)
      assert.equals(2, result.total)
    end)

    it("should reset the parser state correctly", function()
      parser:parse('{"key": "value"}')
      parser:reset()

      assert.equals("", parser.buffer)
      assert.is_false(parser.state.inString)
      assert.is_false(parser.state.escaping)
      assert.is_table(parser.state.stack)
      assert.equals(0, #parser.state.stack)
      assert.is_nil(parser.state.result)
      assert.is_nil(parser.state.currentKey)
      assert.is_nil(parser.state.current)
      assert.is_table(parser.state.parentKeys)
    end)

    it("should return partial results for incomplete JSON", function()
      parser:reset()
      local result, complete = parser:parse('{"stream": [1, 2,')
      assert.is_false(complete)
      assert.is_table(result)
      assert.is_table(result.stream)
      assert.equals(1, result.stream[1])
      assert.equals(2, result.stream[2])

      -- We need exactly one item in the stack (the array)
      assert.equals(2, #parser.state.stack)
    end)

    it("should handle whitespace correctly", function()
      parser:reset()
      local result, complete = parser:parse('{"key1": "value1", "key2": 42}')
      assert.is_true(complete)
      assert.is_table(result)
      assert.equals("value1", result.key1)
      assert.equals(42, result.key2)
    end)

    it("should provide access to partial results during streaming", function()
      parser:parse('{"name": "John", "items": [')

      local partial = parser:getCurrentPartial()
      assert.is_table(partial)
      assert.equals("John", partial.name)
      assert.is_table(partial.items)

      parser:parse("1, 2]")
      local result, complete = parser:parse("}")

      assert.is_true(complete)
      assert.equals("John", result.name)
      assert.equals(1, result.items[1])
      assert.equals(2, result.items[2])
    end)
  end)
end)
