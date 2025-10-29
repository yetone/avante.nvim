# Installation

## Prerequisites

- Neovim v0.10+ (required)
- `curl` and `tar` for downloading prebuilt binaries
- `cargo` if you want to build from source

## Using lazy.nvim (Recommended)

```lua
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  version = false, -- Never set this value to "*"! Never!
  build = vim.fn.has("win32") ~= 0
      and "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false"
      or "make",
  opts = {
    -- add any opts here
    provider = "claude",
  },
  dependencies = {
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    --- The below dependencies are optional,
    "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
    "zbirenbaum/copilot.lua", -- for providers='copilot'
    {
      -- support for image pasting
      "HakonHarnes/img-clip.nvim",
      event = "VeryLazy",
      opts = {
        -- recommended settings
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          -- required for Windows users
          use_absolute_path = true,
        },
      },
    },
    {
      -- Make sure to set this up properly if you have lazy=true
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { "markdown", "Avante" },
      },
      ft = { "markdown", "Avante" },
    },
  },
}
```

## Building from Source

If you want to build the binary from source, use:

```lua
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  build = "make BUILD_FROM_SOURCE=true",
  -- rest of your config
}
```

## Using packer.nvim

```lua
use {
  "yetone/avante.nvim",
  run = vim.fn.has("win32") ~= 0
      and "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false"
      or "make",
  config = function()
    require("avante").setup({
      -- your config
    })
  end,
  requires = {
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons",
  }
}
```

## Using vim-plug

```vim
Plug 'stevearc/dressing.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'yetone/avante.nvim', { 'do': has('win32') ? 'powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false' : 'make' }
```

Then add to your init.vim or init.lua:

```lua
lua << EOF
require("avante").setup({
  -- your config
})
EOF
```

## Post-Installation

After installation, you need to configure your AI provider. See the [Configuration](/configuration) page for detailed setup instructions.

### Quick Configuration

For Claude (recommended):

```lua
opts = {
  provider = "claude",
  providers = {
    claude = {
      endpoint = "https://api.anthropic.com",
      model = "claude-sonnet-4-20250514",
      timeout = 30000,
      extra_request_body = {
        temperature = 0.75,
        max_tokens = 20480,
      },
    },
  },
}
```

For OpenAI:

```lua
opts = {
  provider = "openai",
  providers = {
    openai = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4o",
      timeout = 30000,
      extra_request_body = {
        temperature = 0.75,
      },
    },
  },
}
```

## API Keys

You'll need to set up your API keys as environment variables:

```bash
# For Claude
export ANTHROPIC_API_KEY="your-api-key-here"

# For OpenAI
export OPENAI_API_KEY="your-api-key-here"

# For Azure
export AZURE_OPENAI_API_KEY="your-api-key-here"
```

Add these to your `.bashrc`, `.zshrc`, or equivalent shell configuration file.

## Verifying Installation

After installation, restart Neovim and verify that avante.nvim is loaded:

```vim
:Avante
```

This should open the avante.nvim interface. If you encounter any issues, check the [Troubleshooting](#troubleshooting) section below.

## Troubleshooting

### Build Failures

If the build fails, try:

1. Building from source: `make BUILD_FROM_SOURCE=true`
2. Ensure you have `curl` and `tar` installed
3. Check your Neovim version: `:version`

### Missing Dependencies

Make sure all required plugins are installed:

```vim
:checkhealth avante
```

### Windows Users

On Windows, make sure you're running PowerShell with execution policy allowing scripts:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
```

## Next Steps

- [Quick Start Guide](/quickstart) - Learn the basics
- [Configuration](/configuration) - Customize avante.nvim
- [Features](/features) - Explore all features
