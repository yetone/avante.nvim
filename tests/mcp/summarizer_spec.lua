local summarizer = require("avante.mcp.summarizer")

describe("summarizer", function()
  describe("extract_first_sentence", function()
    it("extracts the first sentence", function()
      local desc = "This is a sentence. This is another sentence."
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("This is a sentence.", result)
    end)

    it("handles question marks", function()
      local desc = "Is this a question? This is another sentence."
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("Is this a question?", result)
    end)

    it("handles exclamation marks", function()
      local desc = "This is an exclamation! This is another sentence."
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("This is an exclamation!", result)
    end)

    it("handles abbreviations", function()
      local desc = "This is e.g. an example. This is another sentence."
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("This is e.g. an example.", result)
    end)

    it("handles missing sentence end", function()
      local desc = "This is a sentence without end"
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("This is a sentence without end", result)
    end)

    it("truncates long descriptions without sentence end", function()
      local desc = string.rep("a", 150)
      local result = summarizer.extract_first_sentence(desc)
      assert.equals(string.rep("a", 100) .. "...", result)
    end)

    it("handles empty input", function()
      local result = summarizer.extract_first_sentence("")
      assert.equals("", result)
    end)

    it("handles nil input", function()
      local result = summarizer.extract_first_sentence(nil)
      assert.equals("", result)
    end)
  end)

  describe("summarize_tool", function()
    it("summarizes a tool", function()
      local tool = {
        name = "test_tool",
        description = "This is a test tool. It has a long description.",
        param = {
          fields = {
            {
              name = "param1",
              description = "This is parameter 1. It has a long description.",
            },
            {
              name = "param2",
              description = "This is parameter 2. It has a long description.",
            },
          },
        },
        returns = {
          {
            name = "return1",
            description = "This is return value 1. It has a long description.",
          },
        },
      }

      local result = summarizer.summarize_tool(tool)
      assert.equals("This is a test tool.", result.description)
      assert.equals("This is parameter 1.", result.param.fields[1].description)
      assert.equals("This is parameter 2.", result.param.fields[2].description)
      assert.equals("This is return value 1.", result.returns[1].description)
    end)

    it("handles nil input", function()
      local result = summarizer.summarize_tool(nil)
      assert.is_nil(result)
    end)

    it("handles missing descriptions", function()
      local tool = {
        name = "test_tool",
        param = {
          fields = {
            {
              name = "param1",
            },
          },
        },
        returns = {
          {
            name = "return1",
          },
        },
      }

      local result = summarizer.summarize_tool(tool)
      assert.is_nil(result.description)
      assert.is_nil(result.param.fields[1].description)
      assert.is_nil(result.returns[1].description)
    end)
  end)

  describe("summarize_tools", function()
    it("summarizes multiple tools", function()
      local tools = {
        {
          name = "tool1",
          description = "Tool 1 description. More details.",
        },
        {
          name = "tool2",
          description = "Tool 2 description. More details.",
        },
      }

      local result = summarizer.summarize_tools(tools)
      assert.equals(2, #result)
      assert.equals("Tool 1 description.", result[1].description)
      assert.equals("Tool 2 description.", result[2].description)
    end)

    it("handles empty array", function()
      local result = summarizer.summarize_tools({})
      assert.same({}, result)
    end)

    it("handles nil input", function()
      local result = summarizer.summarize_tools(nil)
      assert.same({}, result)
    end)
  end)
end)
