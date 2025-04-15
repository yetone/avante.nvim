local Utils = require("avante.utils")
local Config = require("avante.config")
local Selector = require("avante.ui.selector")

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

  local items = vim
    .iter(models)
    :map(function(item)
      return {
        id = item.name,
        title = item.name,
      }
    end)
    :totable()

  local default_item = vim.iter(models):find(function(item) return item.provider == Config.provider end)

  local function on_select(item_ids)
    if not item_ids then return end
    local choice = vim.iter(models):find(function(item) return item.name == item_ids[1] end)
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
  end

  local selector = Selector:new({
    title = "Select Avante Model",
    items = items,
    default_item_id = default_item and default_item.name or nil,
    provider = Config.selector.provider,
    provider_opts = Config.selector.provider_opts,
    on_select = on_select,
  })

  selector:open()
end

return M
