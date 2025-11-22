-- Create a mock mcphub module
local mcphub = {
  get_hub_instance = function()
    return {
      get_tools = function()
        return {
          {
            server_name = "test_server", 
            name = "test_tool", 
            description = "A test tool description"
          }
        }
      end
    }
  end
}
package.preload['mcphub'] = function() return mcphub end

local LoadMcpTool = require("avante.llm_tools.load_mcp_tool")
local LazyLoading = require("avante.llm_tools.lazy_loading")
local Config = require("avante.config")

describe("load_mcp_tool", function()
  local original_get_hub_instance
  local LlmTools

  before_each(function()
    -- Reset lazy loading state and tool cache
    LazyLoading.reset_requested_tools()
    LazyLoading._requested_tools = {}
    LazyLoading._available_to_request = {}
    LazyLoading._tools_to_collect = {}
    LoadMcpTool._tool_cache = {}

    -- Save the original function to restore later
    original_get_hub_instance = mcphub.get_hub_instance

    -- Get LlmTools with a custom get_tools function
    LlmTools = require("avante.llm_tools")
    LlmTools.get_tools = function()
      return {
        {
          name = "test_avante_tool",
          description = "A test avante tool description"
        }
      }
    end
  end)

  after_each(function()
    -- Restore the original function
    mcphub.get_hub_instance = original_get_hub_instance
    
    -- Restore the original get_tools function
    LlmTools.get_tools = require("avante.llm_tools").get_tools
  end)

  describe("input validation", function()
    it("should return an error if server_name is missing", function()
      local result, err = LoadMcpTool.func({}, {})
      assert.is_nil(result)
      assert.equals("server_name is required", err)
    end)

    it("should return an error if tool_name is missing", function()
      local result, err = LoadMcpTool.func({server_name = "test_server"}, {})
      assert.is_nil(result)
      assert.equals("tool_name is required", err)
    end)
  end)

  describe("avante server tools", function()
    it("should register the tool to collect for avante server", function()
      -- Clear any previously collected tools
      LazyLoading._tools_to_collect = {}

      local result, err = LoadMcpTool.func({
        server_name = "avante",
        tool_name = "test_avante_tool"
      }, {})

      assert.is_nil(err)
      assert.equals("The tool test_avante_tool has now been added to the tools section of the prompt.", result)
      assert.equals(1, #LazyLoading._tools_to_collect)
      assert.equals("test_avante_tool", LazyLoading._tools_to_collect[1].name)
    end)

    it("should return an error for non-existent avante tool", function()
      local result, err = LoadMcpTool.func({
        server_name = "avante",
        tool_name = "non_existent_tool"
      }, {})

      assert.is_nil(result)
      assert.equals("Internal error: could not load tool non_existent_tool", err)
    end)
  end)

  describe("non-avante server tools", function()
    it("should return tool details for existing tool", function()
      local result, err = LoadMcpTool.func({
        server_name = "test_server", 
        tool_name = "test_tool"
      }, {})

      assert.is_nil(err)
      local tool_spec = vim.json.decode(result)
      assert.equals("test_tool", tool_spec.name)
      assert.equals("A test tool description", tool_spec.description)
    end)

    it("should return error for non-existent server", function()
      -- Replace get_hub_instance to return nil
      mcphub.get_hub_instance = function()
        return nil
      end

      local result, err = LoadMcpTool.func({
        server_name = "non_existent_server", 
        tool_name = "test_tool"
      }, {})

      assert.is_nil(result)
      assert.equals("Server 'non_existent_server' is not available or not connected", err)
    end)

    it("should return error for non-existent tool", function()
      local result, err = LoadMcpTool.func({
        server_name = "test_server", 
        tool_name = "non_existent_tool"
      }, {})

      assert.is_nil(result)
      assert.equals("Tool 'non_existent_tool' on server 'test_server' does not exist.", err)
    end)

    it("should cache tool details", function()
      local log_called = false
      
      -- First call should fetch and cache
      local result1, err1 = LoadMcpTool.func({
        server_name = "test_server", 
        tool_name = "test_tool"
      }, {
        on_log = function(msg)
          assert.is_nil(msg)  -- No log message on first call
        end
      })

      -- Second call should use cache
      local result2, err2 = LoadMcpTool.func({
        server_name = "test_server", 
        tool_name = "test_tool"
      }, {
        on_log = function(msg)
          log_called = true
          assert.equals("Cache hit for test_server:test_tool", msg)
        end
      })

      assert.is_nil(err1)
      assert.is_nil(err2)
      assert.is_true(log_called)
      assert.equals(result1, result2)
    end)
  end)

  describe("tool registration", function()
    it("should register requested tool", function()
      LazyLoading._available_to_request = {}
      LazyLoading._requested_tools = {}

      -- First, register the tool as available
      LazyLoading.register_available_tool("test_server", "test_tool")

      -- Now call load_mcp_tool
      local result, err = LoadMcpTool.func({
        server_name = "test_server", 
        tool_name = "test_tool"
      }, {})

      assert.is_nil(err)
      assert.is_true(LazyLoading.is_tool_requested("test_server", "test_tool"))
    end)
  end)
end)
