local ModelMessage = require("avante.model_message")

describe("ModelMessage", function()
  describe("constructor", function()
    it("should create a new ModelMessage with defaults", function()
      local msg = ModelMessage:new("user", "Hello world")

      assert.equals("user", msg.message.role)
      assert.equals("Hello world", msg.message.content)
      assert.is_not_nil(msg.uuid)
      assert.is_not_nil(msg.timestamp)
      assert.equals("generated", msg.state)
      assert.equals(false, msg.is_user_submission)
      assert.equals(false, msg.is_context)
      assert.equals(false, msg.is_compacted)
      assert.equals(false, msg.is_deleted)
    end)

    it("should create ModelMessage with options", function()
      local opts = {
        uuid = "test-uuid",
        state = "generating",
        is_user_submission = true,
        provider = "claude",
        model = "claude-3-sonnet",
      }
      
      local msg = ModelMessage:new("assistant", "Response", opts)

      assert.equals("assistant", msg.message.role)
      assert.equals("Response", msg.message.content)
      assert.equals("test-uuid", msg.uuid)
      assert.equals("generating", msg.state)
      assert.equals(true, msg.is_user_submission)
      assert.equals("claude", msg.provider)
      assert.equals("claude-3-sonnet", msg.model)
    end)

    it("should handle complex content", function()
      local complex_content = {
        { type = "text", text = "Hello" },
        { type = "tool_use", name = "view", id = "tool-123", input = { path = "/test.lua" } }
      }
      
      local msg = ModelMessage:new("assistant", complex_content)

      assert.equals("assistant", msg.message.role)
      assert.same({ complex_content }, msg.message.content)
    end)
  end)

  describe("synthetic messages", function()
    it("should create synthetic ModelMessage", function()
      local msg = ModelMessage:new_synthetic("assistant", "Tool result")

      assert.equals("assistant", msg.message.role)
      assert.equals("Tool result", msg.message.content)
      assert.equals(true, msg.is_dummy)
    end)

    it("should create assistant synthetic", function()
      local msg = ModelMessage:new_assistant_synthetic("Assistant synthetic")

      assert.equals("assistant", msg.message.role)
      assert.equals("Assistant synthetic", msg.message.content)
      assert.equals(true, msg.is_dummy)
    end)

    it("should create user synthetic", function()
      local msg = ModelMessage:new_user_synthetic("User synthetic")

      assert.equals("user", msg.message.role)
      assert.equals("User synthetic", msg.message.content)
      assert.equals(true, msg.is_dummy)
    end)
  end)

  describe("content updates", function()
    it("should update simple text content", function()
      local msg = ModelMessage:new("user", "Original content")
      
      msg:update_content("Updated content")

      assert.equals("Updated content", msg.message.content)
    end)

    it("should fail to update complex content", function()
      local msg = ModelMessage:new("assistant", { { type = "text", text = "Complex" } })
      
      assert.has_error(function()
        msg:update_content("New content")
      end, "can only update content of simple string messages")
    end)
  end)

  describe("tool detection", function()
    it("should detect tool use messages", function()
      local tool_content = {
        {
          type = "tool_use",
          name = "view",
          id = "tool-123",
          input = { path = "/test.lua" }
        }
      }
      
      local msg = ModelMessage:new("assistant", tool_content)

      assert.equals(true, msg:is_tool_use())
      assert.equals(false, msg:is_tool_result())
    end)

    it("should detect tool result messages", function()
      local result_content = {
        {
          type = "tool_result",
          tool_use_id = "tool-123",
          content = "File contents here",
          is_error = false
        }
      }
      
      local msg = ModelMessage:new("user", result_content)

      assert.equals(false, msg:is_tool_use())
      assert.equals(true, msg:is_tool_result())
    end)

    it("should not detect tools in simple text", function()
      local msg = ModelMessage:new("user", "Simple text message")

      assert.equals(false, msg:is_tool_use())
      assert.equals(false, msg:is_tool_result())
    end)
  end)

  describe("tool data extraction", function()
    it("should extract tool use data", function()
      local tool_content = {
        {
          type = "tool_use",
          name = "edit_file",
          id = "tool-456",
          input = { 
            path = "/src/main.lua",
            content = "new content"
          }
        }
      }
      
      local msg = ModelMessage:new("assistant", tool_content)
      local tool_use = msg:get_tool_use()

      assert.is_not_nil(tool_use)
      assert.equals("edit_file", tool_use.name)
      assert.equals("tool-456", tool_use.id)
      assert.same({ path = "/src/main.lua", content = "new content" }, tool_use.input)
    end)

    it("should extract tool result data", function()
      local result_content = {
        {
          type = "tool_result",
          tool_use_id = "tool-789",
          content = "Operation successful",
          is_error = false,
          is_user_declined = false
        }
      }
      
      local msg = ModelMessage:new("user", result_content)
      local tool_result = msg:get_tool_result()

      assert.is_not_nil(tool_result)
      assert.equals("tool-789", tool_result.tool_use_id)
      assert.equals("Operation successful", tool_result.content)
      assert.equals(false, tool_result.is_error)
      assert.equals(false, tool_result.is_user_declined)
      assert.equals("", tool_result.tool_name) -- Tool name not stored in result
    end)

    it("should return nil for missing tool data", function()
      local msg = ModelMessage:new("user", "No tools here")

      assert.is_nil(msg:get_tool_use())
      assert.is_nil(msg:get_tool_result())
    end)

    it("should handle mixed content and find tools", function()
      local mixed_content = {
        { type = "text", text = "Some text" },
        {
          type = "tool_use",
          name = "view",
          id = "tool-mixed",
          input = { path = "/mixed.lua" }
        },
        { type = "text", text = "More text" }
      }
      
      local msg = ModelMessage:new("assistant", mixed_content)
      local tool_use = msg:get_tool_use()

      assert.equals(true, msg:is_tool_use())
      assert.is_not_nil(tool_use)
      assert.equals("view", tool_use.name)
      assert.equals("tool-mixed", tool_use.id)
    end)
  end)
end)