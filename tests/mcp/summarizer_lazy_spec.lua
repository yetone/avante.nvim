local summarizer = require("avante.mcp.summarizer")

describe("summarizer for lazy loading", function()
  describe("summarize_tools for MCP servers", function()
    it("summarizes a collection of tools with server information", function()
      local tools = {
        {
          name = "tool1",
          description = "This is tool 1 with a detailed description. It has multiple sentences.",
          server_name = "test_server",
          param = {
            fields = {
              {
                name = "param1",
                description = "Parameter 1 with a detailed description. More details here.",
              },
            },
          },
        },
        {
          name = "tool2",
          description = "This is tool 2 with a detailed description. It has multiple sentences.",
          server_name = "another_server",
          param = {
            fields = {
              {
                name = "param1",
                description = "Parameter 1 with a detailed description. More details here.",
              },
            },
          },
        },
      }

      local summarized = summarizer.summarize_tools(tools)

      -- Check that the tools were summarized
      assert.equals(2, #summarized)
      assert.equals("This is tool 1 with a detailed description.", summarized[1].description)
      assert.equals("This is tool 2 with a detailed description.", summarized[2].description)

      -- Check that parameter descriptions were summarized
      assert.equals("Parameter 1 with a detailed description.", summarized[1].param.fields[1].description)
      assert.equals("Parameter 1 with a detailed description.", summarized[2].param.fields[1].description)

      -- Check that server information was preserved
      assert.equals("test_server", summarized[1].server_name)
      assert.equals("another_server", summarized[2].server_name)
    end)

    it("handles tools with complex parameter structures", function()
      local tool = {
        name = "complex_tool",
        description = "A tool with complex parameters. It has nested structures.",
        param = {
          fields = {
            {
              name = "simple_param",
              description = "A simple parameter. With details.",
              type = "string",
            },
            {
              name = "complex_param",
              description = "A complex parameter with nested fields. More details.",
              type = "object",
              fields = {
                {
                  name = "nested_param",
                  description = "A nested parameter. With details.",
                  type = "string",
                },
              },
            },
          },
        },
        returns = {
          {
            name = "result",
            description = "The result of the tool execution. With details.",
            type = "object",
            fields = {
              {
                name = "nested_result",
                description = "A nested result field. With details.",
                type = "string",
              },
            },
          },
        },
      }

      local summarized = summarizer.summarize_tool(tool)

      -- Check that the tool description was summarized
      assert.equals("A tool with complex parameters.", summarized.description)

      -- Check that parameter descriptions were summarized
      assert.equals("A simple parameter.", summarized.param.fields[1].description)
      assert.equals("A complex parameter with nested fields.", summarized.param.fields[2].description)

      -- Check that nested fields were preserved but not summarized
      -- The summarizer doesn't recursively process nested fields
      assert.equals("A nested parameter. With details.", summarized.param.fields[2].fields[1].description)

      -- Check that return descriptions were summarized
      assert.equals("The result of the tool execution.", summarized.returns[1].description)

      -- Check that nested return fields were preserved but not summarized
      assert.equals("A nested result field. With details.", summarized.returns[1].fields[1].description)
    end)

    it("handles tools with special characters in descriptions", function()
      local tool = {
        name = "special_tool",
        description = "A tool with e.g. abbreviations. It uses i.e. special formatting.",
        param = {
          fields = {
            {
              name = "param1",
              description = "A parameter with e.g. abbreviations. More details.",
            },
          },
        },
      }

      local summarized = summarizer.summarize_tool(tool)

      -- Check that the tool description was summarized correctly
      assert.equals("A tool with e.g. abbreviations.", summarized.description)

      -- Check that parameter descriptions were summarized correctly
      assert.equals("A parameter with e.g. abbreviations.", summarized.param.fields[1].description)
    end)

    it("preserves tool structure while summarizing descriptions", function()
      local tool = {
        name = "structured_tool",
        description = "A tool with a structured description. Multiple sentences here.",
        param = {
          fields = {
            {
              name = "required_param",
              description = "A required parameter. More details.",
              required = true,
            },
            {
              name = "optional_param",
              description = "An optional parameter. More details.",
              required = false,
            },
          },
        },
        returns = {
          {
            name = "success",
            description = "Whether the operation succeeded. Details here.",
            type = "boolean",
          },
        },
      }

      local summarized = summarizer.summarize_tool(tool)

      -- Check that the tool structure was preserved
      assert.equals("structured_tool", summarized.name)
      assert.equals("A tool with a structured description.", summarized.description)

      -- Check that parameter structure was preserved
      assert.equals(2, #summarized.param.fields)
      assert.equals("required_param", summarized.param.fields[1].name)
      assert.equals(true, summarized.param.fields[1].required)
      assert.equals("optional_param", summarized.param.fields[2].name)
      assert.equals(false, summarized.param.fields[2].required)

      -- Check that return structure was preserved
      assert.equals(1, #summarized.returns)
      assert.equals("success", summarized.returns[1].name)
      assert.equals("boolean", summarized.returns[1].type)
      assert.equals("Whether the operation succeeded.", summarized.returns[1].description)
    end)
  end)

  describe("extract_first_sentence edge cases", function()
    it("handles multi-line descriptions", function()
      local desc = "This is a multi-line\ndescription. Second sentence."
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("This is a multi-line\ndescription.", result)
    end)

    it("handles descriptions with code blocks", function()
      -- Create a description with code block
      local desc = "A description with code. `code block here`. Second sentence."

      -- This test checks that the code block is kept intact even though it contains a period
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("A description with code. `code block here`.", result)
    end)

    it("handles descriptions with URLs", function()
      local desc = "A description with a URL https://example.com. Second sentence."
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("A description with a URL https://example.com.", result)
    end)

    it("handles descriptions with multiple consecutive sentence endings", function()
      local desc = "A description with multiple endings... Second sentence."
      local result = summarizer.extract_first_sentence(desc)
      assert.equals("A description with multiple endings...", result)
    end)
  end)
end)
