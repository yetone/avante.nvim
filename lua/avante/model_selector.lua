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

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_index = 1
local spinner_timer = nil
local spinner_msg_id = nil

local function start_spinner()
  spinner_msg_id = vim.notify("Fetching available models... " .. spinner_frames[spinner_index], vim.log.levels.INFO, {
    title = "Avante",
    replace = spinner_msg_id,
  })

  spinner_index = (spinner_index % #spinner_frames) + 1
  spinner_timer = vim.defer_fn(start_spinner, 100)
end

local function stop_spinner()
  if spinner_timer then
    vim.loop.timer_stop(spinner_timer)
    spinner_timer = nil
  end

  if spinner_msg_id then
    vim.notify("Models fetched successfully", vim.log.levels.INFO, {
      title = "Avante",
      replace = spinner_msg_id,
    })
  end
end

---@param dynamic_models table<string, table<string, any>[]>
local function display_model_selector(dynamic_models)
  local models = {}

  for provider_name, provider_models in pairs(dynamic_models) do
    if provider_models and #provider_models > 0 then
      for _, model in ipairs(provider_models) do
        table.insert(models, {
          name = provider_name .. "/" .. model.name,
          provider_name = provider_name,
          model = model.id or model.name,
          description = model.description,
          dynamic = true,
        })
      end
    end
  end

  for _, provider_name in ipairs(Config.provider_names) do
    if dynamic_models[provider_name] and #dynamic_models[provider_name] > 0 then goto continue end

    local cfg = Config.get_provider_config(provider_name)
    if cfg.hide_in_model_selector then goto continue end
    local entry = create_model_entry(provider_name, cfg)
    if entry then table.insert(models, entry) end
    ::continue::
  end

  if #models == 0 then
    Utils.warn("No models available in config or from providers")
    return
  end

  table.sort(models, function(a, b)
    if a.provider_name ~= b.provider_name then
      return a.provider_name < b.provider_name
    else
      return a.name < b.name
    end
  end)

  vim.ui.select(models, {
    prompt = "Select Avante Model:",
    format_item = function(item)
      local display = item.name
      if item.description then display = display .. " - " .. item.description end
      return display
    end,
  }, function(choice)
    if not choice then
      stop_spinner()
      return
    end

    if choice.provider_name ~= Config.provider then require("avante.providers").refresh(choice.provider_name) end

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

local function get_models_for_provider(provider_name, providers_to_check, results, on_complete)
  local provider = require("avante.providers")[provider_name]

  provider:get_available_models(function(models, err)
    results[provider_name] = models or {}

    if err then Utils.debug("Error getting models for " .. provider_name .. ": " .. err) end

    providers_to_check[provider_name] = nil

    local remaining = 0
    for _ in pairs(providers_to_check) do
      remaining = remaining + 1
    end

    if remaining == 0 then on_complete(results) end
  end)
end

function M.open()
  spinner_index = 1
  spinner_timer = nil
  spinner_msg_id = nil

  start_spinner()

  local dynamic_models = {}
  local providers_to_check = {}

  local Providers = require("avante.providers")

  for _, provider_name in ipairs(Config.provider_names) do
    local success, provider = pcall(function() return Providers[provider_name] end)

    if not success then Utils.debug("Failed to load provider for model selection: " .. provider_name) end

    if provider ~= nil and type(provider.get_available_models) == "function" then
      providers_to_check[provider_name] = true
      dynamic_models[provider_name] = {}
    end
  end

  if vim.tbl_isempty(providers_to_check) then
    stop_spinner()
    return display_model_selector(dynamic_models)
  end

  for provider_name in pairs(providers_to_check) do
    get_models_for_provider(provider_name, providers_to_check, dynamic_models, function(results)
      stop_spinner()
      display_model_selector(results)
    end)
  end
end

return M
