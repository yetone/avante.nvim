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

    -- Mock get_active_servers to return an empty array
    local original_get_active_servers = package.loaded["mcphub"].get_active_servers
    package.loaded["mcphub"].get_active_servers = function()
      return {}
    end

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

    -- Restore original function
    package.loaded["mcphub"].get_active_servers = original_get_active_servers

    assert.is_true(done)
  end)

  it("successfully retrieves tool details", function()
    local done = false

    -- Mock hub instance with proper tools
    local mock_hub = {
      get_tools = function()
        return {
          {
            server_name = "test_server",
            name = "test_tool",
            description = "Detailed test tool description"
          }
        }
      end
    }

    -- Override get_hub_instance to return our mock
    local original_get_hub_instance = package.loaded["mcphub"].get_hub_instance
    package.loaded["mcphub"].get_hub_instance = function()
      return mock_hub
    end

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

    -- Restore original function
    package.loaded["mcphub"].get_hub_instance = original_get_hub_instance

    assert.is_true(done)
  end)

  it("caches tool details", function()
    -- Reset the cache before the test
    load_mcp_tool._tool_cache = {}

    local call_count = 0

    -- Create a local mock_hub for this test
    local mock_hub = {
      get_tools = function()
        call_count = call_count + 1
        return {
          {
            server_name = "test_server",
            name = "test_tool",
            description = "This is a test tool with a detailed description. It has multiple sentences."
          }
        }
      end
    }

    -- Override get_hub_instance to return our mock
    local original_get_hub_instance = package.loaded["mcphub"].get_hub_instance
    package.loaded["mcphub"].get_hub_instance = function()
      return mock_hub
    end

    -- First call should fetch the tool
    load_mcp_tool.func({
      server_name = "test_server",
      tool_name = "test_tool",
    }, {
      on_log = function() end,
    })

    -- Second call should use the cache
    load_mcp_tool.func({
      server_name = "test_server",
      tool_name = "test_tool",
    }, {
      on_log = function() end,
    })

    -- Restore original function
    package.loaded["mcphub"].get_hub_instance = original_get_hub_instance

    -- Verify that get_tools was only called once
    assert.equals(1, call_count)
  end)

  it("caches tool details with async callbacks", function()
    -- Reset the tool cache before the test
    load_mcp_tool._tool_cache = {}

    local call_count = 0

    -- Mock hub instance with proper tools
    local mock_hub = {
      get_tools = function()
        call_count = call_count + 1
        return {
          {
            server_name = "test_server",
            name = "test_tool",
            description = "Detailed test tool description"
          }
        }
      end
    }

    -- Override get_hub_instance to return our mock
    local original_get_hub_instance = package.loaded["mcphub"].get_hub_instance
    package.loaded["mcphub"].get_hub_instance = function()
      return mock_hub
    end

    local completed_first = false
    local completed_second = false

    -- First call
    load_mcp_tool.func({
      server_name = "test_server",
      tool_name = "test_tool",
    }, {
      on_log = function() end,
      on_complete = function()
        completed_first = true

        -- Make second call after first one completes
        load_mcp_tool.func({
          server_name = "test_server",
          tool_name = "test_tool",
        }, {
          on_log = function() end,
          on_complete = function()
            completed_second = true
          end,
        })
      end,
    })

    -- Wait for both calls to complete
    assert.is_true(completed_first)
    assert.is_true(completed_second)

    -- Restore original function
    package.loaded["mcphub"].get_hub_instance = original_get_hub_instance

    -- Verify that the tools were only retrieved once
    assert.equals(1, call_count)
  end)
end)
