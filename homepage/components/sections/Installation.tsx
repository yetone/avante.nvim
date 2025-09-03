import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { Copy, Check, AlertCircle, ChevronRight } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/Card';
import Button from '@/components/ui/Button';
import { copyToClipboard } from '@/lib/utils';

interface InstallationProps {
  translations: any;
}

const Installation: React.FC<InstallationProps> = ({ translations }) => {
  const [activeTab, setActiveTab] = useState('lazy');
  const [copiedStates, setCopiedStates] = useState<Record<string, boolean>>({});

  const handleCopy = async (text: string, id: string) => {
    const success = await copyToClipboard(text);
    if (success) {
      setCopiedStates(prev => ({ ...prev, [id]: true }));
      setTimeout(() => {
        setCopiedStates(prev => ({ ...prev, [id]: false }));
      }, 2000);
    }
  };

  const installConfigs = {
    lazy: {
      name: 'lazy.nvim',
      code: `{
  "yetone/avante.nvim",
  event = "VeryLazy",
  lazy = false,
  version = false,
  opts = {
    -- add any opts here
  },
  build = function()
    require("avante.repo_map").setup()
  end,
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
      -- Make sure to set this up properly if you have lazy=true
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { "markdown", "Avante" },
      },
      ft = { "markdown", "Avante" },
    },
  },
}`,
    },
    packer: {
      name: 'packer.nvim',
      code: `use {
  "yetone/avante.nvim",
  config = function()
    require("avante").setup({
      -- add any opts here
    })
  end,
  requires = {
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons",
    "zbirenbaum/copilot.lua",
    {
      "HakonHarnes/img-clip.nvim",
      config = function()
        require("img-clip").setup({
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            use_absolute_path = true,
          },
        })
      end,
    },
    {
      'MeanderingProgrammer/render-markdown.nvim',
      config = function()
        require('render-markdown').setup({
          file_types = { "markdown", "Avante" },
        })
      end,
    },
  },
}`,
    },
    vimplug: {
      name: 'vim-plug',
      code: `Plug 'stevearc/dressing.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'zbirenbaum/copilot.lua'
Plug 'HakonHarnes/img-clip.nvim'
Plug 'MeanderingProgrammer/render-markdown.nvim'
Plug 'yetone/avante.nvim'

" Add this to your init.vim after plugin installation
lua << EOF
require("avante").setup({
  -- add any opts here
})
EOF`,
    },
    manual: {
      name: 'Manual Installation',
      code: `# Clone the repository
git clone https://github.com/yetone/avante.nvim.git ~/.local/share/nvim/site/pack/avante/start/avante.nvim

# Clone dependencies
git clone https://github.com/stevearc/dressing.nvim.git ~/.local/share/nvim/site/pack/avante/start/dressing.nvim
git clone https://github.com/nvim-lua/plenary.nvim.git ~/.local/share/nvim/site/pack/avante/start/plenary.nvim
git clone https://github.com/MunifTanjim/nui.nvim.git ~/.local/share/nvim/site/pack/avante/start/nui.nvim

# Add to your init.lua
require("avante").setup({
  -- add any opts here
})`,
    },
  };

  const steps = [
    {
      title: translations.installation.step1,
      description: 'Add the plugin configuration to your Neovim setup',
    },
    {
      title: translations.installation.step2,
      description: 'Restart Neovim and install the plugin',
    },
    {
      title: translations.installation.step3,
      description: 'Configure your AI provider and API keys',
    },
  ];

  const providerConfig = `-- Configure your AI provider
require("avante").setup({
  provider = "claude", -- or "openai", "azure", "copilot"
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-haiku-20240307",
    temperature = 0,
    max_tokens = 4096,
  },
  mappings = {
    ask = "<leader>aa", -- ask
    edit = "<leader>ae", -- edit
    refresh = "<leader>ar", -- refresh
  },
})`;

  return (
    <section id="installation" className="py-20 bg-gray-50 dark:bg-gray-800">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Section Header */}
        <motion.div
          className="text-center mb-16"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
          viewport={{ once: true }}
        >
          <h2 className="text-3xl md:text-4xl lg:text-5xl font-bold text-gray-900 dark:text-white mb-4">
            {translations.installation.title}
          </h2>
          <p className="text-xl text-gray-600 dark:text-gray-300 max-w-3xl mx-auto">
            {translations.installation.subtitle}
          </p>
        </motion.div>

        {/* Prerequisites */}
        <motion.div
          className="mb-12"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.2 }}
          viewport={{ once: true }}
        >
          <Card className="border-orange-200 dark:border-orange-700 bg-orange-50 dark:bg-orange-900/20">
            <CardHeader>
              <div className="flex items-center gap-3">
                <AlertCircle className="w-5 h-5 text-orange-600 dark:text-orange-400" />
                <CardTitle className="text-orange-900 dark:text-orange-100">
                  {translations.installation.prerequisites}
                </CardTitle>
              </div>
            </CardHeader>
            <CardContent>
              <p className="text-orange-800 dark:text-orange-200">
                {translations.installation.prerequisites_text}
              </p>
            </CardContent>
          </Card>
        </motion.div>

        {/* Installation Steps */}
        <motion.div
          className="mb-12"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.4 }}
          viewport={{ once: true }}
        >
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {steps.map((step, index) => (
              <div key={index} className="flex items-start gap-4">
                <div className="flex-shrink-0 w-8 h-8 bg-primary-600 text-white rounded-full flex items-center justify-center text-sm font-bold">
                  {index + 1}
                </div>
                <div>
                  <h3 className="font-semibold text-gray-900 dark:text-white mb-2">
                    {step.title}
                  </h3>
                  <p className="text-gray-600 dark:text-gray-400 text-sm">
                    {step.description}
                  </p>
                </div>
                {index < steps.length - 1 && (
                  <ChevronRight className="hidden md:block w-5 h-5 text-gray-400 mt-1" />
                )}
              </div>
            ))}
          </div>
        </motion.div>

        {/* Plugin Manager Tabs */}
        <motion.div
          className="mb-8"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.6 }}
          viewport={{ once: true }}
        >
          <div className="text-center mb-6">
            <h3 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
              {translations.installation.choose_manager}
            </h3>
          </div>

          <div className="flex flex-wrap justify-center gap-2 mb-8">
            {Object.entries(installConfigs).map(([key, config]) => (
              <Button
                key={key}
                variant={activeTab === key ? 'primary' : 'outline'}
                onClick={() => setActiveTab(key)}
                className="min-w-0"
              >
                {config.name}
              </Button>
            ))}
          </div>

          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle>{installConfigs[activeTab as keyof typeof installConfigs].name}</CardTitle>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => handleCopy(installConfigs[activeTab as keyof typeof installConfigs].code, activeTab)}
                  className="flex items-center gap-2"
                >
                  {copiedStates[activeTab] ? (
                    <>
                      <Check className="w-4 h-4" />
                      {translations.installation.copy_success}
                    </>
                  ) : (
                    <>
                      <Copy className="w-4 h-4" />
                      {translations.installation.copy_button}
                    </>
                  )}
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              <div className="bg-gray-900 rounded-lg p-4 overflow-x-auto">
                <pre className="text-green-400 text-sm leading-relaxed">
                  <code>{installConfigs[activeTab as keyof typeof installConfigs].code}</code>
                </pre>
              </div>
            </CardContent>
          </Card>
        </motion.div>

        {/* Provider Configuration */}
        <motion.div
          className="mb-8"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.8 }}
          viewport={{ once: true }}
        >
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle>AI Provider Configuration</CardTitle>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => handleCopy(providerConfig, 'provider')}
                  className="flex items-center gap-2"
                >
                  {copiedStates.provider ? (
                    <>
                      <Check className="w-4 h-4" />
                      {translations.installation.copy_success}
                    </>
                  ) : (
                    <>
                      <Copy className="w-4 h-4" />
                      {translations.installation.copy_button}
                    </>
                  )}
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              <div className="bg-gray-900 rounded-lg p-4 overflow-x-auto">
                <pre className="text-green-400 text-sm leading-relaxed">
                  <code>{providerConfig}</code>
                </pre>
              </div>
            </CardContent>
          </Card>
        </motion.div>

        {/* Troubleshooting */}
        <motion.div
          className="text-center"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 1 }}
          viewport={{ once: true }}
        >
          <p className="text-gray-600 dark:text-gray-400">
            {translations.installation.troubleshooting}{' '}
            <a
              href="https://github.com/yetone/avante.nvim#troubleshooting"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary-600 dark:text-primary-400 hover:underline"
            >
              Check our troubleshooting guide
            </a>
          </p>
        </motion.div>
      </div>
    </section>
  );
};

export default Installation;