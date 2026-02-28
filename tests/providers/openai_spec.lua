local openai_bedrock = require("avante.providers.bedrock.openai")

local Config = require("avante.config")
Config.setup({})

describe("openai_bedrock", function()
  describe("is_disable_stream", function()
    it("should return false", function()
      assert.is_false(openai_bedrock:is_disable_stream())
    end)
  end)

  describe("transform_tool", function()
    it("should transform tool correctly", function()
      local tool = {
        name = "test",
        param = { fields = { { name = "x", type = "string" } } },
        description = "desc",
        get_description = function() return "desc" end,
      }
      local result = openai_bedrock:transform_tool(tool)
      assert.equals("function", result.type)
      assert.equals("test", result["function"].name)
      assert.equals("desc", result["function"].description)
      assert.is_table(result["function"].parameters)
    end)
  end)
end)
