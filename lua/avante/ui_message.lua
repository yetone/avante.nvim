local Utils = require("avante.utils")

---@class avante.UIMessage
local M = {}
M.__index = M

---@class avante.UIMessage.Opts
---@field displayed_content? string
---@field visible? boolean
---@field is_dummy? boolean
---@field just_for_display? boolean
---@field is_calling? boolean
---@field state? avante.HistoryMessageState
---@field ui_cache? table
---@field rendering_metadata? table
---@field computed_lines? avante.ui.Line[]
---

---Create a new UIMessage instance
---@param uuid string Reference to corresponding ModelMessage
---@param opts? avante.UIMessage.Opts
---@return avante.UIMessage
function M:new(uuid, opts)
  local obj = {
    uuid = uuid,
    displayed_content = nil,
    visible = true,
    is_dummy = false,
    just_for_display = false,
    is_calling = false,
    state = "generated",
    ui_cache = {},
    rendering_metadata = {},
    last_rendered_at = 0,
    computed_lines = nil,
  }
  obj = vim.tbl_extend("force", obj, opts or {})
  return setmetatable(obj, M)
end

---Creates a new synthetic UIMessage
---@param uuid string Reference UUID
---@param opts? avante.UIMessage.Opts
---@return avante.UIMessage
function M:new_synthetic(uuid, opts)
  local synthetic_opts = vim.tbl_extend("force", opts or {}, { is_dummy = true })
  return M:new(uuid, synthetic_opts)
end

---Update the visibility state
---@param visible boolean
function M:set_visible(visible)
  self.visible = visible
end

---Update the calling state
---@param is_calling boolean
function M:set_calling(is_calling)
  self.is_calling = is_calling
end

---Update the display content
---@param content string
function M:set_displayed_content(content)
  self.displayed_content = content
  -- Clear cached lines when content changes
  self.computed_lines = nil
  self.last_rendered_at = 0
end

---Update the UI state
---@param state avante.HistoryMessageState
function M:set_state(state)
  self.state = state
  self.is_calling = state == "generating"
end

---Check if the UI cache is valid
---@param model_timestamp? string Timestamp from corresponding ModelMessage
---@return boolean
function M:is_cache_valid(model_timestamp)
  if not self.computed_lines then
    return false
  end
  if model_timestamp and self.last_rendered_at < Utils.parse_timestamp(model_timestamp) then
    return false
  end
  return true
end

---Invalidate the UI cache
function M:invalidate_cache()
  self.computed_lines = nil
  self.ui_cache = {}
  self.last_rendered_at = 0
end

---Update cached lines and metadata
---@param lines avante.ui.Line[]
function M:update_cache(lines)
  self.computed_lines = lines
  self.last_rendered_at = os.time()
end

---Get cached lines if valid
---@param model_timestamp? string Timestamp from corresponding ModelMessage
---@return avante.ui.Line[] | nil
function M:get_cached_lines(model_timestamp)
  if self:is_cache_valid(model_timestamp) then
    return self.computed_lines
  end
  return nil
end

---Set rendering metadata
---@param key string
---@param value any
function M:set_rendering_metadata(key, value)
  self.rendering_metadata[key] = value
end

---Get rendering metadata
---@param key string
---@return any
function M:get_rendering_metadata(key)
  return self.rendering_metadata[key]
end

---Set UI cache value
---@param key string
---@param value any
function M:set_ui_cache(key, value)
  self.ui_cache[key] = value
end

---Get UI cache value
---@param key string
---@return any
function M:get_ui_cache(key)
  return self.ui_cache[key]
end

return M