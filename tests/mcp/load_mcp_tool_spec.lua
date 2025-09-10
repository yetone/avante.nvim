local load_mcp_tool = require("avante.llm_tools.load_mcp_tool")

describe("load_mcp_tool", function()
  before_each(function()
    -- Mock mcphub module
    package.loaded["mcphub"] = {
      get_active_servers = function()
        return {
          { name = "test_server" },
        }
      end,
      get_server_tool_details = function(server_name, tool_name, callback)
        if server_name == "test_server" and tool_name == "test_tool" then
          callback({
            name = "test_tool",
            description = "Detailed test tool description",
            param = {
              fields = {
                {
                  name = "param1",
                  description = "Parameter 1 description",
                },
              },
            },
          }, nil)
        else
          callback(nil, "Tool not found")
        end
      end,
    }
    
    -- Mock vim.json
    _G.vim = _G.vim or {}
    _G.vim.json = {
      encode = function(obj)
        if obj.name == "test_tool" then
          return '{"name":"test_tool","description":"Detailed test tool description"}'
        end
        return "{}"
      end,
    }
  end)
  
  after_each(function()
    package.loaded["mcphub"] = nil
  end)
  
  it("has the correct name", function()
    assert.equals("load_mcp_tool", load_mcp_tool.name)
  end)
  
  it("has a description", function()
    assert.is_string(load_mcp_tool.description)
    assert.is_true(#load_mcp_tool.description > 0)
  end)
  
  it("has the required parameters", function()
    assert.is_table(load_mcp_tool.param)
    assert.is_table(load_mcp_tool.param.fields)
    
    local has_server_name = false
    local has_tool_name = false
    
    for _, field in ipairs(load_mcp_tool.param.fields) do
      if field.name == "server_name" then has_server_name = true end
      if field.name == "tool_name" then has_tool_name = true end
    end
    
    assert.is_true(has_server_name)
    assert.is_true(has_tool_name)
  end)
  
  it("returns error for missing server_name", function()
    local result, err = load_mcp_tool.func({
      tool_name = "test_tool",
    }, {})
    
    assert.is_nil(result)
    assert.equals("server_name is required", err)
  end)
  
  it("returns error for missing tool_name", function()
    local result, err = load_mcp_tool.func({
      server_name = "test_server",
    }, {})
    
    assert.is_nil(result)
    assert.equals("tool_name is required", err)
  end)
  
  it("returns error for non-existent server", function()
    local done = false
    
    load_mcp_tool.func({
      server_name = "non_existent_server",
      tool_name = "test_tool",
    }, {
      on_log = function() end,
      on_complete = function(result, err)
        assert.is_nil(result)
        assert.equals("Server 'non_existent_server' is not available or not connected", err)
        done = true
      end,
    })
    
    assert.is_true(done)
  end)
  
  it("successfully retrieves tool details", function()
    local done = false
    
    load_mcp_tool.func({
      server_name = "test_server",
      tool_name = "test_tool",
    }, {
      on_log = function() end,
      on_complete = function(result, err)
        assert.is_nil(err)
        assert.equals('{"name":"test_tool","description":"Detailed test tool description"}', result)
        done = true
      end,
    })
    
    assert.is_true(done)
  end)
  
  it("caches tool details", function()
    local call_count = 0
    package.loaded["mcphub"].get_server_tool_details = function(server_name, tool_name, callback)
      call_count = call_count + 1
      callback({
        name = "test_tool",
        description = "Detailed test tool description",
      }, nil)
    end
    
    -- First call
    load_mcp_tool.func({
      server_name = "test_server",
      tool_name = "test_tool",
    }, {
      on_log = function() end,
      on_complete = function() end,
    })
    
    -- Second call
    load_mcp_tool.func({
      server_name = "test_server",
      tool_name = "test_tool",
    }, {
      on_log = function() end,
      on_complete = function() end,
    })
    
    assert.equals(1, call_count)
  end)
end)
