---NOTE: user will be merged with defaults and
---we add a default var_accessor for this table to config values.

local Utils = require("avante.utils")

---@class avante.CoreConfig: avante.Config
local M = {}

---@class avante.Config
---@field silent_warning boolean will be determined from debug
M.defaults = {
  debug = false,
  ---@alias Provider "claude" | "openai" | "azure" | "gemini" | "cohere" | "copilot" | string
  provider = "claude", -- Only recommend using Claude
  ---@type AvanteSupportedProvider
  openai = {
    endpoint = "https://api.openai.com/v1",
    model = "gpt-4o",
    timeout = 30000, -- Timeout in milliseconds
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---@type AvanteSupportedProvider
  copilot = {
    endpoint = "https://api.githubcopilot.com",
    model = "gpt-4o-2024-05-13",
    proxy = nil, -- [protocol://]host[:port] Use this proxy
    allow_insecure = false, -- Allow insecure server connections
    timeout = 30000, -- Timeout in milliseconds
    temperature = 0,
    max_tokens = 4096,
  },
  ---@type AvanteAzureProvider
  azure = {
    endpoint = "", -- example: "https://<your-resource-name>.openai.azure.com"
    deployment = "", -- Azure deployment name (e.g., "gpt-4o", "my-gpt-4o-deployment")
    api_version = "2024-06-01",
    timeout = 30000, -- Timeout in milliseconds
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---@type AvanteSupportedProvider
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20240620",
    timeout = 30000, -- Timeout in milliseconds
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---@type AvanteSupportedProvider
  gemini = {
    endpoint = "https://generativelanguage.googleapis.com/v1beta/models",
    model = "gemini-1.5-flash-latest",
    timeout = 30000, -- Timeout in milliseconds
    temperature = 0,
    max_tokens = 4096,
    ["local"] = false,
  },
  ---@type AvanteSupportedProvider
  cohere = {
    endpoint = "https://api.cohere.com/v1",
    model = "command-r-plus",
    timeout = 30000, -- Timeout in milliseconds
    temperature = 0,
    max_tokens = 3072,
    ["local"] = false,
  },
  ---To add support for custom provider, follow the format below
  ---See https://github.com/yetone/avante.nvim/README.md#custom-providers for more details
  ---@type {[string]: AvanteProvider}
  vendors = {},
  ---Specify the behaviour of avante.nvim
  ---1. auto_apply_diff_after_generation: Whether to automatically apply diff after LLM response.
  ---                                     This would simulate similar behaviour to cursor. Default to false.
  ---2. auto_set_keymaps                : Whether to automatically set the keymap for the current line. Default to true.
  ---                                     Note that avante will safely set these keymap. See https://github.com/yetone/avante.nvim/wiki#keymaps-and-api-i-guess for more details.
  ---3. auto_set_highlight_group        : Whether to automatically set the highlight group for the current line. Default to true.
  ---4. support_paste_from_clipboard    : Whether to support pasting image from clipboard. This will be determined automatically based whether img-clip is available or not.
  behaviour = {
    auto_set_highlight_group = true,
    auto_set_keymaps = true,
    auto_apply_diff_after_generation = false,
    support_paste_from_clipboard = false,
  },
  history = {
    storage_path = vim.fn.stdpath("state") .. "/avante",
    paste = {
      extension = "png",
      filename = "pasted-%Y-%m-%d-%H-%M-%S",
    },
  },
  highlights = {
    ---@type AvanteConflictHighlights
    diff = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  mappings = {
    ---@class AvanteConflictMappings
    diff = {
      ours = "co",
      theirs = "ct",
      all_theirs = "ca",
      none = "c0",
      both = "cb",
      cursor = "cc",
      next = "]x",
      prev = "[x",
    },
    jump = {
      next = "]]",
      prev = "[[",
    },
    submit = {
      normal = "<CR>",
      insert = "<C-s>",
    },
    -- NOTE: The following will be safely set by avante.nvim
    ask = "<leader>aa",
    edit = "<leader>ae",
    refresh = "<leader>ar",
    toggle = {
      debug = "<leader>ad",
      hint = "<leader>ah",
    },
  },
  windows = {
    wrap = true, -- similar to vim.o.wrap
    width = 30, -- default % based on available width
    sidebar_header = {
      align = "center", -- left, center, right for title
      rounded = true,
    },
    input = {
      prefix = "> ",
    },
    edit = {
      border = "rounded",
    },
  },
  --- @class AvanteConflictUserConfig
  diff = {
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
  M.options = vim.tbl_deep_extend(
    "force",
    M.defaults,
    opts or {},
    ---@type avante.Config
    {
      behaviour = {
        support_paste_from_clipboard = M.support_paste_image(),
      },
    }
  )
  if not M.options.silent_warning then
    -- set silent_warning to true if debug is false
    M.options.silent_warning = not M.options.debug
  end

  M.diff = vim.tbl_deep_extend(
    "force",
    {},
    M.options.diff,
    { mappings = M.options.mappings.diff, highlights = M.options.highlights.diff }
  )
  M.hints = vim.tbl_deep_extend("force", {}, M.options.hints)

  if next(M.options.vendors) ~= nil then
    for k, v in pairs(M.options.vendors) do
      M.options.vendors[k] = type(v) == "function" and v() or v
    end
  end
end

---@param opts? avante.Config
function M.override(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", M.options, opts)
  if not M.options.silent_warning then
    -- set silent_warning to true if debug is false
    M.options.silent_warning = not M.options.debug
  end

  M.diff = vim.tbl_deep_extend(
    "force",
    {},
    M.options.diff,
    { mappings = M.options.mappings.diff, highlights = M.options.highlights.diff }
  )
  M.hints = vim.tbl_deep_extend("force", {}, M.options.hints)

  if next(M.options.vendors) ~= nil then
    for k, v in pairs(M.options.vendors) do
      M.options.vendors[k] = type(v) == "function" and v() or v
    end
  end
end

M = setmetatable(M, {
  __index = function(_, k)
    if M.options[k] then
      return M.options[k]
    end
  end,
})

M.support_paste_image = function()
  local supported = Utils.has("img-clip.nvim") or Utils.has("img-clip")
  if not supported and not M.options.silent_warning then
    Utils.warn("img-clip.nvim is not installed. Pasting image will be disabled.", { once = true })
  end
  return supported
end

M.get_window_width = function()
  return math.ceil(vim.o.columns * (M.windows.width / 100))
end

---@param provider Provider
---@return boolean
M.has_provider = function(provider)
  return M.options[provider] ~= nil or M.vendors[provider] ~= nil
end

---get supported providers
---@param provider Provider
---@return AvanteProviderFunctor
M.get_provider = function(provider)
  if M.options[provider] ~= nil then
    return vim.deepcopy(M.options[provider], true)
  elseif M.vendors[provider] ~= nil then
    return vim.deepcopy(M.vendors[provider], true)
  else
    error("Failed to find provider: " .. provider, 2)
  end
end

M.BASE_PROVIDER_KEYS = {
  "endpoint",
  "model",
  "deployment",
  "api_version",
  "proxy",
  "allow_insecure",
  "api_key_name",
  "timeout",
  -- internal
  "local",
  "_shellenv",
}

---@return {width: integer, height: integer}
M.get_sidebar_layout_options = function()
  local width = M.get_window_width()
  local height = vim.o.lines
  return { width = width, height = height }
end

return M
