local M = {}

local config = {
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
    show_sidebar = "<leader>aa",
    diff = {
      ours = "co",
      theirs = "ct",
      none = "c0",
      both = "cb",
      next = "]x",
      prev = "[x",
    },
  },
}

function M.update(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.get()
  return config
end

return M
