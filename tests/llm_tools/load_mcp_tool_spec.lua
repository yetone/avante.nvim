-- Create a mock mcphub module
local mcphub = {
  get_hub_instance = function()
    return {
      get_tools = function()
        return {
          {
            server_name = "test_server",
            name = "test_tool",
            description = "A test tool description",
            inputSchema = {
              type = "object",
              properties = {
                param1 = {
                  type = "string",
                  description = "First parameter"
                }
              }
            }
          }
        }
      end,
    }
  end,
}
package.preload["mcphub"] = function() return mcphub end

-- Create mock mcphub.utils.prompt module
local mcphub_prompt = {
  get_description = function(tool)
    return tool.description or "No description"
  end,
  get_inputSchema = function(tool)
    return tool.inputSchema or {}
  end
}
package.preload['mcphub.utils.prompt'] = function() return mcphub_prompt end

-- Create mock mcphub.utils module
local mcphub_utils = {
  pretty_json = function(json_str)
    return json_str
  end
}
package.preload['mcphub.utils'] = function() return mcphub_utils end

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
          description = "A test avante tool description",
        },
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
      -- When both are missing, tool_name validation runs second and overwrites the error
      assert.equals("tool_name is required", err)
    end)

    it("should return an error if tool_name is missing", function()
      local result, err = LoadMcpTool.func({ server_name = "test_server" }, {})
      assert.is_nil(result)
      assert.equals("tool_name is required", err)
    end)
  end)

  describe("avante server tools", function()
    it("should register the tool to collect for avante server", function()
      -- Clear any previously collected tools
      LazyLoading._tools_to_collect = {}

      -- Register the tool as available first
      LazyLoading.register_available_tool("avante", "test_avante_tool")

      local result, err = LoadMcpTool.func({
        server_name = "avante",
        tool_name = "test_avante_tool",
      }, {})

      assert.is_nil(err)
      assert.equals("The tool test_avante_tool has now been added to the tools section of the prompt.", result)
      assert.equals(1, #LazyLoading._tools_to_collect)
      assert.equals("test_avante_tool", LazyLoading._tools_to_collect[1].name)
    end)

    it("should return an error for non-existent avante tool", function()
      local result, err = LoadMcpTool.func({
        server_name = "avante",
        tool_name = "non_existent_tool",
      }, {})

      assert.is_nil(result)
      assert.equals("Tool 'non_existent_tool' on server 'avante' does not exist.", err)
    end)
  end)

  describe("non-avante server tools", function()
    it("should return tool details for existing tool", function()
      -- Register the tool as available first
      LazyLoading.register_available_tool("test_server", "test_tool")

      local result, err = LoadMcpTool.func({
        server_name = "test_server",
        tool_name = "test_tool"
      }, {})

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_true(result:find("test_tool") ~= nil)
      assert.is_true(result:find("A test tool description") ~= nil)
    end)

    it("should return error for non-existent server", function()
      -- Replace get_hub_instance to return nil
      mcphub.get_hub_instance = function() return nil end

      local result, err = LoadMcpTool.func({
        server_name = "non_existent_server",
        tool_name = "test_tool"
      }, {})

      assert.is_nil(result)
      assert.equals("Tool 'test_tool' on server 'non_existent_server' does not exist.", err)
    end)

    it("should return error for non-existent tool", function()
      local result, err = LoadMcpTool.func({
        server_name = "test_server",
        tool_name = "non_existent_tool",
      }, {})

      assert.is_nil(result)
      assert.equals("Tool 'non_existent_tool' on server 'test_server' does not exist.", err)
    end)

    it("should call on_log when provided with tool_use_id", function()
      local log_called = false
      local log_tool_use_id = nil
      local log_tool_name = nil
      local log_message = nil
      local log_status = nil

      -- Register the tool as available first
      LazyLoading.register_available_tool("test_server", "test_tool")

      local result, err = LoadMcpTool.func({
        server_name = "test_server",
        tool_name = "test_tool"
      }, {
        tool_use_id = "test_id_123",
        on_log = function(tool_use_id, tool_name, message, status)
          log_called = true
          log_tool_use_id = tool_use_id
          log_tool_name = tool_name
          log_message = message
          log_status = status
        end
      })

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_true(log_called)
      assert.equals("test_id_123", log_tool_use_id)
      assert.equals("load_mcp_tool", log_tool_name)
      assert.is_not_nil(log_message)
      assert.equals("completed", log_status)
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
        tool_name = "test_tool",
      }, {})

      assert.is_nil(err)
      assert.is_true(LazyLoading.is_tool_requested("test_server", "test_tool"))
    end)
  end)
end)
