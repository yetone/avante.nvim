# avante.nvim

**avante.nvim** is a Neovim plugin designed to emulate the behaviour of the [Cursor](https://www.cursor.com) AI IDE. It provides users with AI-driven code suggestions and the ability to apply these recommendations directly to their source files with minimal effort.

> [!NOTE]
>
> 🥰 This project is undergoing rapid iterations, and many exciting features will be added successively. Stay tuned!

https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53

https://github.com/user-attachments/assets/86140bfd-08b4-483d-a887-1b701d9e37dd

## Features

- **AI-Powered Code Assistance**: Interact with AI to ask questions about your current code file and receive intelligent suggestions for improvement or modification.
- **One-Click Application**: Quickly apply the AI's suggested changes to your source code with a single command, streamlining the editing process and saving time.

## Installation


<details open>

  <summary><a href="https://github.com/folke/lazy.nvim">lazy.nvim</a> (recommended)</summary>

```lua
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  lazy = false,
  opts = {
    -- add any opts here
  },
  build = ":AvanteBuild", -- This is optional, recommended tho. Also note that this will block the startup for a bit since we are compiling bindings in Rust.
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
      -- Make sure to setup it properly if you have lazy=true
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
Plug 'stevearc/dressing.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'

" Optional deps
Plug 'nvim-tree/nvim-web-devicons' "or Plug 'echasnovski/mini.icons'
Plug 'HakonHarnes/img-clip.nvim'
Plug 'zbirenbaum/copilot.lua'

" Yay
Plug 'yetone/avante.nvim', { 'branch': 'main', 'do': ':AvanteBuild', 'on': 'AvanteAsk' }
```

> [!important]
>
> For `avante.tokenizers` to work, make sure to call `require('avante_lib').load()` somewhere when entering the editor.
> We will leave the users to decide where it fits to do this, as this varies among configurations. (But we do recommend running this after where you set your colorscheme)

</details>

<details>

  <summary><a href="https://github.com/echasnovski/mini.deps">mini.deps</a></summary>

```lua
local add, later, now = MiniDeps.add, MiniDeps.later, MiniDeps.now

add({
  source = 'yetone/avante.nvim',
  monitor = 'main',
  depends = {
    'stevearc/dressing.nvim',
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    'echasnovski/mini.icons'
  },
  hooks = { post_checkout = function() vim.cmd('AvanteBuild') end }
})
--- optional
add({ source = 'zbirenbaum/copilot.lua' })
add({ source = 'HakonHarnes/img-clip.nvim' })
add({ source = 'MeanderingProgrammer/render-markdown.nvim' })

now(function() require('avante_lib').load() end)
later(function() require('render-markdown').setup({...}) end)
later(function()
  require('img-clip').setup({...}) -- config img-clip
  require("copilot").setup({...}) -- setup copilot to your liking
  require("avante").setup({...}) -- config for avante.nvim
end)
```

</details>

<details>

  <summary>Lua</summary>

```lua
-- deps:
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
> `render-markdown.nvim` is an optional dependency that is used to render the markdown content of the chat history. Make sure to also include `Avante` as a filetype
> to its setup (e.g. via Lazy):
>
> ```lua
> {
>   "MeanderingProgrammer/render-markdown.nvim",
>   opts = {
>     file_types = { "markdown", "Avante" },
>   },
>   ft = { "markdown", "Avante" },
> }
> ```

> [!TIP]
>
> Any rendering plugins that support markdown should work with Avante as long as you add the supported filetype `Avante`. See https://github.com/yetone/avante.nvim/issues/175 and [this comment](https://github.com/yetone/avante.nvim/issues/175#issuecomment-2313749363) for more information.

### Default setup configuration

_See [config.lua#L9](./lua/avante/config.lua) for the full config_

```lua
{
  ---@alias Provider "claude" | "openai" | "azure" | "gemini" | "cohere" | "copilot" | string
  provider = "claude", -- Recommend using Claude
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20240620",
    temperature = 0,
    max_tokens = 4096,
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
    jump = {
      next = "]]",
      prev = "[[",
    },
    submit = {
      normal = "<CR>",
      insert = "<C-s>",
    },
  },
  hints = { enabled = true },
  windows = {
    wrap = true, -- similar to vim.o.wrap
    width = 30, -- default % based on available width
    sidebar_header = {
      align = "center", -- left, center, right for title
      rounded = true,
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
  },
}
```

## Usage

Given its early stage, `avante.nvim` currently supports the following basic functionalities:

> [!IMPORTANT]
>
> Avante will only support Claude, and OpenAI (and its variants including azure)out-of-the-box due to its high code quality generation.
> For all OpenAI-compatible providers, see [wiki](https://github.com/yetone/avante.nvim/wiki) for more details.

> [!IMPORTANT]
>
> Due to the poor performance of other models, avante.nvim only recommends using the claude-3.5-sonnet model.
> All features can only be guaranteed to work properly on the claude-3.5-sonnet model.
> We do not accept changes to the code or prompts to accommodate other models. Otherwise, it will greatly increase our maintenance costs.
> We hope everyone can understand. Thank you!

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

1. Open a code file in Neovim.
2. Use the `:AvanteAsk` command to query the AI about the code.
3. Review the AI's suggestions.
4. Apply the recommended changes directly to your code with a simple command or key binding.

**Note**: The plugin is still under active development, and both its functionality and interface are subject to significant changes. Expect some rough edges and instability as the project evolves.

## Key Bindings

The following key bindings are available for use with `avante.nvim`:

| Key Binding | Description |
|-------------|-------------|
| <kbd>Leader</kbd><kbd>a</kbd><kbd>a</kbd> | show sidebar |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>r</kbd> | refresh sidebar |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>e</kbd> | edit selected blocks |
| <kbd>c</kbd><kbd>o</kbd> | choose ours |
| <kbd>c</kbd><kbd>t</kbd> | choose theirs |
| <kbd>c</kbd><kbd>a</kbd> | choose all theirs |
| <kbd>c</kbd><kbd>0</kbd> | choose none |
| <kbd>c</kbd><kbd>b</kbd> | choose both |
| <kbd>c</kbd><kbd>c</kbd> | choose cursor |
| <kbd>]</kbd><kbd>x</kbd> | move to previous conflict |
| <kbd>[</kbd><kbd>x</kbd> | move to next conflict |
| <kbd>[</kbd><kbd>[</kbd> | jump to previous codeblocks (results window) |
| <kbd>]</kbd><kbd>]</kbd> | jump to next codeblocks (results windows) |

> [!NOTE]
>
> If you are using `lazy.nvim`, then all keymap here will be safely set, meaning if `<leader>aa` is already binded, then avante.nvim won't bind this mapping.
> In this case, user will be responsible for setting up their own. See [notes on keymaps](https://github.com/yetone/avante.nvim/wiki#keymaps-and-api-i-guess) for more details.

## Highlight Groups


| Highlight Group | Description | Notes |
|-----------------|-------------|-------|
| AvanteTitle | Title | |
| AvanteReversedTitle | Used for rounded border | |
| AvanteSubtitle | Selected code title | |
| AvanteReversedSubtitle | Used for rounded border | |
| AvanteThirdTitle | Prompt title | |
| AvanteReversedThirdTitle | Used for rounded border | |
| AvanteConflictCurrent | Current conflict highlight | Default to `Config.highlights.diff.current` |
| AvanteConflictIncoming | Incoming conflict highlight | Default to `Config.highlights.diff.incoming` |
| AvanteConflictCurrentLabel | Current conflict label highlight | Default to shade of `AvanteConflictCurrent` |
| AvanteConflictIncomingLabel | Incoming conflict label highlight | Default to shade of `AvanteConflictIncoming` |

See [highlights.lua](./lua/avante/highlights.lua) for more information

## TODOs

- [x] Chat with current file
- [x] Apply diff patch
- [x] Chat with the selected block
- [x] Slash commands
- [x] Edit the selected block
- [ ] Smart Tab (Cursor Flow)
- [ ] Chat with project
- [ ] Chat with selected files

## Roadmap

- **Enhanced AI Interactions**: Improve the depth of AI analysis and recommendations for more complex coding scenarios.
- **LSP + Tree-sitter + LLM Integration**: Integrate with LSP and Tree-sitter and LLM to provide more accurate and powerful code suggestions and analysis.

## Contributing

Contributions to avante.nvim are welcome! If you're interested in helping out, please feel free to submit pull requests or open issues. Before contributing, ensure that your code has been thoroughly tested.

See [wiki](https://github.com/yetone/avante.nvim/wiki) for more recipes and tricks.

## Acknowledgments

We would like to express our heartfelt gratitude to the contributors of the following open-source projects, whose code has provided invaluable inspiration and reference for the development of avante.nvim:

| Nvim Plugin | License | Functionality | Where did we use |
| --- | --- | --- | --- |
| [git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim) | No License | Diff comparison functionality | https://github.com/yetone/avante.nvim/blob/main/lua/avante/diff.lua |
| [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim) | Apache 2.0 License | Calculation of tokens count | https://github.com/yetone/avante.nvim/blob/main/lua/avante/utils/tokens.lua |
| [img-clip.nvim](https://github.com/HakonHarnes/img-clip.nvim) | MIT License | Clipboard image support | https://github.com/yetone/avante.nvim/blob/main/lua/avante/clipboard.lua |
| [copilot.lua](https://github.com/zbirenbaum/copilot.lua) | MIT License | Copilot support | https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/copilot.lua |

The high quality and ingenuity of these projects' source code have been immensely beneficial throughout our development process. We extend our sincere thanks and respect to the authors and contributors of these projects. It is the selfless dedication of the open-source community that drives projects like avante.nvim forward.

## License

avante.nvim is licensed under the Apache 2.0 License. For more details, please refer to the [LICENSE](./LICENSE) file.
