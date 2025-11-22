local Config = require("avante.config")
local load_mcp_tool = require("avante.llm_tools.load_mcp_tool")
local llm_tools = require("avante.llm_tools")
local LazyLoading = require("avante.llm_tools.lazy_loading")
local stub = require("luassert.stub")

describe("load_mcp_tool for lazy loading", function()
  local original_config

  before_each(function()
    -- Store original config
    original_config = vim.deepcopy(Config)

    -- Setup default lazy loading config
    Config.lazy_loading = {
      enabled = true,
      always_eager = {
        "think",
        "attempt_completion",
        "load_mcp_tool",
        "add_todos",
        "update_todo_status",
      },
    }

    -- Mock llm_tools.get_tools to return test tools
    stub(llm_tools, "get_tools", function()
      return {
        { name = "think", description = "This is the think tool with a detailed description." },
        { name = "test_tool", description = "This is a test tool" },
      }
    end)

    -- Mock LazyLoading functions
    stub(LazyLoading, "register_requested_tool", function() end)
    stub(LazyLoading, "register_tool_to_collect", function() end)

    -- Mock mcphub module
    package.loaded["mcphub"] = {
      get_hub_instance = function()
        return {
          get_tools = function()
            return {
              {
                server_name = "test_server",
                name = "test_tool",
                description = "This is a test tool with a detailed description. It has multiple sentences.",
                param = {
                  fields = {
                    {
                      name = "param1",
                      description = "Parameter 1 with a detailed description. More details here.",
                      type = "string",
                    },
                    {
                      name = "param2",
                      description = "Parameter 2 with a detailed description. More details here.",
                      type = "number",
                    },
                  },
                },
                returns = {
                  {
                    name = "result",
                    description = "The result of the tool execution. More details here.",
                    type = "string",
                  },
                },
              },
            }
          end,
        }
      end,
      get_active_servers = function()
        return {
          { name = "test_server" },
        }
      end,
    }

    -- Mock vim.json
    _G.vim = _G.vim or {}
    _G.vim.json = {
      encode = function(obj)
        if obj.name == "test_tool" then
          return '{"name":"test_tool","description":"This is a test tool with a detailed description. It has multiple sentences."}'
        elseif obj.name == "think" then
          return '{"name":"think","description":"This is the think tool with a detailed description."}'
        end
        return "{}"
      end,
    }

    -- Mock vim.deepcopy if it doesn't exist
    if not _G.vim.deepcopy then
      _G.vim.deepcopy = function(obj)
        local copy = {}
        for k, v in pairs(obj) do
          if type(v) == "table" then
            copy[k] = _G.vim.deepcopy(v)
          else
            copy[k] = v
          end
        end
        return copy
      end
    end
    
    -- Mock vim.fn.json_decode if needed
    _G.vim.fn = _G.vim.fn or {}
    _G.vim.fn.json_decode = _G.vim.fn.json_decode or function(json_str)
      if json_str:match("test_tool") then
        return {
          name = "test_tool",
          description = "This is a test tool with a detailed description. It has multiple sentences."
        }
      elseif json_str:match("think") then
        return {
          name = "think",
          description = "This is the think tool with a detailed description."
        }
      end
      return {}
    end
  end)

  after_each(function()
    -- Restore original config
    Config = original_config

    -- Clean up mocks
    package.loaded["mcphub"] = nil
    llm_tools.get_tools:revert()
    LazyLoading.register_requested_tool:revert()
    LazyLoading.register_tool_to_collect:revert()
  end)

  it("loads detailed information for MCP server tools", function()
    local done = false

    load_mcp_tool.func({
      server_name = "test_server",
      tool_name = "test_tool",
    }, {
      on_log = function() end,
      on_complete = function(result, err)
        assert.is_nil(err)
        assert.is_not_nil(result)
        done = true
      end,
    })

    assert.is_true(done)
  end)

  it("loads detailed information for built-in avante tools", function()
    local done = false

    load_mcp_tool.func({
      server_name = "avante",
      tool_name = "think",
    }, {
      on_log = function() end,
      on_complete = function(result, err)
        assert.is_nil(err)
        assert.is_not_nil(result)
        assert.equals("The tool think has now been added to the tools section of the prompt.", result)
        done = true
      end,
    })

    assert.is_true(done)
    assert.stub(LazyLoading.register_requested_tool).was_called_with("avante", "think")
    assert.stub(LazyLoading.register_tool_to_collect).was_called(1)
  end)

  it("caches tool information for subsequent requests", function()
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

  it("returns error for missing parameters", function()
    local result, err = load_mcp_tool.func({
      server_name = "test_server",
    }, {})

    assert.is_nil(result)
    assert.equals("tool_name is required", err)

    result, err = load_mcp_tool.func({
      tool_name = "test_tool",
    }, {})

    assert.is_nil(result)
    assert.equals("server_name is required", err)
  end)

  it("returns error for non-existent server", function()
    local done = false

    -- Mock get_active_servers to return an empty array
    local original_get_active_servers = package.loaded["mcphub"].get_active_servers
    package.loaded["mcphub"].get_active_servers = function()
      return {}
    end

    -- Override get_hub_instance to return a hub that throws an error
    local original_get_hub_instance = package.loaded["mcphub"].get_hub_instance
    package.loaded["mcphub"].get_hub_instance = function()
      return nil
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

    -- Restore original functions
    package.loaded["mcphub"].get_active_servers = original_get_active_servers
    package.loaded["mcphub"].get_hub_instance = original_get_hub_instance

    assert.is_true(done)
  end)

  it("returns error for non-existent tool", function()
    local done = false

    -- Mock get_hub_instance to return a hub with no tools
    local original_get_hub_instance = package.loaded["mcphub"].get_hub_instance
    package.loaded["mcphub"].get_hub_instance = function()
      return {
        get_tools = function()
          return {
            -- Return a tool with a different name than the one we're looking for
            {
              server_name = "test_server",
              name = "different_tool",
              description = "This is a different tool"
            }
          }
        end,
      }
    end

    load_mcp_tool.func({
      server_name = "test_server",
      tool_name = "non_existent_tool",
    }, {
      on_log = function() end,
      on_complete = function(result, err)
        assert.is_nil(result)
        assert.equals("Tool 'non_existent_tool' on server 'test_server' does not exist.", err)
        done = true
      end,
    })

    -- Restore original function
    package.loaded["mcphub"].get_hub_instance = original_get_hub_instance

    assert.is_true(done)
  end)
end)
