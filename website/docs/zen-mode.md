# Zen Mode

## What is Zen Mode?

Zen Mode is avante.nvim's revolutionary CLI-like interface that combines the power of modern AI coding agents (like Claude Code, Gemini CLI, and Codex) with the efficiency and familiarity of Neovim.

<div align="center" style="margin: 2rem 0;">
  <img alt="Avante Zen Mode" src="https://github.com/user-attachments/assets/60880f65-af55-4e4c-a565-23bb63e19251" style="width: 100%; border-radius: 8px;" />
</div>

## Why Zen Mode?

In the era of Coding Agent CLIs, many argue that traditional editors are becoming obsolete. However, this perspective overlooks a crucial fact:

**Terminal-based Editors have already solved and standardized the biggest problem with Terminal-based applications — awkward TUI interactions!**

### The Problem with Coding Agent CLIs

Modern Coding Agent CLIs face several limitations:

- **Limited UI/UX**: No matter how optimized, CLI UI/UX is always a subset of what terminal editors can offer
- **No Vim abstractions**: Cannot achieve Vim's elegant action + text objects model
- **Poor multi-line editing**: Editing large prompts is cumbersome
- **Plugin ecosystem**: Cannot leverage thousands of mature Vim/Neovim plugins
- **Context switching**: Must jump to other applications to view/edit code, disrupting workflow

### The Zen Mode Solution

Zen Mode looks like a Vibe Coding Agent CLI but is **completely Neovim underneath**. This gives you:

- ✅ All your familiar Vim muscle memory and operations
- ✅ Access to thousands of mature Neovim plugins (easymotion, telescope, etc.)
- ✅ Seamless code viewing and modification within the same interface
- ✅ All capabilities of claude code / gemini-cli / codex through ACP support
- ✅ No context switching or workflow interruption

## Setting Up Zen Mode

### Basic Setup

Add this alias to your shell configuration (`.bashrc`, `.zshrc`, etc.):

```bash
alias avante='nvim -c "lua vim.defer_fn(function()require(\"avante.api\").zen_mode()end, 100)"'
```

Reload your shell:

```bash
source ~/.bashrc  # or ~/.zshrc
```

### Advanced Setup

For a more customized experience:

```bash
alias avante='nvim -u ~/.config/nvim/zen.lua'
```

Create `~/.config/nvim/zen.lua`:

```lua
-- Minimal config optimized for Zen Mode
vim.g.mapleader = " "

-- Load your plugin manager and avante.nvim
require("lazy").setup({
  {
    "yetone/avante.nvim",
    build = "make",
    opts = {
      provider = "claude",
      -- Zen Mode optimized settings
      windows = {
        position = "bottom",
        width = 100,
      },
    },
  },
  -- Add other essential plugins
})

-- Auto-start Zen Mode
vim.defer_fn(function()
  require("avante.api").zen_mode()
end, 100)
```

## Using Zen Mode

### Starting Zen Mode

Simply type `avante` in your terminal:

```bash
avante
```

This launches Neovim directly in Zen Mode, ready for AI-assisted coding.

### Working in Zen Mode

Once in Zen Mode, you can:

1. **Start a conversation**: Begin typing your coding request
2. **Use Vim operations**: All your Vim muscle memory works
3. **View/edit code**: Open files directly without leaving the interface
4. **Apply suggestions**: Review and apply AI suggestions inline
5. **Navigate freely**: Use Vim motions to move around

### Example Workflow

```bash
# Start Zen Mode
avante

# In Zen Mode, ask AI to create a file
> Create a Python FastAPI application with user authentication

# Review the generated code with Vim motions
# Use j/k to navigate, / to search, etc.

# Edit the code using Vim commands
:e app.py
# Make changes using normal Vim editing

# Ask follow-up questions
> Add password hashing to the authentication

# Apply changes
<CR>
```

## Zen Mode Features

### Full Vim/Neovim Capabilities

- **Motions**: `h`, `j`, `k`, `l`, `w`, `b`, `e`, `f`, `t`, etc.
- **Text objects**: `ciw`, `dap`, `yi"`, `va}`, etc.
- **Operators**: `d`, `c`, `y`, `p`, `>`, `<`, etc.
- **Registers**: `"ay`, `"bp`, etc.
- **Marks**: `ma`, `` `a ``, etc.
- **Macros**: `qa`, `@a`, `@@`, etc.

### Plugin Integration

Use your favorite plugins in Zen Mode:

- **telescope.nvim**: Fuzzy finding
- **vim-easymotion**: Quick navigation
- **vim-surround**: Surround operations
- **nvim-treesitter**: Syntax highlighting
- **Any other Neovim plugin**

### ACP Support

Zen Mode includes full ACP (AI Coding Protocol) support, giving you all the capabilities of:

- claude code
- gemini-cli
- codex
- Other AI coding agents

## Tips for Zen Mode

### Efficient Prompt Editing

Use Vim's text editing power for complex prompts:

```vim
" Multi-line prompt editing
i  " Enter insert mode
# Type your multi-line prompt
" Can you help me:
" 1. Create a REST API
" 2. Add authentication
" 3. Write tests
<Esc>  " Exit insert mode

" Now use Vim commands to edit
cc  " Change entire line
dd  " Delete line
o   " Open new line
```

### File Operations

```vim
" Open files directly
:e myfile.py

" Split windows
:vs otherfile.py
:sp testfile.py

" Navigate between buffers
:bn  " Next buffer
:bp  " Previous buffer
```

### Search and Replace

```vim
" Search in conversation
/function

" Replace in generated code
:%s/old/new/g
```

### Quick Navigation

With plugins like easymotion:

```vim
<leader><leader>w  " Jump to word
<leader><leader>f  " Jump to character
```

## Comparison with Traditional CLIs

| Feature | Traditional CLI | Zen Mode |
|---------|----------------|----------|
| Multi-line editing | Limited | Full Vim power |
| Navigation | Arrow keys only | All Vim motions |
| Text objects | None | Full support |
| Plugin ecosystem | None | Thousands available |
| Muscle memory | CLI-specific | Vim (decades old) |
| Code viewing | External tool | Built-in |
| Context switching | Required | None |

## Advanced Usage

### Custom Zen Mode Configuration

Create a dedicated Zen Mode config:

```lua
-- ~/.config/nvim/zen.lua
local function setup_zen_mode()
  -- Customize UI for Zen Mode
  vim.opt.number = false
  vim.opt.relativenumber = false
  vim.opt.signcolumn = "no"
  
  -- Custom keymaps for Zen Mode
  vim.keymap.set("n", "<leader>q", "<cmd>qa<cr>")
  vim.keymap.set("n", "<leader>n", "<cmd>enew<cr>")
end

-- Auto-load Zen Mode
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    setup_zen_mode()
    vim.defer_fn(function()
      require("avante.api").zen_mode()
    end, 100)
  end,
})
```

### Integration with tmux

Combine with tmux for ultimate productivity:

```bash
# Start tmux session with Zen Mode
tmux new-session -s coding "avante"
```

## Exit Zen Mode

To exit Zen Mode:

```vim
:qa  " Quit all
```

Or use your custom keybinding:

```vim
<leader>q  " If configured
```

## Next Steps

- [Quick Start](/quickstart) - Learn the basics
- [Features](/features) - Explore all features
- [Configuration](/configuration) - Customize your setup
- [Project Instructions](/project-instructions) - Add project context

## Getting Help

- 🐛 [Report Issues](https://github.com/yetone/avante.nvim/issues)
- 💬 [Join Discord](https://discord.gg/QfnEFEdSjz)
- ❤️ [Support on Patreon](https://patreon.com/yetone)
