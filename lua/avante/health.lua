local M = {}
local H = require("vim.health")
local Utils = require("avante.utils")
local Config = require("avante.config")

M.check = function()
  H.start("avante.nvim")

  -- Required dependencies
  local required_plugins = {
    ["nvim-treesitter"] = "nvim-treesitter/nvim-treesitter",
    ["dressing.nvim"] = "stevearc/dressing.nvim",
    ["plenary.nvim"] = "nvim-lua/plenary.nvim",
    ["nui.nvim"] = "MunifTanjim/nui.nvim",
  }

  for plugin_name, plugin_path in pairs(required_plugins) do
    if Utils.has(plugin_name) then
      H.ok(string.format("Found required plugin: %s", plugin_path))
    else
      H.error(string.format("Missing required plugin: %s", plugin_path))
    end
  end

  -- Optional dependencies
  local has_devicons = Utils.has("nvim-web-devicons")
  local has_mini_icons = Utils.has("mini.icons") or Utils.has("mini.nvim")
  if has_devicons or has_mini_icons then
    H.ok("Found icons plugin (nvim-web-devicons or mini.icons)")
  else
    H.warn("No icons plugin found (nvim-web-devicons or mini.icons). Icons will not be displayed")
  end

  -- Check Copilot if configured
  if Config.providers and Config.providers == "copilot" then
    if Utils.has("copilot.lua") or Utils.has("copilot.vim") then
      H.ok("Found Copilot plugin")
    else
      H.error("Copilot provider is configured but neither copilot.lua nor copilot.vim is installed")
    end
  end
end

return M
