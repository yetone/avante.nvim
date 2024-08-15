# avante.nvim (Alpha)

**avante.nvim** is a Neovim plugin designed to emulate the behavior of the [Cursor](https://www.cursor.com) AI IDE, providing users with AI-driven code suggestions and the ability to apply these recommendations directly to their source files with minimal effort.

> [!NOTE]
> ⚠️⚠️ This plugin is still in a very early stage of development, so please be aware that the current code is very messy and unstable, and problems are likely to occur.

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
    opts = {},
    build = "make",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
      {
        "grapp-dev/nui-components.nvim",
        dependencies = {
          "MunifTanjim/nui.nvim"
        }
      },
      "nvim-lua/plenary.nvim",
      "MeanderingProgrammer/render-markdown.nvim",
    },
  }
  ```

> [!IMPORTANT]
>
> If your neovim doesn't use LuaJIT, then change `build` to `make lua51`. By default running make will install luajit.
> For ARM-based setup, make sure to also install cargo as we will have to build the tiktoken_core from source.

Default setup configuration:

  ```lua
  {
    provider = "claude", -- "claude" or "openai" or "azure"
    openai = {
      endpoint = "https://api.openai.com",
      model = "gpt-4o",
      temperature = 0,
      max_tokens = 4096,
    },
    azure = {
      endpoint = "", -- Example: "https://<your-resource-name>.openai.azure.com"
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
  ```

## Usage

Given its early stage, `avante.nvim` currently supports the following basic functionalities:

1. Set the appropriate API key as an environment variable:

   For Claude:

   ```sh
   export ANTHROPIC_API_KEY=your-api-key
   ```

   For OpenAI:

   ```sh
   export OPENAI_API_KEY=your-api-key
   ```

   For Azure OpenAI:

   ```sh
   export AZURE_OPENAI_API_KEY=your-api-key
   ```

2. Open a code file in Neovim.
3. Use the `:AvanteAsk` command to query the AI about the code.
4. Review the AI's suggestions.
5. Apply the recommended changes directly to your code with a simple command or key binding.

**Note**: The plugin is still under active development, and both its functionality and interface are subject to significant changes. Expect some rough edges and instability as the project evolves.

## Key Bindings

The following key bindings are available for use with `avante.nvim`:

- <kbd>Leader</kbd><kbd>a</kbd><kbd>a</kbd> — show sidebar
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
- [ ] Chat with selected block
- [ ] Chat with project
- [ ] Chat with selected files
- [ ] Auto suggestion and completion

## Contributing

Contributions to avante.nvim are welcome! If you're interested in helping out, please feel free to submit pull requests or open issues. Before contributing, ensure that your code has been thoroughly tested.

## Development

To set up the development environment:

1. Install [StyLua](https://github.com/JohnnyMorganz/StyLua) for Lua code formatting.
2. Install [pre-commit](https://pre-commit.com) for managing and maintaining pre-commit hooks.
3. After cloning the repository, run the following command to set up pre-commit hooks:

```sh
pre-commit install --install-hooks
```

## License

avante.nvim is licensed under the Apache License. For more details, please refer to the [LICENSE](./LICENSE) file.
