'use client'

import { useState } from 'react'
import { Copy, Check, ExternalLink } from 'lucide-react'

const installationMethods = [
  {
    id: 'lazy',
    name: 'lazy.nvim',
    description: 'Most popular Neovim plugin manager',
    code: `{
  "yetone/avante.nvim",
  build = "make",
  event = "VeryLazy",
  version = false,
  opts = {
    provider = "claude",
    providers = {
      claude = {
        endpoint = "https://api.anthropic.com",
        model = "claude-sonnet-4-20250514",
      },
    },
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons",
  },
}`
  },
  {
    id: 'packer',
    name: 'packer.nvim',
    description: 'Traditional Neovim plugin manager',
    code: `use {
  'yetone/avante.nvim',
  branch = 'main',
  run = 'make',
  config = function()
    require('avante').setup({
      provider = "claude",
    })
  end,
  requires = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons',
  }
}`
  },
  {
    id: 'vim-plug',
    name: 'vim-plug',
    description: 'Classic Vim plugin manager',
    code: `Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'yetone/avante.nvim', { 'branch': 'main', 'do': 'make' }

" After plug#end()
lua << EOF
require('avante').setup({
  provider = "claude",
})
EOF`
  },
  {
    id: 'manual',
    name: 'Manual',
    description: 'Manual installation for advanced users',
    code: `# Clone the repository
git clone https://github.com/yetone/avante.nvim.git ~/.local/share/nvim/site/pack/avante/start/avante.nvim

# Build the plugin
cd ~/.local/share/nvim/site/pack/avante/start/avante.nvim
make

# Add to your init.lua
require('avante').setup({
  provider = "claude",
})`
  }
]

const prerequisites = [
  {
    name: 'Neovim',
    version: '0.10.1+',
    description: 'Latest version of Neovim'
  },
  {
    name: 'Build Tools',
    version: 'make, cargo',
    description: 'Required for building from source'
  },
  {
    name: 'API Key',
    version: 'Claude/OpenAI',
    description: 'API key for your preferred AI provider'
  }
]

