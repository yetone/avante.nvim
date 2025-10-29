local llm = require("avante.llm")
local History = require("avante.history")

describe("ACP history message tracking", function()
  local test_opts

  before_each(function()
    -- Mock config for ACP provider
    local Config = require("avante.config")
    Config.provider = "codex"
    Config.acp_providers = {
      codex = {
        command = "echo",
        args = { "test" },
        env = {},
      },
    }

    test_opts = {
      system_prompt = "Test prompt",
      messages = {},
    }
  end)

  describe("when get_history_messages callback is provided", function()
    it("should use provided callback to retrieve history messages", function()
      local external_history = {
        History.Message:new("user", "Hello"),
      }

      test_opts.get_history_messages = function()
        return external_history
      end

      -- The implementation should use this callback instead of internal tracking
      assert.is_not_nil(test_opts.get_history_messages, "callback should be set")
      local retrieved = test_opts.get_history_messages()
      assert.are.equal(1, #retrieved, "should return external history")
      assert.are.equal("Hello", retrieved[1].message.content, "should have correct content")
    end)

    it("should update existing messages in external history by uuid", function()
      local message1 = History.Message:new("assistant", "Initial")
      local external_history = { message1 }

      test_opts.get_history_messages = function()
        return external_history
      end

      -- Simulate updating the same message (same uuid, different content)
      local updated_message = History.Message:new("assistant", "Updated")
      updated_message.uuid = message1.uuid

      test_opts.on_messages_add = function(messages)
        for _, msg in ipairs(messages) do
          for i, existing in ipairs(external_history) do
            if existing.uuid == msg.uuid then
              external_history[i] = msg
            end
          end
        end
      end

      test_opts.on_messages_add({ updated_message })

      local retrieved = test_opts.get_history_messages()
      assert.are.equal("Updated", retrieved[1].message.content, "message should be updated")
    end)
  end)

  describe("when get_history_messages callback is not provided", function()
    it("should maintain internal history messages array", function()
      local messages_added = {}

      test_opts.on_messages_add = function(messages)
        for _, msg in ipairs(messages) do
          table.insert(messages_added, msg)
        end
      end

      -- Add messages without external callback
      local msg1 = History.Message:new("user", "First message")
      local msg2 = History.Message:new("assistant", "Response")

      test_opts.on_messages_add({ msg1 })
      test_opts.on_messages_add({ msg2 })

      assert.are.equal(2, #messages_added, "should track 2 messages")
      assert.are.equal("First message", messages_added[1].message.content)
      assert.are.equal("Response", messages_added[2].message.content)
    end)

    it("should update existing messages in internal history by uuid", function()
      local messages_history = {}

      test_opts.on_messages_add = function(messages)
        for _, message in ipairs(messages) do
          local idx = nil
          for i, m in ipairs(messages_history) do
            if m.uuid == message.uuid then
              idx = i
              break
            end
          end
          if idx ~= nil then
            messages_history[idx] = message
          else
            table.insert(messages_history, message)
          end
        end
      end

      local msg1 = History.Message:new("assistant", "Original")
      test_opts.on_messages_add({ msg1 })

      assert.are.equal(1, #messages_history, "should have 1 message")

      -- Update with same uuid
      local msg1_updated = History.Message:new("assistant", "Modified")
      msg1_updated.uuid = msg1.uuid
      test_opts.on_messages_add({ msg1_updated })

      assert.are.equal(1, #messages_history, "should still have 1 message")
      assert.are.equal("Modified", messages_history[1].message.content, "content should be updated")
    end)

    it("should append new messages with different uuid", function()
      local messages_history = {}

      test_opts.on_messages_add = function(messages)
        for _, message in ipairs(messages) do
          local idx = nil
          for i, m in ipairs(messages_history) do
            if m.uuid == message.uuid then
              idx = i
              break
            end
          end
          if idx ~= nil then
            messages_history[idx] = message
          else
            table.insert(messages_history, message)
          end
        end
      end

      local msg1 = History.Message:new("user", "First")
      local msg2 = History.Message:new("assistant", "Second")

      test_opts.on_messages_add({ msg1 })
      test_opts.on_messages_add({ msg2 })

      assert.are.equal(2, #messages_history, "should have 2 distinct messages")
      assert.are_not.equal(msg1.uuid, msg2.uuid, "messages should have different uuids")
    end)
  end)

  describe("agent message chunk handling", function()
    it("should append text chunks to existing assistant message content", function()
      local messages_history = {}

      test_opts.get_history_messages = function()
        return messages_history
      end

      test_opts.on_messages_add = function(messages)
        for _, msg in ipairs(messages) do
          table.insert(messages_history, msg)
        end
      end

      -- Add initial assistant message
      local initial_msg = History.Message:new("assistant", "Hello")
      test_opts.on_messages_add({ initial_msg })

      -- Simulate appending chunk (this would be done by the streaming handler)
      messages_history[#messages_history].message.content =
        messages_history[#messages_history].message.content .. " world"

      assert.are.equal("Hello world", messages_history[1].message.content,
        "text chunks should be appended")
    end)

    it("should handle table content with text type", function()
      local messages_history = {}

      test_opts.get_history_messages = function()
        return messages_history
      end

      test_opts.on_messages_add = function(messages)
        for _, msg in ipairs(messages) do
          table.insert(messages_history, msg)
        end
      end

      -- Add message with structured content
      local msg = History.Message:new("assistant", {
        { type = "text", text = "Initial" }
      })
      test_opts.on_messages_add({ msg })

      -- Simulate appending chunk to structured content
      local content = messages_history[1].message.content
      for _, item in ipairs(content) do
        if type(item) == "table" and item.type == "text" then
          item.text = item.text .. " chunk"
        end
      end

      assert.are.equal("Initial chunk", messages_history[1].message.content[1].text,
        "text chunks should append to structured content")
    end)
  end)
end)
