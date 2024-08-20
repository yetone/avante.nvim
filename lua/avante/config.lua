---NOTE: user will be merged with defaults and
---we add a default var_accessor for this table to config values.
---
---@class avante.CoreConfig: avante.Config
local M = {}

---@class avante.Config
M.defaults = {
  debug = false,
  ---Currently, default supported providers include "claude", "openai", "azure", "deepseek", "groq"
  ---For custom provider, see README.md
  ---@alias Provider "openai" | "claude" | "azure" | "deepseek" | "groq" | string
  provider = "claude",
  ---@type AvanteSupportedProvider
  openai = {
    endpoint = "https://api.openai.com",
    model = "gpt-4o",
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---@type AvanteAzureProvider
  azure = {
    endpoint = "", -- example: "https://<your-resource-name>.openai.azure.com"
    deployment = "", -- Azure deployment name (e.g., "gpt-4o", "my-gpt-4o-deployment")
    api_version = "2024-06-01",
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---@type AvanteSupportedProvider
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20240620",
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---@type AvanteSupportedProvider
  deepseek = {
    endpoint = "https://api.deepseek.com",
    model = "deepseek-coder",
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---@type AvanteSupportedProvider
  groq = {
    endpoint = "https://api.groq.com",
    model = "llama-3.1-70b-versatile",
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---To add support for custom provider, follow the format below
  ---See https://github.com/yetone/avante.nvim/README.md#custom-providers for more details
  ---@type {[string]: AvanteProvider}
  vendors = {},
  ---Specify the behaviour of avante.nvim
  ---1. auto_apply_diff_after_generation: Whether to automatically apply diff after LLM response.
  ---                                     This would simulate similar behaviour to cursor. Default to false.
  behaviour = {
    auto_apply_diff_after_generation = false,
  },
  highlights = {
    ---@type AvanteConflictHighlights
    diff = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  mappings = {
    ask = "<leader>aa",
    edit = "<leader>ae",
    refresh = "<leader>ar",
    --- @class AvanteConflictMappings
    diff = {
      ours = "co",
      theirs = "ct",
      none = "c0",
      both = "cb",
      next = "]x",
      prev = "[x",
    },
    jump = {
      next = "]]",
      prev = "[[",
    },
  },
  windows = {
    wrap_line = true, -- similar to vim.o.wrap
    width = 30, -- default % based on available width
  },
  --- @class AvanteConflictUserConfig
  diff = {
    debug = false,
    autojump = true,
    ---@type string | fun(): any
    list_opener = "copen",
  },
  --- @class AvanteHintsConfig
  hints = {
    enabled = true,
  },
}

---@type avante.Config
M.options = {}

---@class avante.ConflictConfig: AvanteConflictUserConfig
---@field mappings AvanteConflictMappings
---@field highlights AvanteConflictHighlights
M.diff = {}

---@class AvanteHintsConfig
---@field enabled boolean
M.hints = {}

---@param opts? avante.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  M.diff = vim.tbl_deep_extend(
    "force",
    {},
    M.options.diff,
    { mappings = M.options.mappings.diff, highlights = M.options.highlights.diff }
  )
  M.hints = vim.tbl_deep_extend("force", {}, M.options.hints)
end

---@param opts? avante.Config
function M.override(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

M = setmetatable(M, {
  __index = function(_, k)
    if M.options[k] then
      return M.options[k]
    end
  end,
})

function M.get_window_width()
  return math.ceil(vim.o.columns * (M.windows.width / 100))
end

---@return {width: integer, height: integer}
function M.get_sidebar_layout_options()
  local width = M.get_window_width()
  local height = vim.o.lines
  return { width = width, height = height }
end

return M
