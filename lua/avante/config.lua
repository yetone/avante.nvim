---NOTE: user will be merged with defaults and
---we add a default var_accessor for this table to config values.
---
---@class avante.CoreConfig: avante.Config
local M = {}

---@class avante.Config
M.defaults = {
  ---@alias Provider "openai" | "claude" | "azure" | "deepseek" | "groq"
  provider = "claude", -- "claude" or "openai" or "azure" or "deepseek" or "groq"
  openai = {
    endpoint = "https://api.openai.com",
    model = "gpt-4o",
    temperature = 0,
    max_tokens = 4096,
  },
  azure = {
    endpoint = "", -- example: "https://<your-resource-name>.openai.azure.com"
    deployment = "", -- Azure deployment name (e.g., "gpt-4o", "my-gpt-4o-deployment")
    api_version = "2024-06-01",
    temperature = 0,
    max_tokens = 4096,
  },
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20240620",
    temperature = 0,
    max_tokens = 4096,
  },
  deepseek = {
    endpoint = "https://api.deepseek.com",
    model = "deepseek-coder",
    temperature = 0,
    max_tokens = 4096,
  },
  groq = {
    endpoint = "https://api.groq.com",
    model = "llama-3.1-70b-versatile",
    temperature = 0,
    max_tokens = 4096,
  },
  behaviour = {
    auto_apply_diff_after_generation = false, -- Whether to automatically apply diff after LLM response.
  },
  highlights = {
    ---@type AvanteConflictHighlights
    diff = {
      current = "DiffText", -- need have background color
      incoming = "DiffAdd", -- need have background color
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
    wrap = true, -- similar to vim.o.wrap
    width = 30, -- default % based on available width
  },
  --- @class AvanteConflictUserConfig
  diff = {
    debug = false,
    autojump = true,
    ---@type string | fun(): any
    list_opener = "copen",
  },
}

---@type avante.Config
M.options = {}

---@class avante.ConflictConfig: AvanteConflictUserConfig
---@field mappings AvanteConflictMappings
---@field highlights AvanteConflictHighlights
M.diff = {}

---@param opts? avante.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  M.diff = vim.tbl_deep_extend(
    "force",
    {},
    M.options.diff,
    { mappings = M.options.mappings.diff, highlights = M.options.highlights.diff }
  )
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

---@return {width: integer, height: integer, position: integer}
function M.get_renderer_layout_options()
  local width = M.get_window_width()
  local height = vim.o.lines
  local position = vim.o.columns - width
  return { width = width, height = height, position = position }
end

return M
