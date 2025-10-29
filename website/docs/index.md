---
layout: home

hero:
  name: "avante.nvim"
  text: "AI-Powered Code Assistance"
  tagline: "Bring the power of Cursor AI to your Neovim editor"
  image:
    src: https://github.com/user-attachments/assets/2e2f2a58-2b28-4d11-afd1-87b65612b2de
    alt: avante.nvim
  actions:
    - theme: brand
      text: Get Started
      link: /installation
    - theme: alt
      text: View on GitHub
      link: https://github.com/yetone/avante.nvim

features:
  - icon: 🤖
    title: AI-Powered Code Assistance
    details: Interact with AI to ask questions about your current code file and receive intelligent suggestions for improvement or modification.
  
  - icon: ⚡
    title: One-Click Application
    details: Quickly apply the AI's suggested changes to your source code with a single command, streamlining the editing process and saving time.
  
  - icon: 📝
    title: Project-Specific Instructions
    details: Customize AI behavior by adding a markdown file in the project root. This file is automatically referenced during workspace changes.
  
  - icon: 🧘
    title: Zen Mode
    details: A Vibe Coding Agent CLI experience completely powered by Neovim underneath. Use your muscle-memory Vim operations with all the power of AI agents.
  
  - icon: 🔌
    title: Multiple AI Providers
    details: Support for Claude, OpenAI, Azure, Copilot, Gemini, Cohere, and many more AI providers out of the box.
  
  - icon: 🎨
    title: Customizable UI
    details: Beautiful and customizable interface that seamlessly integrates with your Neovim setup.
---

## What is avante.nvim?

**avante.nvim** is a Neovim plugin designed to emulate the behaviour of the [Cursor](https://www.cursor.com) AI IDE. It provides users with AI-driven code suggestions and the ability to apply these recommendations directly to their source files with minimal effort.

<div style="margin: 2rem 0;">
  <video controls style="width: 100%; border-radius: 8px;">
    <source src="https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53" type="video/mp4">
  </video>
</div>

## Why avante.nvim?

In the era of Coding Agent CLIs, many argue that editors are no longer needed. However, **avante.nvim** proves that Terminal-based Editors have already solved and standardized the biggest problem with Terminal-based applications — awkward TUI interactions!

No matter how much these Coding Agent CLIs optimize their UI/UX, they will always be a subset of Terminal-based Editors (Vim, Emacs). They cannot achieve Vim's elegant action + text objects abstraction, nor can they leverage thousands of mature Vim/Neovim plugins to optimize TUI UI/UX.

With **avante.nvim**, you get:

- The power of AI-driven coding assistance
- Your familiar Vim/Neovim muscle memory
- Rich ecosystem of Neovim plugins
- Seamless code viewing and modification without context switching
- All the capabilities of claude code / gemini-cli / codex through ACP support

## Quick Start

Install with [lazy.nvim](https://github.com/folke/lazy.nvim):

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

See the [Installation Guide](/installation) for detailed instructions.

## Community

- 🐛 [Report Issues](https://github.com/yetone/avante.nvim/issues)
- 💬 [Join Discord](https://discord.gg/QfnEFEdSjz)
- ❤️ [Sponsor on Patreon](https://patreon.com/yetone)

## Special Thanks

<div align="center" style="margin: 2rem 0;">
  <a href="https://www.warp.dev/avantenvim">
    <img alt="Warp sponsorship" width="400" src="https://github.com/user-attachments/assets/0fb088f2-f684-4d17-86d2-07a489229083">
  </a>
  <p><a href="https://www.warp.dev/avantenvim">Warp, the intelligent terminal for developers</a></p>
  <p><a href="https://www.warp.dev/avantenvim">Available for MacOS, Linux, & Windows</a></p>
</div>
