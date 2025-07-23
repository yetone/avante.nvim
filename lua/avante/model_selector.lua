local Utils = require("avante.utils")
local Providers = require("avante.providers")
local Config = require("avante.config")
local Selector = require("avante.ui.selector")

---@class avante.ModelSelector
local M = {}

M.models_list_invoked = {}
M.models_list_returned = {}

local models_list_cached_result = {}

---@param provider_name string
---@param provider_cfg table
---@return table
local function create_model_entries(provider_name, provider_cfg)
  if provider_cfg.models_list and provider_cfg.__inherited_from == nil then
    local models_list
    if type(provider_cfg.models_list) == "function" then
      if M.models_list_invoked[provider_cfg.models_list] then return {} end
      M.models_list_invoked[provider_cfg.models_list] = true
      local cached_result = models_list_cached_result[provider_cfg.models_list]
      if cached_result then
        models_list = cached_result
      else
        models_list = provider_cfg:models_list()
        models_list_cached_result[provider_cfg.models_list] = models_list
      end
    else
      if M.models_list_returned[provider_cfg.models_list] then return {} end
      M.models_list_returned[provider_cfg.models_list] = true
      models_list = provider_cfg.models_list
    end
    if not models_list then return {} end
    -- If models_list is defined, use it to create entries
    local models = vim
      .iter(models_list)
      :map(
        function(model)
          return {
            name = model.name or model.id,
            display_name = model.display_name or model.name or model.id,
            provider_name = provider_name,
            model = model.id,
          }
        end
      )
      :totable()
    return models
  end
  return provider_cfg.model
      and {
        {
          name = provider_cfg.display_name or (provider_name .. "/" .. provider_cfg.model),
          display_name = provider_cfg.display_name or (provider_name .. "/" .. provider_cfg.model),
          provider_name = provider_name,
          model = provider_cfg.model,
        },
      }
    or {}
end

function M.open()
  M.models_list_invoked = {}
  M.models_list_returned = {}
  local models = {}

  -- Collect models from providers
  for provider_name, _ in pairs(Config.providers) do
    local provider_cfg = Providers[provider_name]
    if provider_cfg.hide_in_model_selector then goto continue end
    if not provider_cfg.is_env_set() then goto continue end
    local entries = create_model_entries(provider_name, provider_cfg)
    models = vim.list_extend(models, entries)
    ::continue::
  end

  -- Sort models by name for stable display
  table.sort(models, function(a, b) return (a.name or "") < (b.name or "") end)

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
      providers = {
        [choice.provider_name] = vim.tbl_deep_extend(
          "force",
          Config.get_provider_config(choice.provider_name),
          { model = choice.model }
        ),
      },
    })

    local provider_cfg = Providers[choice.provider_name]
    if provider_cfg then provider_cfg.model = choice.model end

    Utils.info("Switched to model: " .. choice.name)
    -- Persist last used provider and model
    Config.save_last_model(choice.model, choice.provider_name)
  end

  local selector = Selector:new({
    title = "Select Avante Model",
    items = items,
    default_item_id = default_item and default_item.name or nil,
    provider = Config.selector.provider,
    provider_opts = Config.selector.provider_opts,
    on_select = on_select,
    get_preview_content = function(item_id)
      local model = vim.iter(models):find(function(item) return item.name == item_id end)
      if not model then return "", "markdown" end
      return model.name, "markdown"
    end,
  })

  selector:open()
end

return M
