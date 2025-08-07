local ReActParser = require("avante.libs.ReAct_parser2")

-- ReActパーサーのテストスイート
-- 二重呼び出し防止機能のためのメタデータ生成機能をテスト
describe("ReAct Parser", function()
  it("should parse text without tools", function()  -- ツールなしのテキスト解析テスト
    local text = "Hello, world! This is plain text."
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(1, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("Hello, world! This is plain text.", result[1].text)
    assert.is_false(result[1].partial)
    
    assert.are.equal(0, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
    assert.is_false(metadata.all_tools_complete)
    assert.is_false(metadata.has_tools)
  end)
  
  it("should parse complete tool use", function()  -- 完全なツール使用の解析テスト
    local text = [[Hello! <tool_use>{"name": "write", "input": {"path": "file.txt", "content": "test"}}</tool_use>]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(2, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("Hello! ", result[1].text)
    assert.is_false(result[1].partial)
    
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.are.equal("file.txt", result[2].tool_input.path)
    assert.are.equal("test", result[2].tool_input.content)
    assert.is_false(result[2].partial)
    
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
    assert.is_true(metadata.all_tools_complete)
    assert.is_true(metadata.has_tools)
  end)
  
  it("should parse partial tool use", function()  -- 部分的なツール使用の解析テスト
    local text = [[Hello! <tool_use>{"name": "write", "input": {"path": "file.txt"]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(2, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("Hello! ", result[1].text)
    
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.are.equal("file.txt", result[2].tool_input.path)
    assert.is_true(result[2].partial)
    
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(1, metadata.partial_tool_count)
    assert.is_false(metadata.all_tools_complete)
    assert.is_true(metadata.has_tools)
  end)
  
  it("should parse mixed complete and partial tools", function()  -- 完全・部分的ツールの混在解析テスト
    local text = [[Text <tool_use>{"name": "write", "input": {"content": "done"}}</tool_use> More text <tool_use>{"name": "read", "input": {"path":]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(4, #result)
    
    -- First text
    assert.are.equal("text", result[1].type)
    assert.are.equal("Text ", result[1].text)
    
    -- Complete tool
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.is_false(result[2].partial)
    
    -- Second text
    assert.are.equal("text", result[3].type)
    assert.are.equal(" More text ", result[3].text)
    
    -- Partial tool
    assert.are.equal("tool_use", result[4].type)
    assert.are.equal("read", result[4].tool_name)
    assert.is_true(result[4].partial)
    
    assert.are.equal(2, metadata.tool_count)
    assert.are.equal(1, metadata.partial_tool_count)
    assert.is_false(metadata.all_tools_complete)
    assert.is_true(metadata.has_tools)
  end)
  
  it("should handle invalid JSON gracefully", function()  -- 無効なJSON処理のテスト
    local text = [[Text <tool_use>invalid json</tool_use> More text]]
    local result, metadata = ReActParser.parse(text)
    
    -- Should treat the whole thing as text when JSON is invalid
    assert.are.equal(3, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("Text ", result[1].text)
    
    assert.are.equal("text", result[2].type)
    assert.are.equal("<tool_use>invalid json</tool_use>", result[2].text)
    
    assert.are.equal("text", result[3].type)
    assert.are.equal(" More text", result[3].text)
    
    assert.are.equal(0, metadata.tool_count)
    assert.is_false(metadata.has_tools)
  end)
end)