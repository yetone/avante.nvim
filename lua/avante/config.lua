---NOTE: user will be merged with defaults and
---we add a default var_accessor for this table to config values.
---@class avante.CoreConfig: avante.Config
local M = {}

---@class avante.Config
M.defaults = {
  provider = "claude", -- "claude" or "openai" or "azure"
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
  highlights = {
    diff = {
      current = "DiffText", -- need have background color
      incoming = "DiffAdd", -- need have background color
    },
  },
  mappings = {
    ask = "<leader>aa",
    edit = "<leader>ae",
    diff = {
      ours = "co",
      theirs = "ct",
      none = "c0",
      both = "cb",
      next = "]x",
      prev = "[x",
    },
  },
  windows = {
    width = 30, -- default % based on available width
  },
}

---@type avante.Config
M.options = {}

---@param opts? avante.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
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
