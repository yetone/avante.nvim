---@class avante.MessageConverter
local MessageConverter = {}

---Convert ModelMessage to UIMessage
---@param model_msg avante.ModelMessage
---@return avante.UIMessage
function MessageConverter.to_ui_message(model_msg)
  return {
    uuid = model_msg.uuid,
    displayed_content = nil, -- Computed on demand
    visible = true,
    is_dummy = model_msg.is_dummy or false,
    just_for_display = false,
    is_calling = model_msg.state == "generating",
    state = model_msg.state,
    ui_cache = {},
    rendering_metadata = {},
    last_rendered_at = 0,
    computed_lines = nil,
  }
end

---Convert UIMessage back to ModelMessage (for compatibility)
---@param ui_msg avante.UIMessage
---@param model_store table<string, avante.ModelMessage>
---@return avante.ModelMessage | nil
function MessageConverter.to_model_message(ui_msg, model_store)
  local model_msg = model_store[ui_msg.uuid]
  if not model_msg then
    return nil
  end
  return model_msg
end

---Convert HistoryMessage to ModelMessage
---@param hist_msg avante.HistoryMessage
---@return avante.ModelMessage
function MessageConverter.history_to_model_message(hist_msg)
  return {
    message = hist_msg.message,
    timestamp = hist_msg.timestamp,
    uuid = hist_msg.uuid,
    provider = hist_msg.provider,
    model = hist_msg.model,
    tool_use_logs = hist_msg.tool_use_logs,
    tool_use_store = hist_msg.tool_use_store,
    turn_id = hist_msg.turn_id,
    original_content = hist_msg.original_content,
    selected_code = hist_msg.selected_code,
    selected_filepaths = hist_msg.selected_filepaths,
    is_user_submission = hist_msg.is_user_submission,
    is_context = hist_msg.is_context,
    is_compacted = hist_msg.is_compacted,
    is_deleted = hist_msg.is_deleted,
    state = hist_msg.state,
  }
end

---Convert HistoryMessage to UIMessage
---@param hist_msg avante.HistoryMessage
---@return avante.UIMessage
function MessageConverter.history_to_ui_message(hist_msg)
  return {
    uuid = hist_msg.uuid,
    displayed_content = hist_msg.displayed_content,
    visible = hist_msg.visible ~= false, -- Default to true if nil
    is_dummy = hist_msg.is_dummy or false,
    just_for_display = hist_msg.just_for_display or false,
    is_calling = hist_msg.is_calling or false,
    state = hist_msg.state,
    ui_cache = {},
    rendering_metadata = {},
    last_rendered_at = 0,
    computed_lines = nil,
  }
end

---Convert ModelMessage and UIMessage back to HistoryMessage (for compatibility)
---@param model_msg avante.ModelMessage
---@param ui_msg avante.UIMessage
---@return avante.HistoryMessage
function MessageConverter.to_history_message(model_msg, ui_msg)
  return {
    message = model_msg.message,
    timestamp = model_msg.timestamp,
    state = model_msg.state,
    uuid = model_msg.uuid,
    displayed_content = ui_msg.displayed_content,
    visible = ui_msg.visible,
    is_context = model_msg.is_context,
    is_user_submission = model_msg.is_user_submission,
    provider = model_msg.provider,
    model = model_msg.model,
    selected_code = model_msg.selected_code,
    selected_filepaths = model_msg.selected_filepaths,
    tool_use_logs = model_msg.tool_use_logs,
    tool_use_store = model_msg.tool_use_store,
    just_for_display = ui_msg.just_for_display,
    is_dummy = ui_msg.is_dummy,
    is_compacted = model_msg.is_compacted,
    is_deleted = model_msg.is_deleted,
    turn_id = model_msg.turn_id,
    is_calling = ui_msg.is_calling,
    original_content = model_msg.original_content,
  }
end

---Validate message conversion integrity
---@param original avante.ModelMessage
---@param converted avante.UIMessage
---@return boolean success
---@return string? error_msg
function MessageConverter.validate_conversion(original, converted)
  if original.uuid ~= converted.uuid then
    return false, "UUID mismatch in conversion"
  end
  if (original.is_dummy or false) ~= converted.is_dummy then
    return false, "is_dummy flag mismatch"
  end
  return true, nil
end

---Batch convert ModelMessages to UIMessages
---@param model_messages avante.ModelMessage[]
---@return avante.UIMessage[]
function MessageConverter.batch_to_ui_messages(model_messages)
  local ui_messages = {}
  for _, model_msg in ipairs(model_messages) do
    table.insert(ui_messages, MessageConverter.to_ui_message(model_msg))
  end
  return ui_messages
end

---Batch convert HistoryMessages to ModelMessages and UIMessages
---@param history_messages avante.HistoryMessage[]
---@return avante.ModelMessage[], avante.UIMessage[]
function MessageConverter.batch_convert_history(history_messages)
  local model_messages = {}
  local ui_messages = {}
  for _, hist_msg in ipairs(history_messages) do
    table.insert(model_messages, MessageConverter.history_to_model_message(hist_msg))
    table.insert(ui_messages, MessageConverter.history_to_ui_message(hist_msg))
  end
  return model_messages, ui_messages
end

return MessageConverter