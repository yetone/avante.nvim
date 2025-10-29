# Quick Start

## Installation

First, install avante.nvim using your preferred plugin manager. See the [Installation Guide](/installation) for detailed instructions.

Quick install with lazy.nvim:

```lua
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  build = "make",
  opts = {
    provider = "claude",
  },
  dependencies = {
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons",
  },
}
```

## Set Up API Key

Configure your AI provider's API key as an environment variable:

```bash
# For Claude (recommended)
export ANTHROPIC_API_KEY="your-api-key-here"

# For OpenAI
export OPENAI_API_KEY="your-api-key-here"
```

Add this to your `.bashrc`, `.zshrc`, or equivalent shell configuration file, then restart your terminal.

## Basic Usage

### 1. Open a Code File

Open any code file in Neovim:

```bash
nvim myfile.py
```

### 2. Activate avante

Toggle the avante sidebar with the default keybinding:

```
<leader>aa
```

Or use the command:

```vim
:AvanteToggle
```

### 3. Ask Questions

In the avante sidebar, type your question or request. For example:

```
Can you explain what this function does?
```

Press `<CR>` (Enter) to submit.

### 4. Apply Suggestions

When the AI provides code suggestions:

1. Review the suggested changes in the diff view
2. Press `<CR>` to apply the changes
3. Or use `q` to dismiss

### 5. Edit Code with AI

Select code in visual mode, then press `<leader>ae`:

```vim
" Select some code in visual mode
V}

" Press <leader>ae and enter your request
" Example: "Refactor this to use async/await"
```

## Common Workflows

### Getting Code Explanations

1. Open a file with complex code
2. Toggle avante (`<leader>aa`)
3. Ask: "Explain this function step by step"
4. Review the explanation in the sidebar

### Refactoring Code

1. Select the code to refactor (visual mode)
2. Press `<leader>ae`
3. Enter your refactoring request: "Extract this into a separate function"
4. Review and apply the changes

### Debugging Help

1. Open a file with a bug
2. Toggle avante
3. Ask: "Why isn't this working as expected?"
4. Follow the AI's suggestions to fix the issue

### Writing Tests

1. Open your source file
2. Toggle avante
3. Ask: "Write unit tests for this function"
4. Review and apply the generated tests

### Documentation

1. Select a function or class
2. Press `<leader>ae`
3. Request: "Add comprehensive documentation"
4. Apply the documentation

## Default Keybindings

- `<leader>aa` - Toggle avante sidebar
- `<leader>ar` - Refresh AI suggestions
- `<leader>ae` - Edit selected code with AI (visual mode)
- `<leader>ac` - Clear conversation history
- `<CR>` - Apply suggestion (in sidebar)
- `q` - Close sidebar
- `<Tab>` - Switch windows in sidebar
- `]]` - Jump to next suggestion
- `[[` - Jump to previous suggestion

## Tips for Better Results

### Be Specific

Instead of:
```
Make this better
```

Try:
```
Refactor this function to improve readability by:
- Using descriptive variable names
- Breaking it into smaller functions
- Adding comments for complex logic
```

### Provide Context

Instead of:
```
Fix this
```

Try:
```
This function should sort users by age, but it's returning 
incorrect results. The expected behavior is to sort in 
ascending order.
```

### Use Project Instructions

Create an `avante.md` file in your project root to provide context:

```markdown
# Project Instructions

## Your Role
You are an expert Python developer working on a Django web application.

## Coding Standards
- Use Python 3.11+ features
- Follow PEP 8 style guide
- Write docstrings for all functions
- Prefer type hints
```

See [Project Instructions](/project-instructions) for more details.

## Troubleshooting

### Sidebar Won't Open

Check if avante is loaded:

```vim
:checkhealth avante
```

### No Response from AI

Verify your API key is set:

```bash
echo $ANTHROPIC_API_KEY
```

Check the logs:

```vim
:messages
```

### Build Failed

Try building from source:

```bash
cd ~/.local/share/nvim/lazy/avante.nvim
make BUILD_FROM_SOURCE=true
```

## Next Steps

- [Features](/features) - Explore all available features
- [Configuration](/configuration) - Customize your setup
- [Zen Mode](/zen-mode) - Try the CLI-like experience
- [Project Instructions](/project-instructions) - Set up project-specific behavior

## Getting Help

- 📖 [Full Documentation](/)
- 🐛 [Report Issues](https://github.com/yetone/avante.nvim/issues)
- 💬 [Join Discord](https://discord.gg/QfnEFEdSjz)
- ❤️ [Support on Patreon](https://patreon.com/yetone)
