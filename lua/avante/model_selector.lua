local Utils = require("avante.utils")
local Config = require("avante.config")

---@class avante.ModelSelector
local M = {}

---@param provider string
---@param cfg table
---@return table?
local function create_model_entry(provider, cfg)
  return cfg.model and {
    name = provider .. "/" .. cfg.model,
    provider = provider,
    model = cfg.model,
  }
end

function M.open()
  local models = {}

  -- Collect models from main providers and vendors
  for _, provider in ipairs(Config.providers) do
    local entry = create_model_entry(provider, Config.get_provider(provider))
    if entry then table.insert(models, entry) end
  end

  if #models == 0 then
    Utils.warn("No models available in config")
    return
  end

  vim.ui.select(models, {
    prompt = "Select Model:",
    format_item = function(item) return item.name end,
  }, function(choice)
    if not choice then return end

    -- Switch provider if needed
    if choice.provider ~= Config.provider then require("avante.providers").refresh(choice.provider) end

    -- Update config with new model
    Config.override({
      [choice.provider] = vim.tbl_deep_extend("force", Config.get_provider(choice.provider), { model = choice.model }),
    })

    Utils.info("Switched to model: " .. choice.name)
  end)
end

return M
