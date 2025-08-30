local History = require("avante.history.init")
local MessageConverter = require("avante.message_converter")
local Utils = require("avante.utils")

describe("History Separated Architecture", function()
  local sample_history_messages

  before_each(function()
    -- Clear stores before each test
    History.clear_stores()
    
    -- Create sample history messages
    sample_history_messages = {
      {
        message = { role = "user", content = "Hello" },
        uuid = "uuid1",
        timestamp = Utils.get_timestamp(),
        state = "generated",
        visible = true,
        is_user_submission = true,
        provider = "claude",
        model = "claude-3-sonnet",
      },
      {
        message = { role = "assistant", content = "Hi there!" },
        uuid = "uuid2", 
        timestamp = Utils.get_timestamp(),
        state = "generated",
        visible = true,
        displayed_content = "Custom display",
        is_dummy = false,
        provider = "claude",
        model = "claude-3-sonnet",
      },
      {
        message = { role = "assistant", content = "Tool result" },
        uuid = "uuid3",
        timestamp = Utils.get_timestamp(), 
        state = "generated",
        visible = false,
        is_dummy = true,
      }
    }
  end)

  after_each(function()
    History.clear_stores()
  end)

  describe("store management", function()
    it("should add and retrieve ModelMessages", function()
      local model_msg = {
        uuid = "test-uuid",
        message = { role = "user", content = "Test" },
        timestamp = Utils.get_timestamp(),
        state = "generated",
        provider = "claude",
      }

      History.add_model_message(model_msg)
      local retrieved = History.get_model_message("test-uuid")

      assert.same(model_msg, retrieved)
    end)

    it("should return nil for non-existent ModelMessage", function()
      local result = History.get_model_message("nonexistent")
      assert.is_nil(result)
    end)

    it("should add and retrieve UIMessages", function()
      local ui_msg = {
        uuid = "test-uuid",
        visible = true,
        displayed_content = "Display text",
        is_dummy = false,
        state = "generated",
      }

      History.add_ui_message(ui_msg)
      local retrieved = History.get_ui_message("test-uuid")

      assert.same(ui_msg, retrieved)
    end)

    it("should get all ModelMessages sorted by timestamp", function()
      local msg1 = {
        uuid = "uuid1",
        message = { role = "user", content = "First" },
        timestamp = "2023-01-01T00:00:00Z",
        state = "generated",
      }
      local msg2 = {
        uuid = "uuid2",
        message = { role = "user", content = "Second" },
        timestamp = "2023-01-02T00:00:00Z",
        state = "generated",
      }

      History.add_model_message(msg2) -- Add in reverse order
      History.add_model_message(msg1)

      local all_messages = History.get_all_model_messages()

      assert.equals(2, #all_messages)
      assert.equals("uuid1", all_messages[1].uuid) -- Should be first due to earlier timestamp
      assert.equals("uuid2", all_messages[2].uuid)
    end)

    it("should get visible UIMessages only", function()
      local model_msg1 = {
        uuid = "uuid1",
        message = { role = "user", content = "Visible" },
        timestamp = Utils.get_timestamp(),
        state = "generated",
      }
      local model_msg2 = {
        uuid = "uuid2",
        message = { role = "user", content = "Hidden" },
        timestamp = Utils.get_timestamp(),
        state = "generated",
      }

      local ui_msg1 = {
        uuid = "uuid1",
        visible = true,
        state = "generated",
      }
      local ui_msg2 = {
        uuid = "uuid2",
        visible = false,
        state = "generated",
      }

      History.add_model_message(model_msg1)
      History.add_model_message(model_msg2)
      History.add_ui_message(ui_msg1)
      History.add_ui_message(ui_msg2)

      local visible = History.get_visible_ui_messages()

      assert.equals(1, #visible)
      assert.equals("uuid1", visible[1].uuid)
    end)
  end)

  describe("store conversion", function()
    it("should load from HistoryMessages", function()
      History.load_from_history_messages(sample_history_messages)

      local model_store = History.get_model_store()
      local ui_store = History.get_ui_store()

      -- Check that all messages were loaded
      assert.equals(3, vim.tbl_count(model_store))
      assert.equals(3, vim.tbl_count(ui_store))

      -- Check specific message conversion
      local model_msg1 = model_store["uuid1"]
      local ui_msg1 = ui_store["uuid1"]

      assert.is_not_nil(model_msg1)
      assert.is_not_nil(ui_msg1)
      
      assert.equals("user", model_msg1.message.role)
      assert.equals("Hello", model_msg1.message.content)
      assert.equals("claude", model_msg1.provider)
      assert.equals(true, model_msg1.is_user_submission)
      
      assert.equals("uuid1", ui_msg1.uuid)
      assert.equals(true, ui_msg1.visible)
      assert.equals(false, ui_msg1.is_dummy)
    end)

    it("should convert back to HistoryMessages", function()
      History.load_from_history_messages(sample_history_messages)
      
      local reconstructed = History.to_history_messages()

      assert.equals(3, #reconstructed)
      
      -- Check that data is preserved (order might differ due to timestamp sorting)
      local by_uuid = {}
      for _, msg in ipairs(reconstructed) do
        by_uuid[msg.uuid] = msg
      end

      local msg1 = by_uuid["uuid1"]
      assert.is_not_nil(msg1)
      assert.equals("user", msg1.message.role)
      assert.equals("Hello", msg1.message.content)
      assert.equals(true, msg1.visible)
      assert.equals(true, msg1.is_user_submission)
      assert.equals("claude", msg1.provider)

      local msg2 = by_uuid["uuid2"]
      assert.is_not_nil(msg2)
      assert.equals("assistant", msg2.message.role)
      assert.equals("Custom display", msg2.displayed_content)
      assert.equals(true, msg2.visible)
      assert.equals(false, msg2.is_dummy)

      local msg3 = by_uuid["uuid3"]
      assert.is_not_nil(msg3)
      assert.equals(false, msg3.visible)
      assert.equals(true, msg3.is_dummy)
    end)

    it("should handle round-trip conversion without data loss", function()
      History.load_from_history_messages(sample_history_messages)
      local reconstructed = History.to_history_messages()
      
      -- Clear and reload from reconstructed
      History.clear_stores()
      History.load_from_history_messages(reconstructed)
      local second_round = History.to_history_messages()

      -- Should have same number of messages
      assert.equals(#sample_history_messages, #second_round)

      -- Check key data is preserved
      local original_by_uuid = {}
      for _, msg in ipairs(sample_history_messages) do
        original_by_uuid[msg.uuid] = msg
      end

      local final_by_uuid = {}
      for _, msg in ipairs(second_round) do
        final_by_uuid[msg.uuid] = msg
      end

      for uuid, original in pairs(original_by_uuid) do
        local final = final_by_uuid[uuid]
        assert.is_not_nil(final, "Missing message with UUID: " .. uuid)
        
        assert.equals(original.message.role, final.message.role)
        assert.equals(original.message.content, final.message.content)
        assert.equals(original.visible, final.visible)
        assert.equals(original.is_dummy, final.is_dummy)
        assert.equals(original.provider, final.provider)
        assert.equals(original.model, final.model)
        assert.equals(original.displayed_content, final.displayed_content)
      end
    end)
  end)

  describe("store access", function()
    it("should get model store reference", function()
      local model_msg = {
        uuid = "test",
        message = { role = "user", content = "Test" },
        timestamp = Utils.get_timestamp(),
        state = "generated",
      }

      History.add_model_message(model_msg)
      
      local store = History.get_model_store()
      
      assert.same(model_msg, store["test"])
    end)

    it("should get UI store reference", function()
      local ui_msg = {
        uuid = "test",
        visible = true,
        state = "generated",
      }

      History.add_ui_message(ui_msg)
      
      local store = History.get_ui_store()
      
      assert.same(ui_msg, store["test"])
    end)
  end)

  describe("store clearing", function()
    it("should clear both stores", function()
      -- Add some test data
      local model_msg = {
        uuid = "test",
        message = { role = "user", content = "Test" },
        timestamp = Utils.get_timestamp(),
        state = "generated",
      }
      local ui_msg = {
        uuid = "test",
        visible = true,
        state = "generated",
      }

      History.add_model_message(model_msg)
      History.add_ui_message(ui_msg)

      -- Verify data exists
      assert.is_not_nil(History.get_model_message("test"))
      assert.is_not_nil(History.get_ui_message("test"))

      -- Clear and verify empty
      History.clear_stores()
      
      assert.is_nil(History.get_model_message("test"))
      assert.is_nil(History.get_ui_message("test"))
      assert.equals(0, #History.get_all_model_messages())
      assert.equals(0, #History.get_visible_ui_messages())
    end)
  end)
end)