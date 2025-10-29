# Configuration

## Basic Configuration

The minimal configuration for avante.nvim:

```lua
require("avante").setup({
  provider = "claude", -- or "openai", "azure", "copilot", etc.
})
```

## Complete Configuration Example

Here's a comprehensive configuration example with all available options:

```lua
require("avante").setup({
  ---@type "claude" | "openai" | "azure" | "gemini" | "copilot" | string
  provider = "claude",
  
  -- Auto-suggestions configuration
  auto_suggestions_provider = "copilot",
  
  -- Behaviour configuration
  behaviour = {
    auto_suggestions = false, -- Enable auto-suggestions
    auto_set_highlight_group = true,
    auto_set_keymaps = true,
    auto_apply_diff_after_generation = false,
    support_paste_from_clipboard = false,
  },
  
  -- Mappings configuration
  mappings = {
    diff = {
      ours = "co",
      theirs = "ct",
      all_theirs = "ca",
      both = "cb",
      cursor = "cc",
      next = "]x",
      prev = "[x",
    },
    suggestion = {
      accept = "<M-l>",
      next = "<M-]>",
      prev = "<M-[>",
      dismiss = "<C-]>",
    },
    jump = {
      next = "]]",
      prev = "[[",
    },
    submit = {
      normal = "<CR>",
      insert = "<C-s>",
    },
    sidebar = {
      switch_windows = "<Tab>",
      reverse_switch_windows = "<S-Tab>",
    },
  },
  
  -- Hints configuration
  hints = { enabled = true },
  
  -- Windows configuration
  windows = {
    position = "right", -- "right", "left", "top", "bottom"
    wrap = true,
    width = 30, -- % based on available width
    sidebar_header = {
      align = "center", -- "left", "center", "right"
      rounded = true,
    },
  },
  
  -- Highlights configuration
  highlights = {
    diff = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  
  -- Diff configuration
  diff = {
    autojump = true,
    list_opener = "copen",
  },
})
```

## Provider Configuration

### Claude (Anthropic)

```lua
{
  provider = "claude",
  providers = {
    claude = {
      endpoint = "https://api.anthropic.com",
      model = "claude-sonnet-4-20250514",
      timeout = 30000, -- milliseconds
      temperature = 0.75,
      max_tokens = 20480,
      -- API key via environment variable: ANTHROPIC_API_KEY
    },
  },
}
```

### OpenAI

```lua
{
  provider = "openai",
  providers = {
    openai = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4o",
      timeout = 30000,
      temperature = 0.75,
      max_tokens = 4096,
      -- API key via environment variable: OPENAI_API_KEY
    },
  },
}
```

### Azure OpenAI

```lua
{
  provider = "azure",
  providers = {
    azure = {
      endpoint = "https://YOUR_RESOURCE.openai.azure.com",
      deployment = "YOUR_DEPLOYMENT_NAME",
      api_version = "2024-02-15-preview",
      timeout = 30000,
      temperature = 0.75,
      max_tokens = 4096,
      -- API key via environment variable: AZURE_OPENAI_API_KEY
    },
  },
}
```

### GitHub Copilot

```lua
{
  provider = "copilot",
  auto_suggestions_provider = "copilot",
  providers = {
    copilot = {
      model = "gpt-4o-2024-05-13",
      timeout = 30000,
      temperature = 0.75,
      max_tokens = 4096,
    },
  },
}
```

Requires `zbirenbaum/copilot.lua` plugin.

### Google Gemini

```lua
{
  provider = "gemini",
  providers = {
    gemini = {
      endpoint = "https://generativelanguage.googleapis.com/v1beta/models",
      model = "gemini-1.5-flash-latest",
      timeout = 30000,
      temperature = 0.75,
      max_tokens = 4096,
      -- API key via environment variable: GEMINI_API_KEY
    },
  },
}
```

### Cohere

```lua
{
  provider = "cohere",
  providers = {
    cohere = {
      endpoint = "https://api.cohere.ai/v1",
      model = "command-r-plus",
      timeout = 30000,
      temperature = 0.75,
      max_tokens = 4096,
      -- API key via environment variable: COHERE_API_KEY
    },
  },
}
```

## Custom Provider

You can add your own custom AI provider:

```lua
{
  providers = {
    my_custom_provider = {
      endpoint = "https://api.example.com/v1",
      model = "custom-model",
      timeout = 30000,
      temperature = 0.75,
      max_tokens = 4096,
      parse = function(response)
        -- Custom response parsing logic
        return parsed_content
      end,
      -- API key via environment variable: MY_CUSTOM_PROVIDER_API_KEY
    },
  },
}
```

## Environment Variables

Set these environment variables for your chosen provider:

```bash
# Claude
export ANTHROPIC_API_KEY="sk-ant-..."

# OpenAI
export OPENAI_API_KEY="sk-..."

# Azure
export AZURE_OPENAI_API_KEY="..."

# Gemini
export GEMINI_API_KEY="..."

# Cohere
export COHERE_API_KEY="..."

# Custom provider
export MY_CUSTOM_PROVIDER_API_KEY="..."
```

Add to your shell configuration file (`.bashrc`, `.zshrc`, etc.).

## Keybindings

### Default Keybindings

```lua
-- Toggle avante sidebar
vim.keymap.set("n", "<leader>aa", "<cmd>AvanteToggle<cr>")

-- Ask AI about selection
vim.keymap.set("v", "<leader>aa", "<cmd>AvanteAsk<cr>")

-- Refresh suggestions
vim.keymap.set("n", "<leader>ar", "<cmd>AvanteRefresh<cr>")

-- Edit with AI
vim.keymap.set("v", "<leader>ae", "<cmd>AvanteEdit<cr>")
```

### Custom Keybindings

Disable auto keymaps and define your own:

```lua
require("avante").setup({
  behaviour = {
    auto_set_keymaps = false,
  },
})

-- Define custom keymaps
vim.keymap.set("n", "<C-a>", "<cmd>AvanteToggle<cr>")
vim.keymap.set("v", "<C-a>", "<cmd>AvanteAsk<cr>")
```

## UI Customization

### Window Position

```lua
{
  windows = {
    position = "right", -- "right", "left", "top", "bottom"
    width = 30, -- percentage
  },
}
```

### Highlights

Customize diff highlights:

```lua
{
  highlights = {
    diff = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
}
```

## Project Instructions File

Configure the default instructions file name:

```lua
{
  instructions_file = "avante.md", -- or ".avante.md", "AI_INSTRUCTIONS.md", etc.
}
```

See [Project Instructions](/project-instructions) for more details.

## Performance Tuning

### Timeout Settings

```lua
{
  providers = {
    claude = {
      timeout = 30000, -- 30 seconds
    },
  },
}
```

### Auto-suggestions

```lua
{
  behaviour = {
    auto_suggestions = false, -- Disable for better performance
  },
  auto_suggestions_provider = "copilot",
}
```

## Troubleshooting Configuration

Check configuration status:

```vim
:checkhealth avante
```

Debug mode:

```lua
{
  debug = true, -- Enable debug logging
}
```

View logs:

```vim
:messages
```

## Advanced Configuration

### Diff Settings

```lua
{
  diff = {
    autojump = true, -- Auto jump to diff
    list_opener = "copen", -- How to open quickfix
  },
}
```

### Hint Settings

```lua
{
  hints = {
    enabled = true,
  },
}
```

## Next Steps

- [Features](/features) - Explore all features
- [Project Instructions](/project-instructions) - Set up project-specific AI behavior
- [Zen Mode](/zen-mode) - Learn about Zen Mode
