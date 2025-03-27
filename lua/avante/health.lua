local M = {}
local H = require("vim.health")
local Utils = require("avante.utils")
local Config = require("avante.config")

function M.check()
  H.start("avante.nvim")

  -- Required dependencies with their module names
  local required_plugins = {
    ["nvim-treesitter"] = {
      path = "nvim-treesitter/nvim-treesitter",
      module = "nvim-treesitter",
    },
    ["dressing.nvim"] = {
      path = "stevearc/dressing.nvim",
      module = "dressing",
    },
    ["plenary.nvim"] = {
      path = "nvim-lua/plenary.nvim",
      module = "plenary",
    },
    ["nui.nvim"] = {
      path = "MunifTanjim/nui.nvim",
      module = "nui.popup",
    },
  }

  for name, plugin in pairs(required_plugins) do
    if Utils.has(name) or Utils.has(plugin.module) then
      H.ok(string.format("Found required plugin: %s", plugin.path))
    else
      H.error(string.format("Missing required plugin: %s", plugin.path))
    end
  end

  -- Optional dependencies
  if Utils.icons_enabled() then
    H.ok("Found icons plugin (nvim-web-devicons or mini.icons)")
  else
    H.warn("No icons plugin found (nvim-web-devicons or mini.icons). Icons will not be displayed")
  end

  -- Check Copilot if configured
  if Config.provider and Config.provider == "copilot" then
    if Utils.has("copilot.lua") or Utils.has("copilot.vim") or Utils.has("copilot") then
      H.ok("Found Copilot plugin")
    else
      H.error("Copilot provider is configured but neither copilot.lua nor copilot.vim is installed")
    end
  end

  -- Check TreeSitter dependencies
  M.check_treesitter()
end

-- Check TreeSitter functionality and parsers
function M.check_treesitter()
  H.start("TreeSitter Dependencies")

  -- Check if TreeSitter is available
  local has_ts, _ = pcall(require, "nvim-treesitter.configs")
  if not has_ts then
    H.error("TreeSitter not available. Make sure nvim-treesitter is properly installed")
    return
  end

  H.ok("TreeSitter core functionality is available")

  -- Check for essential parsers
  local has_parsers, parsers = pcall(require, "nvim-treesitter.parsers")
  if not has_parsers then
    H.error("TreeSitter parsers module not available")
    return
  end

  -- List of important parsers for avante.nvim
  local essential_parsers = {
    "markdown",
  }

  local missing_parsers = {}

  for _, parser in ipairs(essential_parsers) do
    if parsers.has_parser and not parsers.has_parser(parser) then table.insert(missing_parsers, parser) end
  end

  if #missing_parsers == 0 then
    H.ok("All essential TreeSitter parsers are installed")
  else
    H.warn(
      string.format(
        "Missing recommended parsers: %s. Install with :TSInstall %s",
        table.concat(missing_parsers, ", "),
        table.concat(missing_parsers, " ")
      )
    )
  end

  -- Check TreeSitter highlight
  local _, highlighter = pcall(require, "vim.treesitter.highlighter")
  if not highlighter then
    H.warn("TreeSitter highlighter not available. Syntax highlighting might be limited")
  else
    H.ok("TreeSitter highlighter is available")
  end
end

return M
