---@class avante.ui.ConfirmAdapter
local M = {}

---@class avante.ui.ConfirmAdapter.MappedOptions
---@field has_allow_once boolean
---@field has_allow_always boolean
---@field has_reject boolean
---@field option_map table<string, string>

---@class avante.acp.PermissionOption
---@field kind "allow_once" | "allow_always" | "reject_once" | "reject_always" | string
---@field optionId string
---@field name string

---Convert ACP permission options to popup-compatible format
---Maps ACP option kinds to popup button types (yes/all/no)
---@param options avante.acp.PermissionOption[]
---@return avante.ui.ConfirmAdapter.MappedOptions
function M.map_acp_options(options)
  local option_map = { yes = nil, all = nil, no = nil }
  local has = { allow_once = false, allow_always = false, reject = false }

  for _, opt in ipairs(options) do
    if opt.kind == "allow_once" and not option_map.yes then
      option_map.yes = opt.optionId
      has.allow_once = true
    elseif opt.kind == "allow_always" and not option_map.all then
      option_map.all = opt.optionId
      has.allow_always = true
    elseif (opt.kind == "reject_once" or opt.kind == "reject_always") and not option_map.no then
      option_map.no = opt.optionId
      has.reject = true
    end
  end

  return {
    has_allow_once = has.allow_once,
    has_allow_always = has.allow_always,
    has_reject = has.reject,
    option_map = option_map,
  }
end

---Create callback bridge from popup to ACP
---Translates popup callback responses ("yes", "all", "no") to ACP option IDs
---@param acp_callback fun(id: string|nil)
---@param option_map table<string, string>
---@return fun(type: "yes"|"all"|"no")
function M.create_acp_callback_bridge(acp_callback, option_map)
  return function(type)
    local option_id = option_map[type]

    if option_id then
      acp_callback(option_id)
      return
    end

    -- Fallback: if option not available, use yes or cancel
    local fallback = option_map.yes
    if fallback then
      acp_callback(fallback)
    else
      acp_callback(nil) -- Cancel if no valid option
    end
  end
end

---@class avante.acp.ToolCall
---@field kind "read" | "edit" | "delete" | "move" | "search" | "execute" | "fetch" | string
---@field title? string
---@field toolCallId? string

---Get confirmation message for ACP tool call
---Formats tool call details into a readable permission request message
---@param tool_call avante.acp.ToolCall
---@return string
function M.get_acp_message(tool_call)
  local kind_desc = {
    read = "read",
    edit = "edit",
    delete = "delete",
    move = "move",
    search = "search",
    execute = "execute",
    fetch = "fetch",
  }

  local action = kind_desc[tool_call.kind] or "perform"
  local title = tool_call.title or ""

  return string.format("Allow %s: %s", action, title)
end

return M
