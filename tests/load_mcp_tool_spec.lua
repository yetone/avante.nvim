local stub = require("luassert.stub")
local Config = require("avante.config")
local Utils = require("avante.utils")
local load_mcp_tool = require("avante.llm_tools.load_mcp_tool")
local llm_tools = require("avante.llm_tools")
local LazyLoading = require("avante.llm_tools.lazy_loading")

describe("load_mcp_tool", function()
  before_each(function()
    Config.setup()
    -- Enable lazy loading for tests
    Config.lazy_loading = { enabled = true }
    -- Mock get_project_root
    stub(Utils, "get_project_root", function() return "/tmp/test_load_mcp_tool" end)
    -- Mock llm_tools.get_tools to return test tools
    stub(llm_tools, "get_tools", function()
      return {
        { name = "view", description = "View file content" },
        { name = "list_tools", description = "List available tools" },
      }
    end)
    -- Mock LazyLoading functions
    stub(LazyLoading, "register_requested_tool", function() end)
    stub(LazyLoading, "register_tool_to_collect", function() end)
  end)

  after_each(function()
    -- Restore mocks
    Utils.get_project_root:revert()
    llm_tools.get_tools:revert()
    LazyLoading.register_requested_tool:revert()
    LazyLoading.register_tool_to_collect:revert()
    -- Clear the tool cache to ensure tests are isolated
    load_mcp_tool._tool_cache = {}
  end)

  it("should load built-in avante tools that exist", function()
    -- Try to load a tool that definitely exists (view)
    local result, err = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "view"
    }, {})

    assert.is_nil(err)
    assert.is_not_nil(result)
    assert.equals("The tool view has now been added to the tools section of the prompt.", result)

    -- Verify LazyLoading functions were called
    assert.stub(LazyLoading.register_requested_tool).was_called_with("avante", "view")
    assert.stub(LazyLoading.register_tool_to_collect).was_called(1)
  end)

  it("should successfully load the list_tools special tool", function()
    -- Try to load the list_tools special tool
    local result, err = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "list_tools"
    }, {})

    assert.is_nil(err)
    assert.is_not_nil(result)
    assert.equals("The tool list_tools has now been added to the tools section of the prompt.", result)

    -- Verify LazyLoading functions were called
    assert.stub(LazyLoading.register_requested_tool).was_called_with("avante", "list_tools")
    assert.stub(LazyLoading.register_tool_to_collect).was_called(1)
  end)

  it("should return error when loading non-existent built-in tool", function()
    -- Try to load a tool that doesn't exist
    local result, err = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "non_existent_tool"
    }, {})

    assert.is_nil(result)
    assert.equals("Internal error: could not load tool non_existent_tool", err)

    -- Verify LazyLoading function was called
    assert.stub(LazyLoading.register_requested_tool).was_called_with("avante", "non_existent_tool")
  end)

  it("should cache tool information", function()
    -- Load a tool first time (using avante since it's easier to mock)
    local result1, err1 = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "view"
    }, {})

    assert.is_nil(err1)
    assert.is_not_nil(result1)

    -- Check that LazyLoading functions were called
    assert.stub(LazyLoading.register_requested_tool).was_called_with("avante", "view")
    assert.stub(LazyLoading.register_tool_to_collect).was_called(1)

    -- Reset stubs for second call
    LazyLoading.register_requested_tool:clear()
    LazyLoading.register_tool_to_collect:clear()
    llm_tools.get_tools:clear()

    -- Load same tool again
    local result2, err2 = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "view"
    }, {})

    -- Should get same result but require shouldn't be called
    assert.is_nil(err2)
    assert.equals(result1, result2)
    assert.stub(LazyLoading.register_requested_tool).was_called_with("avante", "view")
    assert.stub(LazyLoading.register_tool_to_collect).was_called(1)
  end)
end)
