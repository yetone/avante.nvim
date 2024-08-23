# avante.nvim (Alpha)

**avante.nvim** is a Neovim plugin designed to emulate the behavior of the [Cursor](https://www.cursor.com) AI IDE, providing users with AI-driven code suggestions and the ability to apply these recommendations directly to their source files with minimal effort.

> [!NOTE]
>
> ⚠️ This plugin is still in a very early stage of development, so please be aware that the current code is very messy and unstable, and problems are likely to occur.
>
> 🥰 This project is undergoing rapid iterations, and many exciting features will be added successively. Stay tuned!

https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53

https://github.com/user-attachments/assets/86140bfd-08b4-483d-a887-1b701d9e37dd

## Features

- **AI-Powered Code Assistance**: Interact with AI to ask questions about your current code file and receive intelligent suggestions for improvement or modification.
- **One-Click Application**: Quickly apply the AI's suggested changes to your source code with a single command, streamlining the editing process and saving time.

## Installation

Install `avante.nvim` using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  build = "make",
  opts = {
    -- add any opts here
  },
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    --- The below is optional, make sure to setup it properly if you have lazy=true
    {
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { "markdown", "Avante" },
      },
      ft = { "markdown", "Avante" },
    },
  },
}
```

For Windows users, change the build command to the following:

```lua
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  build = "powershell -ExecutionPolicy Bypass -File Build-LuaTiktoken.ps1",
  -- rest of the config
}
```

> [!IMPORTANT]
>
> `avante.nvim` is currently only compatible with Neovim 0.10.0 or later. Please ensure that your Neovim version meets these requirements before proceeding.

> [!IMPORTANT]
>
> If your neovim doesn't use LuaJIT, then change `build` to `make lua51`. By default running make will install luajit.
> For ARM-based setup, make sure to also install cargo as we will have to build the tiktoken_core from source.

> [!NOTE]
>
> Recommended **Neovim** options:
>
> ```lua
> -- views can only be fully collapsed with the global statusline
> vim.opt.laststatus = 3
> -- Default splitting will cause your main splits to jump when opening an edgebar.
> -- To prevent this, set `splitkeep` to either `screen` or `topline`.
> vim.opt.splitkeep = "screen"
> ```

> [!NOTE]
>
> `render-markdown.nvim` is an optional dependency that is used to render the markdown content of the chat history. Make sure to also include `Avante` as a filetype
> to its setup:
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

Default setup configuration:

_See [config.lua#L9](./lua/avante/config.lua) for the full config_

```lua
{
  ---@alias Provider "openai" | "claude" | "azure"  | "copilot" | [string]
  provider = "claude",
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20240620",
    temperature = 0,
    max_tokens = 4096,
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
    debug = false,
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
> Avante will only support OpenAI (and its variants including copilot and azure), and Claude out-of-the-box due to its high code quality generation.
> For all OpenAI-compatible providers, see [wiki](https://github.com/yetone/avante.nvim/wiki) for more details.

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

- <kbd>Leader</kbd><kbd>a</kbd><kbd>a</kbd> — show sidebar
- <kbd>Leader</kbd><kbd>a</kbd><kbd>r</kbd> — show sidebar
- <kbd>c</kbd><kbd>o</kbd> — choose ours
- <kbd>c</kbd><kbd>t</kbd> — choose theirs
- <kbd>c</kbd><kbd>b</kbd> — choose both
- <kbd>c</kbd><kbd>0</kbd> — choose none
- <kbd>]</kbd><kbd>x</kbd> — move to previous conflict
- <kbd>[</kbd><kbd>x</kbd> — move to next conflict

## Roadmap

- **Enhanced AI Interactions**: Improve the depth of AI analysis and recommendations for more complex coding scenarios.
- **Stability Improvements**: Refactor and optimize the codebase to enhance the stability and reliability of the plugin.
- **Expanded Features**: Introduce additional customization options and new features to support a wider range of coding tasks.

## TODOs

- [x] Chat with current file
- [x] Apply diff patch
- [x] Chat with the selected block
- [x] Slash commands
- [ ] Edit the selected block
- [ ] Smart Tab (Cursor Flow)
- [ ] Chat with project
- [ ] Chat with selected files

## Contributing

Contributions to avante.nvim are welcome! If you're interested in helping out, please feel free to submit pull requests or open issues. Before contributing, ensure that your code has been thoroughly tested.

See [wiki](https://github.com/yetone/avante.nvim/wiki) for more recipes and tricks.


## License

avante.nvim is licensed under the Apache License. For more details, please refer to the [LICENSE](./LICENSE) file.
