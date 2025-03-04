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
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/python.yaml" target="_blank">
    <img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/python.yaml?style=flat-square&logo=python&logoColor=ffffff&label=Python+CI&labelColor=3672A5&color=347D39&event=push" alt="Python CI status" />
  </a>
  <a href="https://discord.com/invite/wUuZz7VxXD" target="_blank">
    <img src="https://img.shields.io/discord/1302530866362323016?style=flat-square&logo=discord&label=Discord&logoColor=ffffff&labelColor=7376CF&color=268165" alt="Discord" />
  </a>
  <a href="https://dotfyle.com/plugins/yetone/avante.nvim">
    <img src="https://dotfyle.com/plugins/yetone/avante.nvim/shield?style=flat-square" />
  </a>
</div>

**avante.nvim** is a Neovim plugin designed to emulate the behaviour of the [Cursor](https://www.cursor.com) AI IDE. It provides users with AI-driven code suggestions and the ability to apply these recommendations directly to their source files with minimal effort.

> [!NOTE]
>
> 🥰 This project is undergoing rapid iterations, and many exciting features will be added successively. Stay tuned!

<https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53>

<https://github.com/user-attachments/assets/86140bfd-08b4-483d-a887-1b701d9e37dd>

## Sponsorship

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
  lazy = false,
  version = false, -- Set this to "*" to always pull the latest release version, or set it to false to update to the latest code changes.
  opts = {
    -- add any opts here
    -- for example
    provider = "openai",
    openai = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4o", -- your desired model (or use gpt-4o, etc.)
      timeout = 30000, -- timeout in milliseconds
      temperature = 0, -- adjust if needed
      max_tokens = 4096,
      -- reasoning_effort = "high" -- only supported for reasoning models (o1, etc.)
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
      config = ''require("avante").setup()'' # or builtins.readFile ./plugins/avante.lua;
    }
  ];
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

```lua
{
  ---@alias Provider "claude" | "openai" | "azure" | "gemini" | "cohere" | "copilot" | string
  provider = "claude", -- The provider used in Aider mode or in the planning phase of Cursor Planning Mode
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
    enable_cursor_planning_mode = false, -- Whether to enable Cursor Planning Mode. Default to false.
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
    sidebar = {
      apply_all = "A",
      apply_cursor = "a",
      switch_windows = "<Tab>",
      reverse_switch_windows = "<S-Tab>",
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

## Blink.cmp users

For blink cmp users (nvim-cmp alternative) view below instruction for configuration
This is achieved by emulating nvim-cmp using blink.compat
or you can use [Kaiser-Yang/blink-cmp-avante](https://github.com/Kaiser-Yang/blink-cmp-avante).
<details>
  <summary>Lua</summary>

```lua
      file_selector = {
        --- @alias FileSelectorProvider "native" | "fzf" | "mini.pick" | "snacks" | "telescope" | string | fun(params: avante.file_selector.IParams|nil): nil
        provider = "fzf",
        -- Options override for custom providers
        provider_opts = {},
      }
