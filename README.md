<div align="center" markdown="1">
   <sup>Special thanks to:</sup>
   <br>
   <br>
   <a href="https://www.warp.dev/avantenvim">
      <img alt="Warp sponsorship" width="400" src="https://github.com/user-attachments/assets/0fb088f2-f684-4d17-86d2-07a489229083">
   </a>

### [Warp, the intelligent terminal for developers](https://www.warp.dev/avantenvim)
[Available for MacOS, Linux, & Windows](https://www.warp.dev/avantenvim)<br>

</div>
<hr>

<div align="center">
  <img alt="logo" width="120" src="https://github.com/user-attachments/assets/2e2f2a58-2b28-4d11-afd1-87b65612b2de" />
  <h1>avante.nvim</h1>
</div>

<div align="center">
  <a href="https://neovim.io/" target="_blank">
    <img src="https://img.shields.io/static/v1?style=flat-square&label=Neovim&message=v0.10%2b&logo=neovim&labelColor=282828&logoColor=8faa80&color=414b32" alt="Neovim: v0.10+" />
  </a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/lua.yaml" target="_blank">
    <img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/lua.yaml?style=flat-square&logo=lua&logoColor=c7c7c7&label=Lua+CI&labelColor=1E40AF&color=347D39&event=push" alt="Lua CI status" />
  </a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/rust.yaml" target="_blank">
    <img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/rust.yaml?style=flat-square&logo=rust&logoColor=ffffff&label=Rust+CI&labelColor=BC826A&color=347D39&event=push" alt="Rust CI status" />
  </a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/pre-commit.yaml" target="_blank">
    <img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/pre-commit.yaml?style=flat-square&logo=pre-commit&logoColor=ffffff&label=pre-commit&labelColor=FAAF3F&color=347D39&event=push" alt="pre-commit status" />
  </a>
  <a href="https://discord.gg/QfnEFEdSjz" target="_blank">
    <img src="https://img.shields.io/discord/1302530866362323016?style=flat-square&logo=discord&label=Discord&logoColor=ffffff&labelColor=7376CF&color=268165" alt="Discord" />
  </a>
  <a href="https://dotfyle.com/plugins/yetone/avante.nvim">
    <img src="https://dotfyle.com/plugins/yetone/avante.nvim/shield?style=flat-square" />
  </a>
</div>

**avante.nvim** is a Neovim plugin designed to emulate the behaviour of the [Cursor](https://www.cursor.com) AI IDE. It provides users with AI-driven code suggestions and the ability to apply these recommendations directly to their source files with minimal effort.

[查看中文版](README_zh.md)

> [!NOTE]
>
> 🥰 This project is undergoing rapid iterations, and many exciting features will be added successively. Stay tuned!

<https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53>

<https://github.com/user-attachments/assets/86140bfd-08b4-483d-a887-1b701d9e37dd>

## Sponsorship ❤️

If you like this project, please consider supporting me on Patreon, as it helps me to continue maintaining and improving it:

[Sponsor me](https://patreon.com/yetone)

## Features

- **AI-Powered Code Assistance**: Interact with AI to ask questions about your current code file and receive intelligent suggestions for improvement or modification.
- **One-Click Application**: Quickly apply the AI's suggested changes to your source code with a single command, streamlining the editing process and saving time.

## Installation

For building binary if you wish to build from source, then `cargo` is required. Otherwise `curl` and `tar` will be used to get prebuilt binary from GitHub.

<details open>

  <summary><a href="https://github.com/folke/lazy.nvim">lazy.nvim</a> (recommended)</summary>

```lua
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  version = false, -- Never set this value to "*"! Never!
  opts = {
    -- add any opts here
    -- for example
    provider = "openai",
    openai = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4o", -- your desired model (or use gpt-4o, etc.)
      timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
      temperature = 0,
      max_completion_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
      --reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
    },
  },
  -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
  build = "make",
  -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    --- The below dependencies are optional,
    "echasnovski/mini.pick", -- for file_selector provider mini.pick
    "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
    "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
    "ibhagwan/fzf-lua", -- for file_selector provider fzf
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

</details>

<details>

  <summary>vim-plug</summary>

```vim

" Deps
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'stevearc/dressing.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'MeanderingProgrammer/render-markdown.nvim'

" Optional deps
Plug 'hrsh7th/nvim-cmp'
Plug 'nvim-tree/nvim-web-devicons' "or Plug 'echasnovski/mini.icons'
Plug 'HakonHarnes/img-clip.nvim'
Plug 'zbirenbaum/copilot.lua'

" Yay, pass source=true if you want to build from source
Plug 'yetone/avante.nvim', { 'branch': 'main', 'do': 'make' }
autocmd! User avante.nvim lua << EOF
require('avante').setup()
EOF
```

</details>

<details>

  <summary><a href="https://github.com/echasnovski/mini.deps">mini.deps</a></summary>

```lua
local add, later, now = MiniDeps.add, MiniDeps.later, MiniDeps.now

add({
  source = 'yetone/avante.nvim',
  monitor = 'main',
  depends = {
    'nvim-treesitter/nvim-treesitter',
    'stevearc/dressing.nvim',
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    'echasnovski/mini.icons'
  },
  hooks = { post_checkout = function() vim.cmd('make') end }
})
--- optional
add({ source = 'hrsh7th/nvim-cmp' })
add({ source = 'zbirenbaum/copilot.lua' })
add({ source = 'HakonHarnes/img-clip.nvim' })
add({ source = 'MeanderingProgrammer/render-markdown.nvim' })

later(function() require('render-markdown').setup({...}) end)
later(function()
  require('img-clip').setup({...}) -- config img-clip
  require("copilot").setup({...}) -- setup copilot to your liking
  require("avante").setup({...}) -- config for avante.nvim
end)
```

</details>

<details>

  <summary><a href="https://github.com/wbthomason/packer.nvim">Packer</a></summary>

```vim

  -- Required plugins
  use 'nvim-treesitter/nvim-treesitter'
  use 'stevearc/dressing.nvim'
  use 'nvim-lua/plenary.nvim'
  use 'MunifTanjim/nui.nvim'
  use 'MeanderingProgrammer/render-markdown.nvim'

  -- Optional dependencies
  use 'hrsh7th/nvim-cmp'
  use 'nvim-tree/nvim-web-devicons' -- or use 'echasnovski/mini.icons'
  use 'HakonHarnes/img-clip.nvim'
  use 'zbirenbaum/copilot.lua'

  -- Avante.nvim with build process
  use {
    'yetone/avante.nvim',
    branch = 'main',
    run = 'make',
    config = function()
      require('avante').setup()
    end
  }
```

</details>

<details>

  <summary><a href="https://github.com/nix-community/home-manager">Home Manager</a></summary>

```nix
programs.neovim = {
  plugins = [
    {
      plugin = pkgs.vimPlugins.avante-nvim;
      type = "lua";
      config = ''
              require("avante_lib").load()
              require("avante").setup()
      '' # or builtins.readFile ./plugins/avante.lua;
    }
  ];
};
```

</details>

<details>

  <summary><a href="https://nix-community.github.io/nixvim/plugins/avante/index.html">Nixvim</a></summary>

```nix
  plugins.avante.enable = true;
  plugins.avante.settings = {
    # setup options here
  };
```

</details>

<details>

  <summary>Lua</summary>

```lua
-- deps:
require('cmp').setup ({
  -- use recommended settings from above
})
require('img-clip').setup ({
  -- use recommended settings from above
})
require('copilot').setup ({
  -- use recommended settings from above
})
require('render-markdown').setup ({
  -- use recommended settings from above
})
require('avante').setup ({
  -- Your config here!
})
```

</details>

> [!IMPORTANT]
>
> `avante.nvim` is currently only compatible with Neovim 0.10.1 or later. Please ensure that your Neovim version meets these requirements before proceeding.

> [!NOTE]
>
> When loading the plugin synchronously, we recommend `require`ing it sometime after your colorscheme.

> [!NOTE]
>
> Recommended **Neovim** options:
>
> ```lua
> -- views can only be fully collapsed with the global statusline
> vim.opt.laststatus = 3
> ```

> [!TIP]
>
> Any rendering plugins that support markdown should work with Avante as long as you add the supported filetype `Avante`. See <https://github.com/yetone/avante.nvim/issues/175> and [this comment](https://github.com/yetone/avante.nvim/issues/175#issuecomment-2313749363) for more information.

### Default setup configuration

_See [config.lua#L9](./lua/avante/config.lua) for the full config_

<details>
<summary>Default configuration</summary>

```lua
{
  ---@alias Provider "claude" | "openai" | "azure" | "gemini" | "cohere" | "copilot" | string
  provider = "claude", -- The provider used in Aider mode or in the planning phase of Cursor Planning Mode
  ---@alias Mode "agentic" | "legacy"
  mode = "agentic", -- The default mode for interaction. "agentic" uses tools to automatically generate code, "legacy" uses the old planning method to generate code.
  -- WARNING: Since auto-suggestions are a high-frequency operation and therefore expensive,
  -- currently designating it as `copilot` provider is dangerous because: https://github.com/yetone/avante.nvim/issues/1048
  -- Of course, you can reduce the request frequency by increasing `suggestion.debounce`.
  auto_suggestions_provider = "claude",
  cursor_applying_provider = nil, -- The provider used in the applying phase of Cursor Planning Mode, defaults to nil, when nil uses Config.provider as the provider for the applying phase
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20241022",
    temperature = 0,
    max_tokens = 4096,
  },
  ---Specify the special dual_boost mode
  ---1. enabled: Whether to enable dual_boost mode. Default to false.
  ---2. first_provider: The first provider to generate response. Default to "openai".
  ---3. second_provider: The second provider to generate response. Default to "claude".
  ---4. prompt: The prompt to generate response based on the two reference outputs.
  ---5. timeout: Timeout in milliseconds. Default to 60000.
  ---How it works:
  --- When dual_boost is enabled, avante will generate two responses from the first_provider and second_provider respectively. Then use the response from the first_provider as provider1_output and the response from the second_provider as provider2_output. Finally, avante will generate a response based on the prompt and the two reference outputs, with the default Provider as normal.
  ---Note: This is an experimental feature and may not work as expected.
  dual_boost = {
    enabled = false,
    first_provider = "openai",
    second_provider = "claude",
    prompt = "Based on the two reference outputs below, generate a response that incorporates elements from both but reflects your own judgment and unique perspective. Do not provide any explanation, just give the response directly. Reference Output 1: [{{provider1_output}}], Reference Output 2: [{{provider2_output}}]",
    timeout = 60000, -- Timeout in milliseconds
  },
  behaviour = {
    auto_suggestions = false, -- Experimental stage
    auto_set_highlight_group = true,
    auto_set_keymaps = true,
    auto_apply_diff_after_generation = false,
    support_paste_from_clipboard = false,
    minimize_diff = true, -- Whether to remove unchanged lines when applying a code block
    enable_token_counting = true, -- Whether to enable token counting. Default to true.
  },
  mappings = {
    --- @class AvanteConflictMappings
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
    cancel = {
      normal = { "<C-c>", "<Esc>", "q" },
      insert = { "<C-c>" },
    },
    sidebar = {
      apply_all = "A",
      apply_cursor = "a",
      retry_user_request = "r",
      edit_user_request = "e",
      switch_windows = "<Tab>",
      reverse_switch_windows = "<S-Tab>",
      remove_file = "d",
      add_file = "@",
      close = { "<Esc>", "q" },
      close_from_input = nil, -- e.g., { normal = "<Esc>", insert = "<C-d>" }
    },
  },
  hints = { enabled = true },
  windows = {
    ---@type "right" | "left" | "top" | "bottom"
    position = "right", -- the position of the sidebar
    wrap = true, -- similar to vim.o.wrap
    width = 30, -- default % based on available width
    sidebar_header = {
      enabled = true, -- true, false to enable/disable the header
      align = "center", -- left, center, right for title
      rounded = true,
    },
    input = {
      prefix = "> ",
      height = 8, -- Height of the input window in vertical layout
    },
    edit = {
      border = "rounded",
      start_insert = true, -- Start insert mode when opening the edit window
    },
    ask = {
      floating = false, -- Open the 'AvanteAsk' prompt in a floating window
      start_insert = true, -- Start insert mode when opening the ask window
      border = "rounded",
      ---@type "ours" | "theirs"
      focus_on_apply = "ours", -- which diff to focus after applying
    },
  },
  highlights = {
    ---@type AvanteConflictHighlights
    diff = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  --- @class AvanteConflictUserConfig
  diff = {
    autojump = true,
    ---@type string | fun(): any
    list_opener = "copen",
    --- Override the 'timeoutlen' setting while hovering over a diff (see :help timeoutlen).
    --- Helps to avoid entering operator-pending mode with diff mappings starting with `c`.
    --- Disable by setting to -1.
    override_timeoutlen = 500,
  },
  suggestion = {
    debounce = 600,
    throttle = 600,
  },
}
```

</details>

## Blink.cmp users

For blink cmp users (nvim-cmp alternative) view below instruction for configuration
This is achieved by emulating nvim-cmp using blink.compat
or you can use [Kaiser-Yang/blink-cmp-avante](https://github.com/Kaiser-Yang/blink-cmp-avante).

<details>
  <summary>Lua</summary>

```lua
      selector = {
        --- @alias avante.SelectorProvider "native" | "fzf_lua" | "mini_pick" | "snacks" | "telescope" | fun(selector: avante.ui.Selector): nil
        provider = "fzf",
        -- Options override for custom providers
        provider_opts = {},
      }
```

To create a customized selector provider, you can specify a customized function to launch a picker to select items and pass the selected items to the `on_select` callback.

```lua
      selector = {
        ---@param selector avante.ui.Selector
        provider = function(selector)
          local items = selector.items ---@type avante.ui.SelectorItem[]
          local title = selector.title ---@type string
          local on_select = selector.on_select ---@type fun(selected_item_ids: string[]|nil): nil

          --- your customized picker logic here
        end,
      }
```

Choose a selector other that native, the default as that currently has an issue
For lazyvim users copy the full config for blink.cmp from the website or extend the options

```lua
      compat = {
        "avante_commands",
        "avante_mentions",
        "avante_files",
      }
```

For other users just add a custom provider

```lua
      default = {
        ...
        "avante_commands",
        "avante_mentions",
        "avante_files",
      }
```

```lua
      providers = {
        avante_commands = {
          name = "avante_commands",
          module = "blink.compat.source",
          score_offset = 90, -- show at a higher priority than lsp
          opts = {},
        },
        avante_files = {
          name = "avante_files",
          module = "blink.compat.source",
          score_offset = 100, -- show at a higher priority than lsp
          opts = {},
        },
        avante_mentions = {
          name = "avante_mentions",
          module = "blink.compat.source",
          score_offset = 1000, -- show at a higher priority than lsp
          opts = {},
        }
        ...
    }
```

</details>

## Usage

Given its early stage, `avante.nvim` currently supports the following basic functionalities:

> [!IMPORTANT]
>
> Avante will only support Claude, and OpenAI (and its variants including azure)out-of-the-box due to its high code quality generation.
> For all OpenAI-compatible providers, see [wiki](https://github.com/yetone/avante.nvim/wiki/Custom-providers) for more details.

> [!IMPORTANT]
>
> ~~Due to the poor performance of other models, avante.nvim only recommends using the claude-3.5-sonnet model.~~ > ~~All features can only be guaranteed to work properly on the claude-3.5-sonnet model.~~ > ~~We do not accept changes to the code or prompts to accommodate other models. Otherwise, it will greatly increase our maintenance costs.~~ > ~~We hope everyone can understand. Thank you!~~

> [!IMPORTANT]
>
> Since avante.nvim now supports [cursor planning mode](./cursor-planning-mode.md), the above statement is no longer valid! avante.nvim now supports most models! If you encounter issues with normal usage, please try enabling [cursor planning mode](./cursor-planning-mode.md).

> [!IMPORTANT]
>
> For most consistency between neovim session, it is recommended to set the environment variables in your shell file.
> By default, `Avante` will prompt you at startup to input the API key for the provider you have selected.
>
> For Claude:
>
> ```sh
> export ANTHROPIC_API_KEY=your-api-key
> ```
>
> For OpenAI:
>
> ```sh
> export OPENAI_API_KEY=your-api-key
> ```
>
> For Azure OpenAI:
>
> ```sh
> export AZURE_OPENAI_API_KEY=your-api-key
> ```
>
> For Amazon Bedrock:
>
> ```sh
> export BEDROCK_KEYS=aws_access_key_id,aws_secret_access_key,aws_region[,aws_session_token]
>
> ```
>
> Note: The aws_session_token is optional and only needed when using temporary AWS credentials

1. Open a code file in Neovim.
2. Use the `:AvanteAsk` command to query the AI about the code.
3. Review the AI's suggestions.
4. Apply the recommended changes directly to your code with a simple command or key binding.

**Note**: The plugin is still under active development, and both its functionality and interface are subject to significant changes. Expect some rough edges and instability as the project evolves.

## Key Bindings

The following key bindings are available for use with `avante.nvim`:

| Key Binding                               | Description                                  |
| ----------------------------------------- | -------------------------------------------- |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>a</kbd> | show sidebar                                 |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>t</kbd> | toggle sidebar visibility                    |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>r</kbd> | refresh sidebar                              |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>f</kbd> | switch sidebar focus                         |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>?</kbd> | select model                                 |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>e</kbd> | edit selected blocks                         |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>S</kbd> | stop current AI request                      |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>h</kbd> | select between chat histories                |
| <kbd>c</kbd><kbd>o</kbd>                  | choose ours                                  |
| <kbd>c</kbd><kbd>t</kbd>                  | choose theirs                                |
| <kbd>c</kbd><kbd>a</kbd>                  | choose all theirs                            |
| <kbd>c</kbd><kbd>0</kbd>                  | choose none                                  |
| <kbd>c</kbd><kbd>b</kbd>                  | choose both                                  |
| <kbd>c</kbd><kbd>c</kbd>                  | choose cursor                                |
| <kbd>]</kbd><kbd>x</kbd>                  | move to previous conflict                    |
| <kbd>[</kbd><kbd>x</kbd>                  | move to next conflict                        |
| <kbd>[</kbd><kbd>[</kbd>                  | jump to previous codeblocks (results window) |
| <kbd>]</kbd><kbd>]</kbd>                  | jump to next codeblocks (results windows)    |

> [!NOTE]
>
> If you are using `lazy.nvim`, then all keymap here will be safely set, meaning if `<leader>aa` is already binded, then avante.nvim won't bind this mapping.
> In this case, user will be responsible for setting up their own. See [notes on keymaps](https://github.com/yetone/avante.nvim/wiki#keymaps-and-api-i-guess) for more details.

### Neotree shortcut

In the neotree sidebar, you can also add a new keyboard shortcut to quickly add `file/folder` to `Avante Selected Files`.

<details>
<summary>Neotree configuration</summary>

```lua
return {
  {
    'nvim-neo-tree/neo-tree.nvim',
    config = function()
      require('neo-tree').setup({
        filesystem = {
          commands = {
            avante_add_files = function(state)
              local node = state.tree:get_node()
              local filepath = node:get_id()
              local relative_path = require('avante.utils').relative_path(filepath)

              local sidebar = require('avante').get()

              local open = sidebar:is_open()
              -- ensure avante sidebar is open
              if not open then
                require('avante.api').ask()
                sidebar = require('avante').get()
              end

              sidebar.file_selector:add_selected_file(relative_path)

              -- remove neo tree buffer
              if not open then
                sidebar.file_selector:remove_selected_file('neo-tree filesystem [1]')
              end
            end,
          },
          window = {
            mappings = {
              ['oa'] = 'avante_add_files',
            },
          },
        },
      })
    end,
  },
}
```

</details>

## Commands

| Command                            | Description                                                                                                 | Examples                                            |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `:AvanteAsk [question] [position]` | Ask AI about your code. Optional `position` set window position and `ask` enable/disable direct asking mode | `:AvanteAsk position=right Refactor this code here` |
| `:AvanteBuild`                     | Build dependencies for the project                                                                          |                                                     |
| `:AvanteChat`                      | Start a chat session with AI about your codebase. Default is `ask`=false                                    |                                                     |
| `:AvanteChatNew`                   | Start a new chat session. The current chat can be re-opened with the chat session selector                  |                                                     |
| `:AvanteHistory`                   | Opens a picker for your previous chat sessions                                                              |                                                     |
| `:AvanteClear`                     | Clear the chat history for your current chat session                                                        |                                                     |
| `:AvanteEdit`                      | Edit the selected code blocks                                                                               |                                                     |
| `:AvanteFocus`                     | Switch focus to/from the sidebar                                                                            |                                                     |
| `:AvanteRefresh`                   | Refresh all Avante windows                                                                                  |                                                     |
| `:AvanteStop`                      | Stop the current AI request                                                                                 |                                                     |
| `:AvanteSwitchProvider`            | Switch AI provider (e.g. openai)                                                                            |                                                     |
| `:AvanteShowRepoMap`               | Show repo map for project's structure                                                                       |                                                     |
| `:AvanteToggle`                    | Toggle the Avante sidebar                                                                                   |                                                     |
| `:AvanteModels`                    | Show model list                                                                                             |                                                     |
| `:AvanteSwitchSelectorProvider`    | Switch avante selector provider (e.g. native, telescope, fzf_lua, mini_pick, snacks)                        |                                                     |

## Highlight Groups

| Highlight Group             | Description                                   | Notes                                        |
| --------------------------- | --------------------------------------------- | -------------------------------------------- |
| AvanteTitle                 | Title                                         |                                              |
| AvanteReversedTitle         | Used for rounded border                       |                                              |
| AvanteSubtitle              | Selected code title                           |                                              |
| AvanteReversedSubtitle      | Used for rounded border                       |                                              |
| AvanteThirdTitle            | Prompt title                                  |                                              |
| AvanteReversedThirdTitle    | Used for rounded border                       |                                              |
| AvanteConflictCurrent       | Current conflict highlight                    | Default to `Config.highlights.diff.current`  |
| AvanteConflictIncoming      | Incoming conflict highlight                   | Default to `Config.highlights.diff.incoming` |
| AvanteConflictCurrentLabel  | Current conflict label highlight              | Default to shade of `AvanteConflictCurrent`  |
| AvanteConflictIncomingLabel | Incoming conflict label highlight             | Default to shade of `AvanteConflictIncoming` |
| AvantePopupHint             | Usage hints in popup menus                    |                                              |
| AvanteInlineHint            | The end-of-line hint displayed in visual mode |                                              |
| AvantePromptInput           | The body highlight of the prompt input        |                                              |
| AvantePromptInputBorder     | The border highlight of the prompt input      | Default to `NormalFloat`                     |

See [highlights.lua](./lua/avante/highlights.lua) for more information

## Ollama

ollama is a first-class provider for avante.nvim. You can use it by setting `provider = "ollama"` in the configuration, and set the `model` field in `ollama` to the model you want to use. For example:

```lua
provider = "ollama",
ollama = {
  model = "qwq:32b",
}
```

> [!NOTE]
> If you use ollama, the code planning effect may not be ideal, so it is strongly recommended that you enable [cursor-planning-mode](https://github.com/yetone/avante.nvim/blob/main/cursor-planning-mode.md)

## AiHubMix

[AiHubMix](https://s.kiiro.ai/r/PPELHy) is a built-in provider for avante.nvim. You can register an account on the [AiHubMix official website](https://s.kiiro.ai/r/PPELHy), then create an API Key within the website, and set this API Key in your environment variables:

```bash
export AIHUBMIX_API_KEY=your_api_key
```

Then in your configuration, set `provider = "aihubmix"`, and set the `model` field to the model name you want to use, for example:

```lua
provider = "aihubmix",
aihubmix = {
  model = "gpt-4o-2024-11-20",
}
```

## Custom providers

Avante provides a set of default providers, but users can also create their own providers.

For more information, see [Custom Providers](https://github.com/yetone/avante.nvim/wiki/Custom-providers)

## RAG Service

Avante provides a RAG service, which is a tool for obtaining the required context for the AI to generate the codes. By default, it is not enabled. You can enable it this way:

```lua
rag_service = {
  enabled = false, -- Enables the RAG service
  host_mount = os.getenv("HOME"), -- Host mount path for the rag service
  provider = "openai", -- The provider to use for RAG service (e.g. openai or ollama)
  llm_model = "", -- The LLM model to use for RAG service
  embed_model = "", -- The embedding model to use for RAG service
  endpoint = "https://api.openai.com/v1", -- The API endpoint for RAG service
},
```

If your rag_service provider is `openai`, then you need to set the `OPENAI_API_KEY` environment variable!

If your rag_service provider is `ollama`, you need to set the endpoint to `http://localhost:11434` (note there is no `/v1` at the end) or any address of your own ollama server.

If your rag_service provider is `ollama`, when `llm_model` is empty, it defaults to `llama3`, and when `embed_model` is empty, it defaults to `nomic-embed-text`. Please make sure these models are available in your ollama server.

Additionally, RAG Service also depends on Docker! (For macOS users, OrbStack is recommended as a Docker alternative).

`host_mount` is the path that will be mounted to the container, and the default is the home directory. The mount is required
for the RAG service to access the files in the host machine. It is up to the user to decide if you want to mount the whole
`/` directory, just the project directory, or the home directory. If you plan using avante and RAG event for projects
stored outside your home directory, you will need to set the `host_mount` to the root directory of your file system.

The mount will be read only.

After changing the rag_service configuration, you need to manually delete the rag_service container to ensure the new configuration is used: `docker rm -fv avante-rag-service`

## Web Search Engines

Avante's tools include some web search engines, currently support:

- [Tavily](https://tavily.com/)
- [SerpApi](https://serpapi.com/)
- [SearchAPI](https://www.searchapi.io/)
- Google's [Programmable Search Engine](https://developers.google.com/custom-search/v1/overview)
- [Kagi](https://help.kagi.com/kagi/api/search.html)
- [Brave Search](https://api-dashboard.search.brave.com/app/documentation/web-search/get-started)
- [SearXNG](https://searxng.github.io/searxng/)

The default is Tavily, and can be changed through configuring `Config.web_search_engine.provider`:

```lua
web_search_engine = {
  provider = "tavily", -- tavily, serpapi, searchapi, google, kagi, brave, or searxng
  proxy = nil, -- proxy support, e.g., http://127.0.0.1:7890
}
```

Environment variables required for providers:

- Tavily: `TAVILY_API_KEY`
- SerpApi: `SERPAPI_API_KEY`
- SearchAPI: `SEARCHAPI_API_KEY`
- Google:
  - `GOOGLE_SEARCH_API_KEY` as the [API key](https://developers.google.com/custom-search/v1/overview)
  - `GOOGLE_SEARCH_ENGINE_ID` as the [search engine](https://programmablesearchengine.google.com) ID
- Kagi: `KAGI_API_KEY` as the [API Token](https://kagi.com/settings?p=api)
- Brave Search: `BRAVE_API_KEY` as the [API key](https://api-dashboard.search.brave.com/app/keys)
- SearXNG: `SEARXNG_API_URL` as the [API URL](https://docs.searxng.org/dev/search_api.html)

## Disable Tools

Avante enables tools by default, but some LLM models do not support tools. You can disable tools by setting `disable_tools = true` for the provider. For example:

```lua
{
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20241022",
    timeout = 30000, -- Timeout in milliseconds
    temperature = 0,
    max_tokens = 4096,
    disable_tools = true, -- disable tools!
  },
}
```

In case you want to ban some tools to avoid its usage (like Claude 3.7 overusing the python tool) you can disable just specific tools

```lua
{
  disabled_tools = { "python" },
}
```

Tool list

> rag_search, python, git_diff, git_commit, list_files, search_files, search_keyword, read_file_toplevel_symbols,
> read_file, create_file, rename_file, delete_file, create_dir, rename_dir, delete_dir, bash, web_search, fetch

## Custom Tools

Avante allows you to define custom tools that can be used by the AI during code generation and analysis. These tools can execute shell commands, run scripts, or perform any custom logic you need.

### Example: Go Test Runner

<details>
<summary>Here's an example of a custom tool that runs Go unit tests:</summary>

```lua
{
  custom_tools = {
    {
      name = "run_go_tests",  -- Unique name for the tool
      description = "Run Go unit tests and return results",  -- Description shown to AI
      command = "go test -v ./...",  -- Shell command to execute
      param = {  -- Input parameters (optional)
        type = "table",
        fields = {
          {
            name = "target",
            description = "Package or directory to test (e.g. './pkg/...' or './internal/pkg')",
            type = "string",
            optional = true,
          },
        },
      },
      returns = {  -- Expected return values
        {
          name = "result",
          description = "Result of the fetch",
          type = "string",
        },
        {
          name = "error",
          description = "Error message if the fetch was not successful",
          type = "string",
          optional = true,
        },
      },
      func = function(params, on_log, on_complete)  -- Custom function to execute
        local target = params.target or "./..."
        return vim.fn.system(string.format("go test -v %s", target))
      end,
    },
  },
}
```

</details>

## MCP

Now you can integrate MCP functionality for Avante through `mcphub.nvim`. For detailed documentation, please refer to [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim#avante-integration)

## Custom prompts

By default, `avante.nvim` provides three different modes to interact with: `planning`, `editing`, and `suggesting`, followed with three different prompts per mode.

- `planning`: Used with `require("avante").toggle()` on sidebar
- `editing`: Used with `require("avante").edit()` on selection codeblock
- `suggesting`: Used with `require("avante").get_suggestion():suggest()` on Tab flow.
- `cursor-planning`: Used with `require("avante").toggle()` on Tab flow, but only when cursor planning mode is enabled.

Users can customize the system prompts via `Config.system_prompt`. We recommend calling this in a custom Autocmds depending on your need:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ToggleMyPrompt",
  callback = function() require("avante.config").override({system_prompt = "MY CUSTOM SYSTEM PROMPT"}) end,
})

vim.keymap.set("n", "<leader>am", function() vim.api.nvim_exec_autocmds("User", { pattern = "ToggleMyPrompt" }) end, { desc = "avante: toggle my prompt" })
```

If one wish to custom prompts for each mode, `avante.nvim` will check for project root based on the given buffer whether it contains
the following patterns: `*.{mode}.avanterules`.

The rules for root hierarchy:

- lsp workspace folders
- lsp root_dir
- root pattern of filename of the current buffer
- root pattern of cwd

<details>

  <summary>Example folder structure for custom prompt</summary>

If you have the following structure:

```bash
.
├── .git/
├── typescript.planning.avanterules
├── snippets.editing.avanterules
├── suggesting.avanterules
└── src/

```

- `typescript.planning.avanterules` will be used for `planning` mode
- `snippets.editing.avanterules` will be used for `editing` mode
- `suggesting.avanterules` will be used for `suggesting` mode.

</details>

> [!important]
>
> `*.avanterules` is a jinja template file, in which will be rendered using [minijinja](https://github.com/mitsuhiko/minijinja). See [templates](https://github.com/yetone/avante.nvim/blob/main/lua/avante/templates) for example on how to extend current templates.

## TODOs

- [x] Chat with current file
- [x] Apply diff patch
- [x] Chat with the selected block
- [x] Slash commands
- [x] Edit the selected block
- [x] Smart Tab (Cursor Flow)
- [x] Chat with project (You can use `@codebase` to chat with the whole project)
- [x] Chat with selected files
- [x] Tool use
- [x] MCP
- [ ] Better codebase indexing

## Roadmap

- **Enhanced AI Interactions**: Improve the depth of AI analysis and recommendations for more complex coding scenarios.
- **LSP + Tree-sitter + LLM Integration**: Integrate with LSP and Tree-sitter and LLM to provide more accurate and powerful code suggestions and analysis.

## Contributing

Contributions to avante.nvim are welcome! If you're interested in helping out, please feel free to submit pull requests or open issues. Before contributing, ensure that your code has been thoroughly tested.

See [wiki](https://github.com/yetone/avante.nvim/wiki) for more recipes and tricks.

## Acknowledgments

We would like to express our heartfelt gratitude to the contributors of the following open-source projects, whose code has provided invaluable inspiration and reference for the development of avante.nvim:

| Nvim Plugin                                                           | License            | Functionality                 | Location                                                                                                                               |
| --------------------------------------------------------------------- | ------------------ | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| [git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim)     | No License         | Diff comparison functionality | [lua/avante/diff.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/diff.lua)                                             |
| [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim)              | Apache 2.0 License | Calculation of tokens count   | [lua/avante/utils/tokens.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/utils/tokens.lua)                             |
| [img-clip.nvim](https://github.com/HakonHarnes/img-clip.nvim)         | MIT License        | Clipboard image support       | [lua/avante/clipboard.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/clipboard.lua)                                   |
| [copilot.lua](https://github.com/zbirenbaum/copilot.lua)              | MIT License        | Copilot support               | [lua/avante/providers/copilot.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/copilot.lua)                   |
| [jinja.vim](https://github.com/HiPhish/jinja.vim)                     | MIT License        | Template filetype support     | [syntax/jinja.vim](https://github.com/yetone/avante.nvim/blob/main/syntax/jinja.vim)                                                   |
| [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) | MIT License        | Secrets logic support         | [lua/avante/providers/init.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/init.lua)                         |
| [aider](https://github.com/paul-gauthier/aider)                       | Apache 2.0 License | Planning mode user prompt     | [lua/avante/templates/planning.avanterules](https://github.com/yetone/avante.nvim/blob/main/lua/avante/templates/planning.avanterules) |

The high quality and ingenuity of these projects' source code have been immensely beneficial throughout our development process. We extend our sincere thanks and respect to the authors and contributors of these projects. It is the selfless dedication of the open-source community that drives projects like avante.nvim forward.

## Business Sponsors

<table>
  <tr>
    <td align="center">
      <a href="https://s.kiiro.ai/r/ylVbT6" target="_blank">
        <img height="80" src="https://github.com/user-attachments/assets/1abd8ede-bd98-4e6e-8ee0-5a661b40344a" alt="Meshy AI" /><br/>
        <strong>Meshy AI</strong>
        <div>&nbsp;</div>
        <div>The #1 AI 3D Model Generator for Creators</div>
      </a>
    </td>
    <td align="center">
      <a href="https://s.kiiro.ai/r/mGPJOd" target="_blank">
        <img height="80" src="https://github.com/user-attachments/assets/7b7bd75e-1fd2-48cc-a71a-cff206e4fbd7" alt="BabelTower API" /><br/>
        <strong>BabelTower API</strong>
        <div>&nbsp;</div>
        <div>No account needed, use any model instantly</div>
      </a>
    </td>
  </tr>
</table>

## License

avante.nvim is licensed under the Apache 2.0 License. For more details, please refer to the [LICENSE](./LICENSE) file.

# Star History

<p align="center">
  <a target="_blank" href="https://star-history.com/#yetone/avante.nvim&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=yetone/avante.nvim&type=Date&theme=dark">
      <img alt="NebulaGraph Data Intelligence Suite(ngdi)" src="https://api.star-history.com/svg?repos=yetone/avante.nvim&type=Date">
    </picture>
  </a>
</p>