export function InstallationSection() {
  const [activeTab, setActiveTab] = useState('lazy')
  const [copiedCode, setCopiedCode] = useState<string | null>(null)

  const copyToClipboard = async (code: string, id: string) => {
    await navigator.clipboard.writeText(code)
    setCopiedCode(id)
    setTimeout(() => setCopiedCode(null), 2000)
  }

  const activeMethod = installationMethods.find(method => method.id === activeTab)

  return (
    <section id="installation" className="section-padding bg-gray-50 dark:bg-gray-800">
      <div className="container-max-w">
        {/* Section Header */}
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold mb-6 text-gray-900 dark:text-white">
            Get Started in
            <span className="text-primary-600 dark:text-primary-400"> Minutes</span>
          </h2>
          <p className="text-xl text-gray-600 dark:text-gray-300 max-w-3xl mx-auto">
            Choose your preferred installation method and start using AI-powered coding in Neovim today.
          </p>
        </div>

        <div className="grid lg:grid-cols-3 gap-8">
          {/* Prerequisites */}
          <div className="lg:col-span-1">
            <div className="bg-white dark:bg-gray-900 rounded-xl p-6 shadow-lg">
              <h3 className="text-xl font-bold mb-6 text-gray-900 dark:text-white flex items-center">
                <span className="w-6 h-6 bg-primary-600 rounded-full text-white text-sm flex items-center justify-center mr-3">
                  !
                </span>
                Prerequisites
              </h3>

              <div className="space-y-4">
                {prerequisites.map((prereq, index) => (
                  <div key={index} className="border-l-4 border-primary-600 pl-4">
                    <div className="flex items-center justify-between mb-1">
                      <h4 className="font-semibold text-gray-900 dark:text-white">
                        {prereq.name}
                      </h4>
                      <span className="text-sm text-primary-600 dark:text-primary-400 font-mono">
                        {prereq.version}
                      </span>
                    </div>
                    <p className="text-sm text-gray-600 dark:text-gray-300">
                      {prereq.description}
                    </p>
                  </div>
                ))}
              </div>

              <div className="mt-6 p-4 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg border border-yellow-200 dark:border-yellow-800">
                <p className="text-sm text-yellow-800 dark:text-yellow-200">
                  <strong>Note:</strong> You&apos;ll need to set your API key as an environment variable or configure it during setup.
                </p>
              </div>
            </div>
          </div>

          {/* Installation Methods */}
          <div className="lg:col-span-2">
            <div className="bg-white dark:bg-gray-900 rounded-xl shadow-lg overflow-hidden">
              {/* Tabs */}
              <div className="border-b border-gray-200 dark:border-gray-700">
                <nav className="flex space-x-0">
                  {installationMethods.map((method) => (
                    <button
                      key={method.id}
                      onClick={() => setActiveTab(method.id)}
                      className={`flex-1 px-4 py-4 text-sm font-medium border-b-2 transition-colors ${
                        activeTab === method.id
                          ? 'border-primary-600 text-primary-600 bg-primary-50 dark:bg-primary-900/20'
                          : 'border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
                      }`}
                    >
                      <div className="text-center">
                        <div className="font-semibold">{method.name}</div>
                        <div className="text-xs opacity-75 mt-1">{method.description}</div>
                      </div>
                    </button>
                  ))}
                </nav>
              </div>

              {/* Code Block */}
              {activeMethod && (
                <div className="relative">
                  <div className="p-6">
                    <div className="flex items-center justify-between mb-4">
                      <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                        Installation with {activeMethod.name}
                      </h3>
                      <button
                        onClick={() => copyToClipboard(activeMethod.code, activeMethod.id)}
                        className="flex items-center space-x-2 px-3 py-2 text-sm bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 rounded-lg transition-colors"
                      >
                        {copiedCode === activeMethod.id ? (
                          <>
                            <Check className="w-4 h-4" />
                            <span>Copied!</span>
                          </>
                        ) : (
                          <>
                            <Copy className="w-4 h-4" />
                            <span>Copy</span>
                          </>
                        )}
                      </button>
                    </div>

                    <div className="code-block">
                      <pre className="overflow-x-auto">
                        <code>{activeMethod.code}</code>
                      </pre>
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* Next Steps */}
            <div className="mt-6 bg-white dark:bg-gray-900 rounded-xl p-6 shadow-lg">
              <h3 className="text-lg font-bold mb-4 text-gray-900 dark:text-white">
                Next Steps
              </h3>
              <div className="grid md:grid-cols-2 gap-4">
                <div className="flex items-start space-x-3">
                  <div className="w-6 h-6 bg-primary-600 text-white rounded-full flex items-center justify-center text-sm font-bold">
                    1
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 dark:text-white mb-1">
                      Set API Key
                    </h4>
                    <p className="text-sm text-gray-600 dark:text-gray-300">
                      Export your API key: <code className="bg-gray-100 dark:bg-gray-800 px-2 py-1 rounded text-xs">export ANTHROPIC_API_KEY=your-key</code>
                    </p>
                  </div>
                </div>
                <div className="flex items-start space-x-3">
                  <div className="w-6 h-6 bg-primary-600 text-white rounded-full flex items-center justify-center text-sm font-bold">
                    2
                  </div>
                  <div>
                    <h4 className="font-semibold text-gray-900 dark:text-white mb-1">
                      Start Coding
                    </h4>
                    <p className="text-sm text-gray-600 dark:text-gray-300">
                      Open Neovim and use <code className="bg-gray-100 dark:bg-gray-800 px-2 py-1 rounded text-xs">:AvanteAsk</code> to get started
                    </p>
                  </div>
                </div>
              </div>

              <div className="mt-6 flex items-center justify-center">
                <a
                  href="https://github.com/yetone/avante.nvim#installation"
                  className="flex items-center space-x-2 text-primary-600 dark:text-primary-400 hover:underline"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <span>View detailed installation guide</span>
                  <ExternalLink className="w-4 h-4" />
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
