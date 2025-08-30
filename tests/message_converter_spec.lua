local MessageConverter = require("avante.message_converter")
local ModelMessage = require("avante.model_message")
local UIMessage = require("avante.ui_message")
local Utils = require("avante.utils")

describe("MessageConverter", function()
  local sample_uuid
  local sample_timestamp

  before_each(function()
    sample_uuid = Utils.uuid()
    sample_timestamp = Utils.get_timestamp()
  end)

  describe("to_ui_message", function()
    it("should convert ModelMessage to UIMessage", function()
      local model_msg = {
        uuid = sample_uuid,
        message = { role = "user", content = "Hello" },
        timestamp = sample_timestamp,
        state = "generated",
        is_dummy = false,
        provider = "claude",
        model = "claude-3-sonnet",
      }

      local ui_msg = MessageConverter.to_ui_message(model_msg)

      assert.equals(sample_uuid, ui_msg.uuid)
      assert.equals(true, ui_msg.visible)
      assert.equals(false, ui_msg.is_dummy)
      assert.equals(false, ui_msg.just_for_display)
      assert.equals(false, ui_msg.is_calling)
      assert.equals("generated", ui_msg.state)
      assert.same({}, ui_msg.ui_cache)
      assert.same({}, ui_msg.rendering_metadata)
    end)

    it("should handle generating state correctly", function()
      local model_msg = {
        uuid = sample_uuid,
        message = { role = "assistant", content = "Thinking..." },
        timestamp = sample_timestamp,
        state = "generating",
        is_dummy = false,
      }

      local ui_msg = MessageConverter.to_ui_message(model_msg)

      assert.equals(true, ui_msg.is_calling)
      assert.equals("generating", ui_msg.state)
    end)

    it("should handle dummy messages", function()
      local model_msg = {
        uuid = sample_uuid,
        message = { role = "assistant", content = "Tool result" },
        timestamp = sample_timestamp,
        state = "generated",
        is_dummy = true,
      }

      local ui_msg = MessageConverter.to_ui_message(model_msg)

      assert.equals(true, ui_msg.is_dummy)
    end)
  end)

  describe("validate_conversion", function()
    it("should validate successful conversion", function()
      local model_msg = {
        uuid = sample_uuid,
        is_dummy = false,
      }
      
      local ui_msg = {
        uuid = sample_uuid,
        is_dummy = false,
      }

      local success, error_msg = MessageConverter.validate_conversion(model_msg, ui_msg)
      
      assert.equals(true, success)
      assert.equals(nil, error_msg)
    end)

    it("should detect UUID mismatch", function()
      local model_msg = {
        uuid = "uuid1",
        is_dummy = false,
      }
      
      local ui_msg = {
        uuid = "uuid2",
        is_dummy = false,
      }

      local success, error_msg = MessageConverter.validate_conversion(model_msg, ui_msg)
      
      assert.equals(false, success)
      assert.equals("UUID mismatch in conversion", error_msg)
    end)

    it("should detect is_dummy flag mismatch", function()
      local model_msg = {
        uuid = sample_uuid,
        is_dummy = true,
      }
      
      local ui_msg = {
        uuid = sample_uuid,
        is_dummy = false,
      }

      local success, error_msg = MessageConverter.validate_conversion(model_msg, ui_msg)
      
      assert.equals(false, success)
      assert.equals("is_dummy flag mismatch", error_msg)
    end)
  end)

  describe("history message conversion", function()
    it("should convert HistoryMessage to ModelMessage", function()
      local hist_msg = {
        message = { role = "user", content = "Test message" },
        uuid = sample_uuid,
        timestamp = sample_timestamp,
        state = "generated",
        provider = "claude",
        model = "claude-3-sonnet",
        tool_use_logs = { "log1", "log2" },
        tool_use_store = { key = "value" },
        turn_id = "turn123",
        original_content = "Original",
        selected_code = { path = "/test.lua", content = "code" },
        selected_filepaths = { "/test.lua" },
        is_user_submission = true,
        is_context = false,
        is_compacted = false,
        is_deleted = false,
      }

      local model_msg = MessageConverter.history_to_model_message(hist_msg)

      assert.same(hist_msg.message, model_msg.message)
      assert.equals(hist_msg.uuid, model_msg.uuid)
      assert.equals(hist_msg.timestamp, model_msg.timestamp)
      assert.equals(hist_msg.state, model_msg.state)
      assert.equals(hist_msg.provider, model_msg.provider)
      assert.equals(hist_msg.model, model_msg.model)
      assert.same(hist_msg.tool_use_logs, model_msg.tool_use_logs)
      assert.same(hist_msg.tool_use_store, model_msg.tool_use_store)
      assert.equals(hist_msg.turn_id, model_msg.turn_id)
      assert.equals(hist_msg.original_content, model_msg.original_content)
      assert.same(hist_msg.selected_code, model_msg.selected_code)
      assert.same(hist_msg.selected_filepaths, model_msg.selected_filepaths)
      assert.equals(hist_msg.is_user_submission, model_msg.is_user_submission)
      assert.equals(hist_msg.is_context, model_msg.is_context)
      assert.equals(hist_msg.is_compacted, model_msg.is_compacted)
      assert.equals(hist_msg.is_deleted, model_msg.is_deleted)
    end)

    it("should convert HistoryMessage to UIMessage", function()
      local hist_msg = {
        uuid = sample_uuid,
        displayed_content = "Displayed text",
        visible = true,
        is_dummy = true,
        just_for_display = false,
        is_calling = true,
        state = "generating",
      }

      local ui_msg = MessageConverter.history_to_ui_message(hist_msg)

      assert.equals(hist_msg.uuid, ui_msg.uuid)
      assert.equals(hist_msg.displayed_content, ui_msg.displayed_content)
      assert.equals(hist_msg.visible, ui_msg.visible)
      assert.equals(hist_msg.is_dummy, ui_msg.is_dummy)
      assert.equals(hist_msg.just_for_display, ui_msg.just_for_display)
      assert.equals(hist_msg.is_calling, ui_msg.is_calling)
      assert.equals(hist_msg.state, ui_msg.state)
    end)

    it("should handle nil visible as true", function()
      local hist_msg = {
        uuid = sample_uuid,
        visible = nil,
        is_dummy = false,
        just_for_display = false,
        is_calling = false,
        state = "generated",
      }

      local ui_msg = MessageConverter.history_to_ui_message(hist_msg)

      assert.equals(true, ui_msg.visible) -- Default to true when nil
    end)
  end)

  describe("batch conversion", function()
    it("should batch convert ModelMessages to UIMessages", function()
      local model_messages = {
        {
          uuid = "uuid1",
          message = { role = "user", content = "Message 1" },
          timestamp = sample_timestamp,
          state = "generated",
          is_dummy = false,
        },
        {
          uuid = "uuid2", 
          message = { role = "assistant", content = "Message 2" },
          timestamp = sample_timestamp,
          state = "generating",
          is_dummy = true,
        }
      }

      local ui_messages = MessageConverter.batch_to_ui_messages(model_messages)

      assert.equals(2, #ui_messages)
      assert.equals("uuid1", ui_messages[1].uuid)
      assert.equals("uuid2", ui_messages[2].uuid)
      assert.equals(false, ui_messages[1].is_calling)
      assert.equals(true, ui_messages[2].is_calling)
      assert.equals(false, ui_messages[1].is_dummy)
      assert.equals(true, ui_messages[2].is_dummy)
    end)

    it("should batch convert HistoryMessages", function()
      local history_messages = {
        {
          message = { role = "user", content = "Message 1" },
          uuid = "uuid1",
          timestamp = sample_timestamp,
          state = "generated",
          visible = true,
          is_dummy = false,
        },
        {
          message = { role = "assistant", content = "Message 2" },
          uuid = "uuid2",
          timestamp = sample_timestamp,
          state = "generated",
          visible = false,
          is_dummy = true,
        }
      }

      local model_messages, ui_messages = MessageConverter.batch_convert_history(history_messages)

      assert.equals(2, #model_messages)
      assert.equals(2, #ui_messages)
      
      assert.equals("uuid1", model_messages[1].uuid)
      assert.equals("uuid2", model_messages[2].uuid)
      
      assert.equals("uuid1", ui_messages[1].uuid)
      assert.equals("uuid2", ui_messages[2].uuid)
      
      assert.equals(true, ui_messages[1].visible)
      assert.equals(false, ui_messages[2].visible)
    end)
  end)

  describe("round-trip conversion", function()
    it("should preserve data in round-trip conversion", function()
      local original_model = {
        message = { role = "user", content = "Test content" },
        uuid = sample_uuid,
        timestamp = sample_timestamp,
        state = "generated",
        provider = "claude",
        model = "claude-3-sonnet",
        is_dummy = false,
      }

      local original_ui = {
        uuid = sample_uuid,
        displayed_content = "Display content",
        visible = true,
        is_dummy = false,
        just_for_display = false,
        is_calling = false,
        state = "generated",
      }

      local hist_msg = MessageConverter.to_history_message(original_model, original_ui)
      local converted_model = MessageConverter.history_to_model_message(hist_msg)
      local converted_ui = MessageConverter.history_to_ui_message(hist_msg)

      -- Check key fields are preserved
      assert.same(original_model.message, converted_model.message)
      assert.equals(original_model.uuid, converted_model.uuid)
      assert.equals(original_model.provider, converted_model.provider)
      assert.equals(original_model.model, converted_model.model)
      
      assert.equals(original_ui.uuid, converted_ui.uuid)
      assert.equals(original_ui.displayed_content, converted_ui.displayed_content)
      assert.equals(original_ui.visible, converted_ui.visible)
      assert.equals(original_ui.is_dummy, converted_ui.is_dummy)
    end)
  end)
end)