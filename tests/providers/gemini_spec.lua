local stub = require("luassert.stub")
local GeminiProvider = require("avante.providers.gemini")
local Utils = require("avante.utils")

describe("GeminiProvider", function()
  describe("transform_tool", function()
    ---@type AvanteLLMTool
    local tool
    package.loaded["mcphub"] = {
      get_hub_instance = function()
        return {
          is_ready = function() return true end,
          get_resources = function()
            return {
              {
                server_name = "server1",
                uri = "/resource1",
                description = "This is a sample tool",
                mimeType = "application/json",
                name = "access_mcp_resource",
              },
            }
          end,
          get_tools = function()
            return {
              {
                description = "Start or stop an MCP server. You can only start a server from one of the disabled servers.",
                inputSchema = {
                  properties = {
                    action = {
                      description = "Action to perform. One of 'start' or 'stop'",
                      enum = { "start", "stop" },
                      type = "string",
                    },
                    server_name = {
                      description = "Name of the MCP server to toggle",
                      type = "string",
                    },
                  },
                  required = { "server_name", "action" },
                  type = "object",
                },
                name = "toggle_mcp_server",
                server_name = "mcphub",
              },
            }
          end,
        }
      end,
    }

    before_each(function()
      -- Define a sample tool object
      tool = {
        name = "sample_tool",
        description = "This is a sample tool",
        param = {
          type = "table",
          fields = {
            { name = "query", type = "string", description = "A search query" },
            { name = "path", type = "string", description = "A file path" },
          },
          required = { "query", "path" },
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

    it("should transform tool with parameters", function()
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
      assert.equals(
        "(Type: string) A search query (Provide a concise search query based on the user's request.)",
        transformed_tool.parameters.properties.query.description
      )
      assert.is_table(transformed_tool.parameters.properties.path)
      assert.equals("string", transformed_tool.parameters.properties.path.type)
      assert.equals(
        "(Type: string) A file path (Provide the relative file path within the project.)",
        transformed_tool.parameters.properties.path.description
      )
      -- check required
      assert.is_table(transformed_tool.parameters.required)
      assert.equals("query", transformed_tool.parameters.required[1])
      assert.equals("path", transformed_tool.parameters.required[2])
    end)
  end)

  describe("parse_messages", function()
    local gemini_provider

    before_each(function() gemini_provider = GeminiProvider end)

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

  describe("parse_curl_args", function()
    local parse_api_key_stub
    before_each(function()
      GeminiProvider["model"] = "gemini"
      parse_api_key_stub = stub(GeminiProvider, "parse_api_key")
      parse_api_key_stub.returns("mocked_api_key")
    end)
    it("should parse curl arguments correctly", function()
      ---@type AvantePromptOptions
      local prompt_opts = {
        system_prompt = "This is a system prompt.",
        messages = {
          { role = "user", content = "Hello, how are you?" },
          { role = "assistant", content = "I'm fine, thank you!" },
        },
        tools = {
          {
            name = "access_mcp_resource",
            description = "This is a sample tool",
            param = {
              type = "table",
              fields = {
                {
                  name = "server_name",
                  type = "string",
                  description = "(Type: string) Name of the server to call the resource on. Must be from one of the available servers.",
                },
                {
                  name = "uri",
                  type = "string",
                  description = "(Type: string) URI of the resource to access.",
                },
              },
              required = { "server_name", "uri" },
            },
            returns = {
              {
                name = "stdout",
                description = "List of sentences where the query was found",
                type = "string[]",
              },
            },
          },
          {
            name = "sample_tool",
            description = "This is a sample tool",
            param = {
              type = "table",
              fields = {
                { name = "query", type = "string", description = "A search query" },
                { name = "path", type = "string", description = "A file path" },
              },
              required = { "query", "path" },
            },
            returns = {
              {
                name = "stdout",
                description = "List of sentences where the query was found",
                type = "string[]",
              },
            },
          },
        },
      }

      ---@type AvanteCurlOutput
      local result = GeminiProvider:parse_curl_args(prompt_opts)

      assert.is_table(result)
      assert.is_string(result.url)
      assert.is_table(result.headers)
      assert.equals("application/json", result.headers["Content-Type"])
      assert.is_table(result.body)
      assert.is_table(result.body.contents)
      assert.equals("This is a system prompt.", result.body.system_instruction.parts[1].text)

      -- Check if the tools are correctly added
      assert.is_table(result.body.tools)
      assert.equals(2, #result.body.tools[1].functionDeclarations)
      assert.equals("sample_tool", result.body.tools[1].functionDeclarations[2].name)
      assert.equals("This is a sample tool", result.body.tools[1].functionDeclarations[2].description)
      assert.equals("access_mcp_resource", result.body.tools[1].functionDeclarations[1].name)
    end)
  end)
end)
