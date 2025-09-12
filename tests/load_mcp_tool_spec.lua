local stub = require("luassert.stub")
local Config = require("avante.config")
local Utils = require("avante.utils")
local load_mcp_tool = require("avante.llm_tools.load_mcp_tool")

describe("load_mcp_tool", function()
  before_each(function()
    Config.setup()
    -- Mock get_project_root
    stub(Utils, "get_project_root", function() return "/tmp/test_load_mcp_tool" end)
  end)

  after_each(function()
    -- Restore mocks
    Utils.get_project_root:revert()
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

    -- Result should be a JSON string
    local decoded = vim.json.decode(result)
    assert.equals("view", decoded.name)
  end)

  it("should successfully load the list_tools special tool", function()
    -- Try to load the list_tools special tool
    local result, err = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "list_tools"
    }, {})

    assert.is_nil(err)
    assert.is_not_nil(result)

    -- Result should be a JSON string
    local decoded = vim.json.decode(result)
    assert.equals("list_tools", decoded.name)
    assert.is_not_nil(decoded.description)
    assert.is_not_nil(decoded.returns)
  end)

  it("should return error when loading non-existent built-in tool", function()
    -- Try to load a tool that doesn't exist
    local result, err = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "non_existent_tool"
    }, {})

    assert.is_nil(result)
    assert.equals("Built-in tool 'non_existent_tool' not found", err)
  end)

  it("should cache tool information", function()
    -- Load a tool first time
    local result1, err1 = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "view"
    }, {})

    assert.is_nil(err1)
    assert.is_not_nil(result1)

    -- Check that it's in the cache
    local cache_key = "avante:view"
    assert.is_not_nil(load_mcp_tool._tool_cache[cache_key])

    -- Mock the require function to verify it uses the cache
    local original_require = _G.require
    local require_called = false
    _G.require = function(module)
      if module == "avante.llm_tools.view" then
        require_called = true
      end
      return original_require(module)
    end

    -- Load same tool again
    local result2, err2 = load_mcp_tool.func({
      server_name = "avante",
      tool_name = "view"
    }, {})

    -- Restore require
    _G.require = original_require

    -- Should get same result but require shouldn't be called
    assert.is_nil(err2)
    assert.equals(result1, result2)
    assert.is_false(require_called)
  end)
end)

