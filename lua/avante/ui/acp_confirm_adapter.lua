---@class avante.ui.ConfirmAdapter
local M = {}

---@class avante.ui.ACPConfirmAdapter.ACPMappedOptions
---@field yes? string
---@field all? string
---@field no? string

---Converts the ACP permission options to confirmation popup-compatible format (yes/all/no)
---@param options avante.acp.PermissionOption[]
---@return avante.ui.ACPConfirmAdapter.ACPMappedOptions
function M.map_acp_options(options)
  local option_map = { yes = nil, all = nil, no = nil }

  for _, opt in ipairs(options) do
    if opt.kind == "allow_once" then
      option_map.yes = opt.optionId
    elseif opt.kind == "allow_always" then
      option_map.all = opt.optionId
    elseif opt.kind == "reject_once" then
      option_map.no = opt.optionId
    elseif opt.kind == "reject_always" then
      -- ignore, no 4th option in the confirm popup
    end
  end

  return option_map
end

return M
