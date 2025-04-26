local stub = require("luassert.stub")
local GeminiProvider = require("avante.providers.gemini")
local Utils = require("avante.utils")

describe("GeminiProvider", function()
  describe("transform_tool", function()
    ---@type AvanteLLMTool
    local tool

    before_each(function()
      -- Mock the Utils functions if needed
      -- stub(Utils, "llm_tool_param_fields_to_json_schema")
      -- stub(Utils, "debug")
      -- stub(Utils, "warn")
      -- stub(Utils, "error")

      -- Define a sample tool object
      tool = {
        name = "sample_tool",
        description = "This is a sample tool",
        param = {
          type = "table",
          fields = {
            { name = "query", type = "string", description = "A search query" },
            { name = "path",  type = "string", description = "A file path" },
          },
        },
        returns = {
          {
            name = "stdout",
            description = "List of senteces where the query was found",
            type = "string[]",
          },
        },
      }
    end)

    after_each(function()
      -- Revert the stubs after each test
      -- Utils.llm_tool_param_fields_to_json_schema:revert()
      -- Utils.debug:revert()
      -- Utils.warn:revert()
      -- Utils.error:revert()
    end)

    it("should transform tool with parameters", function()
      -- Mock the return value of llm_tool_param_fields_to_json_schema
      -- Utils.llm_tool_param_fields_to_json_schema.returns({
      --   query = { type = "string", description = "A search query" },
      --   path = { type = "string", description = "A file path" },
      -- }, { "query" })

      ---@type AvanteOpenAITool | AvanteClaudeTool | AvanteGeminiTool
      local raw_tool = GeminiProvider:transform_tool(tool)
      ---@cast raw_tool AvanteGeminiTool
      local transformed_tool = raw_tool

      assert.is_table(transformed_tool)
      assert.equals("sample_tool", transformed_tool.name)
      assert.equals("This is a sample tool", transformed_tool.description)
      assert.is_table(transformed_tool.parameters)
      assert.equals("object", transformed_tool.parameters.type)
      assert.is_table(transformed_tool.parameters.properties)
      -- check properties
      assert.is_table(transformed_tool.parameters.properties.query)
      assert.equals("string", transformed_tool.parameters.properties.query.type)
      assert.equals("(Type: string) A search query (Provide a concise search query based on the user's request.)", transformed_tool.parameters.properties.query.description)
      assert.is_table(transformed_tool.parameters.properties.path)
      assert.equals("string", transformed_tool.parameters.properties.path.type)
      assert.equals("(Type: string) A file path (Provide the relative file path within the project.)", transformed_tool.parameters.properties.path.description)
      -- check required
      assert.is_table(transformed_tool.parameters.required)
      assert.equals("query", transformed_tool.parameters.required[1])
      assert.equals("path", transformed_tool.parameters.required[2])
    end)

    -- it("should transform tool without parameters", function()
    --   -- Modify the tool to have no parameters
    --   tool.param.fields = {}

    --   local transformed_tool = GeminiProvider:transform_tool(tool)

    --   assert.is_table(transformed_tool)
    --   assert.equals("sample_tool", transformed_tool.name)
    --   assert.equals("This is a sample tool", transformed_tool.description)
    --   assert.is_nil(transformed_tool.parameters)
    -- end)

    -- it("should handle empty properties gracefully", function()
    --   -- Mock the return value to simulate empty properties
    --   Utils.llm_tool_param_fields_to_json_schema.returns({}, {})

    --   local transformed_tool = GeminiProvider:transform_tool(tool)

    --   assert.is_table(transformed_tool)
    --   assert.equals("sample_tool", transformed_tool.name)
    --   assert.equals("This is a sample tool", transformed_tool.description)
    --   assert.is_nil(transformed_tool.parameters)
    --   assert.stub(Utils.warn).was_called_with(
    --     "Gemini Provider: Tool 'sample_tool' has parameters defined, but generated schema properties are empty. Omitting parameters field.",
    --     { title = "Avante" }
    --   )
    -- end)
  end)
  describe("parse_messages", function()
    local gemini_provider

    before_each(function()
      gemini_provider = GeminiProvider
    end)

    it("should parse messages correctly", function()
      ---@type AvantePromptOptions
      local opts = {
        system_prompt = "This is a system prompt.",
        messages = {
          { role = "user", content = "Hello, how are you?" },
          { role = "assistant", content = "I'm fine, thank you!" },
        },
      }

      ---@type AvanteGeminiMessage
      local result = gemini_provider:parse_messages(opts)

      assert.is_table(result)
      assert.is_table(result.contents)
      assert.equals("This is a system prompt.", result.system_instruction.parts[1].text)

      assert.equals("user", result.contents[1].role)
      assert.equals("Hello, how are you?", result.contents[1].parts[1].text)

      assert.equals("model", result.contents[2].role)
      assert.equals("I'm fine, thank you!", result.contents[2].parts[1].text)
    end)
  end)
end)