```

To create a customized file_selector, you can specify a customized function to launch a picker to select items and pass the selected items to the `handler` callback.

```lua
      file_selector = {
        ---@param params avante.file_selector.IParams
        provider = function(params)
          local filepaths = params.filepaths ---@type string[]
          local title = params.title ---@type string
          local handler = params.handler ---@type fun(selected_filepaths: string[]|nil): nil

          -- Launch your customized picker with the items built from `filepaths`, then in the `on_confirm` callback,
          -- pass the selected items (convert back to file paths) to the `handler` function.

          local items = __your_items_formatter__(filepaths)
          __your_picker__({
            items = items,
            on_cancel = function()
              handler(nil)
            end,
            on_confirm = function(selected_items)
              local selected_filepaths = {}
              for _, item in ipairs(selected_items) do
                table.insert(selected_filepaths, item.filepath)
              end
              handler(selected_filepaths)
            end
          })
        end,
        ---below is optional
        provider_opts = {
          ---@param params avante.file_selector.opts.IGetFilepathsParams
          get_filepaths = function(params)
            local cwd = params.cwd ---@type string
            local selected_filepaths = params.selected_filepaths ---@type string[]
            local cmd = string.format("fd --base-directory '%s' --hidden", vim.fn.fnameescape(cwd))
            local output = vim.fn.system(cmd)
            local filepaths = vim.split(output, "\n", { trimempty = true })
            return vim
              .iter(filepaths)
              :filter(function(filepath)
                return not vim.tbl_contains(selected_filepaths, filepath)
              end)
              :totable()
          end
        }
        end
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
> ~~Due to the poor performance of other models, avante.nvim only recommends using the claude-3.5-sonnet model.~~
> ~~All features can only be guaranteed to work properly on the claude-3.5-sonnet model.~~
> ~~We do not accept changes to the code or prompts to accommodate other models. Otherwise, it will greatly increase our maintenance costs.~~
> ~~We hope everyone can understand. Thank you!~~

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

## Commands

| Command | Description | Examples
|---------|-------------| ------------------
| `:AvanteAsk [question] [position]` | Ask AI about your code. Optional `position` set window position and `ask` enable/disable direct asking mode | `:AvanteAsk position=right Refactor this code here`
| `:AvanteBuild` | Build dependencies for the project |
| `:AvanteChat` | Start a chat session with AI about your codebase. Default is `ask`=false |
| `:AvanteEdit` | Edit the selected code blocks |
| `:AvanteFocus` | Switch focus to/from the sidebar |
| `:AvanteRefresh` | Refresh all Avante windows |
| `:AvanteSwitchProvider` | Switch AI provider (e.g. openai) |
| `:AvanteShowRepoMap` | Show repo map for project's structure |
| `:AvanteToggle` | Toggle the Avante sidebar |

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

See [highlights.lua](./lua/avante/highlights.lua) for more information

## Custom providers

Avante provides a set of default providers, but users can also create their own providers.

For more information, see [Custom Providers](https://github.com/yetone/avante.nvim/wiki/Custom-providers)

## Cursor planning mode

Because avante.nvim has always used Aider’s method for planning applying, but its prompts are very picky with models and require ones like claude-3.5-sonnet or gpt-4o to work properly.

Therefore, I have adopted Cursor’s method to implement planning applying. For details on the implementation, please refer to [cursor-planning-mode.md](./cursor-planning-mode.md)

## RAG Service

Avante provides a RAG service, which is a tool for obtaining the required context for the AI to generate the codes. Default it not enabled, you can enable it in this way:

```lua
rag_service = {
  enabled = false, -- Enables the RAG service, requires OPENAI_API_KEY to be set
  provider = "openai", -- The provider to use for RAG service (e.g. openai or ollama)
  llm_model = "", -- The LLM model to use for RAG service
  embed_model = "", -- The embedding model to use for RAG service
  endpoint = "https://api.openai.com/v1", -- The API endpoint for RAG service
},
```

Please note that since the RAG service uses OpenAI for embeddings, you must set `OPENAI_API_KEY` environment variable!

Additionally, RAG Service also depends on Docker! (For macOS users, OrbStack is recommended as a Docker alternative)

## Web Search Engines

Avante's tools include some web search engines, currently support:

- [Tavily](https://tavily.com/)
- [SerpApi](https://serpapi.com/)
- [SearchAPI](https://www.searchapi.io/)
- Google's [Programmable Search Engine](https://developers.google.com/custom-search/v1/overview)
- [Kagi](https://help.kagi.com/kagi/api/search.html)
- [Brave Search](https://api-dashboard.search.brave.com/app/documentation/web-search/get-started)

The default is Tavily, and can be changed through configuring `Config.web_search_engine.provider`:

```lua
web_search_engine = {
  provider = "tavily", -- tavily, serpapi, searchapi, google or kagi
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
- [ ] MCP

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
