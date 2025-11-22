local LazyLoading = require("avante.llm_tools.lazy_loading")
local Config = require("avante.config")

describe("lazy_loading", function()
  before_each(function()
    -- Reset state before each test
    LazyLoading.reset_requested_tools()
    LazyLoading._requested_tools = {}
    LazyLoading._available_to_request = {}
    LazyLoading._tools_to_collect = {}
  end)

  describe("register_requested_tool", function()
    it("should register a tool that is available", function()
      LazyLoading.register_available_tool("test_server", "test_tool")
      local result = LazyLoading.register_requested_tool("test_server", "test_tool")
      assert.is_true(result)
      assert.is_true(LazyLoading.is_tool_requested("test_server", "test_tool"))
    end)

    it("should not register a tool that is not available", function()
      local result = LazyLoading.register_requested_tool("test_server", "test_tool")
      assert.is_false(result)
      assert.is_false(LazyLoading.is_tool_requested("test_server", "test_tool"))
    end)
  end)

  describe("extract_first_sentence", function()
    it("should extract first sentence correctly", function()
      local test_cases = {
        {
          input = "This is a test sentence. Another sentence follows.",
          expected = "This is a test sentence."
        },
        {
          input = "Short sentence.",
          expected = "Short sentence."
        },
        {
          input = "A sentence with a `code block`. More text.",
          expected = "A sentence with a `code block`."
        },
        {
          input = "A sentence with an abbreviation like e.g. something else.",
          expected = "A sentence with an abbreviation like e.g. something else."
        },
        {
          input = "A very long sentence that goes on and on and is more than one hundred characters long and should be truncated...",
          expected = "A very long sentence that goes on and on and is more than one hundred characters long..."
        }
      }

      for _, case in ipairs(test_cases) do
        local result = LazyLoading.extract_first_sentence(case.input)
        assert.equals(case.expected, result)
      end
    end)

    it("should handle empty or nil input", function()
      assert.equals("", LazyLoading.extract_first_sentence(nil))
      assert.equals("", LazyLoading.extract_first_sentence(""))
    end)
  end)

  describe("add_loaded_tools", function()
    it("should add tools to collect that are not already in the list", function()
      local existing_tools = {
        {name = "tool1"},
        {name = "tool2"}
      }
      local tools_to_collect = {
        {name = "tool3"},
        {name = "tool4"}
      }

      LazyLoading._tools_to_collect = tools_to_collect
      local updated_tools = LazyLoading.add_loaded_tools(existing_tools)

      assert.equals(4, #updated_tools)
      assert.equals("tool1", updated_tools[1].name)
      assert.equals("tool2", updated_tools[2].name)
      assert.equals("tool3", updated_tools[3].name)
      assert.equals("tool4", updated_tools[4].name)
      assert.equals(1, #LazyLoading._tools_to_collect)
    end)

    it("should not add tools already in the list", function()
      local existing_tools = {
        {name = "tool1"},
        {name = "tool2"}
      }
      local tools_to_collect = {
        {name = "tool1"},
        {name = "tool4"}
      }

      LazyLoading._tools_to_collect = tools_to_collect
      local updated_tools = LazyLoading.add_loaded_tools(existing_tools)

      assert.equals(3, #updated_tools)
      assert.equals("tool1", updated_tools[1].name)
      assert.equals("tool2", updated_tools[2].name)
      assert.equals("tool4", updated_tools[3].name)
      assert.equals(1, #LazyLoading._tools_to_collect)
      assert.equals("tool1", LazyLoading._tools_to_collect[1].name)
    end)
  end)

  describe("summarize_tool", function()
    it("should return nil for nil input", function()
      assert.is_nil(LazyLoading.summarize_tool(nil))
    end)

    it("should create a minimal tool version with extra concise mode", function()
      -- Temporarily modify config
      Config.lazy_loading = {
        enabled = true,
        mcp_extra_concise = true
      }

      local tool = {
        name = "test_tool",
        description = "This is a long description with multiple sentences. Only the first should be returned.",
        param = {
          fields = {
            {
              name = "test_param",
              description = "A parameter description that will be truncated."
            }
          }
        }
      }

      local summarized = LazyLoading.summarize_tool(tool)
      assert.equals("test_tool", summarized.name)
      assert.equals("This is a long description with multiple sentences.", summarized.description)
      assert.is_nil(summarized.param)
    end)

    it("should summarize tool with standard mode", function()
      -- Temporarily modify config
      Config.lazy_loading = {
        enabled = true,
        mcp_extra_concise = false
      }

      local tool = {
        name = "test_tool",
        description = "This is a long description with multiple sentences. Only the first should be returned.",
        param = {
          fields = {
            {
              name = "test_param",
              description = "A parameter description that will be truncated. This is the full description."
            }
          }
        }
      }

      local summarized = LazyLoading.summarize_tool(tool)
      assert.equals("test_tool", summarized.name)
      assert.equals("This is a long description with multiple sentences.", summarized.description)
      assert.equals(1, #summarized.param.fields)
      assert.equals("test_param", summarized.param.fields[1].name)
      assert.equals("A parameter description that will be truncated.", summarized.param.fields[1].description)
    end)
  end)

  describe("should_include_tool", function()
    it("should include tool for always eager tools", function()
      Config.lazy_loading = {
        enabled = true
      }

      -- Test always eager tools
      local always_eager_tools = LazyLoading.always_eager()
      for tool_name, _ in pairs(always_eager_tools) do
        assert.is_true(LazyLoading.should_include_tool("avante", tool_name))
      end
    end)

    it("should include tool when lazy loading is disabled", function()
      Config.lazy_loading = {
        enabled = false
      }

      assert.is_true(LazyLoading.should_include_tool("test_server", "test_tool"))
    end)

    it("should include requested tool when lazy loading is enabled", function()
      Config.lazy_loading = {
        enabled = true
      }

      LazyLoading.register_available_tool("test_server", "test_tool")
      LazyLoading.register_requested_tool("test_server", "test_tool")

      assert.is_true(LazyLoading.should_include_tool("test_server", "test_tool"))
    end)

    it("should not include unrequested tool when lazy loading is enabled", function()
      Config.lazy_loading = {
        enabled = true
      }

      LazyLoading.register_available_tool("test_server", "test_tool")

      assert.is_false(LazyLoading.should_include_tool("test_server", "test_tool"))
    end)
  end)
end)
