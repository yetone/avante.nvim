import { defineConfig } from 'vitepress'

export default defineConfig({
  title: "avante.nvim",
  description: "AI-powered code assistance for Neovim",
  base: '/avante.nvim/',
  head: [
    ['link', { rel: 'icon', href: '/avante.nvim/favicon.ico' }]
  ],
  themeConfig: {
    logo: 'https://github.com/user-attachments/assets/2e2f2a58-2b28-4d11-afd1-87b65612b2de',
    
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Installation', link: '/installation' },
      { text: 'Features', link: '/features' },
      { text: 'Configuration', link: '/configuration' },
      { text: 'GitHub', link: 'https://github.com/yetone/avante.nvim' }
    ],

    sidebar: [
      {
        text: 'Getting Started',
        items: [
          { text: 'Introduction', link: '/' },
          { text: 'Installation', link: '/installation' },
          { text: 'Quick Start', link: '/quickstart' }
        ]
      },
      {
        text: 'Guide',
        items: [
          { text: 'Features', link: '/features' },
          { text: 'Configuration', link: '/configuration' },
          { text: 'Zen Mode', link: '/zen-mode' },
          { text: 'Project Instructions', link: '/project-instructions' }
        ]
      },
      {
        text: 'Community',
        items: [
          { text: 'Contributing', link: '/contributing' },
          { text: 'Sponsorship', link: '/sponsorship' }
        ]
      }
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/yetone/avante.nvim' },
      { icon: 'discord', link: 'https://discord.gg/QfnEFEdSjz' }
    ],

    footer: {
      message: 'Released under the Apache 2.0 License.',
      copyright: 'Copyright © 2024-present Yetone Zhang'
    },

    search: {
      provider: 'local'
    }
  }
})
