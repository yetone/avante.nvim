local Utils = require("avante.utils")
local Config = require("avante.config")

---@class avante.ModelSelector
local M = {}

---@param provider_name string
---@param cfg table
---@return table?
local function create_model_entry(provider_name, cfg)
  return cfg.model
    and {
      name = cfg.display_name or (provider_name .. "/" .. cfg.model),
      provider_name = provider_name,
      model = cfg.model,
    }
end

function M.open()
  local models = {}

  -- Collect models from main providers and vendors
  for _, provider_name in ipairs(Config.provider_names) do
    local cfg = Config.get_provider_config(provider_name)
    if cfg.hide_in_model_selector then goto continue end
    local entry = create_model_entry(provider_name, cfg)
    if entry then table.insert(models, entry) end
    ::continue::
  end

  if #models == 0 then
    Utils.warn("No models available in config")
    return
  end

  vim.ui.select(models, {
    prompt = "Select Avante Model:",
    format_item = function(item) return item.name end,
  }, function(choice)
    if not choice then return end

    -- Switch provider if needed
    if choice.provider_name ~= Config.provider then require("avante.providers").refresh(choice.provider_name) end

    -- Update config with new model
    Config.override({
      [choice.provider_name] = vim.tbl_deep_extend(
        "force",
        Config.get_provider_config(choice.provider_name),
        { model = choice.model }
      ),
    })

    Utils.info("Switched to model: " .. choice.name)
  end)
end

return M
