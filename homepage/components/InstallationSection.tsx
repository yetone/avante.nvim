'use client';

import { useTranslations } from 'next-intl';
import { useState } from 'react';
import CodeBlock from './CodeBlock';

export default function InstallationSection() {
  const t = useTranslations('installation');
  const [activeTab, setActiveTab] = useState('lazy');

  const installationExamples = {
    lazy: `return {
  "yetone/avante.nvim",
  event = "VeryLazy",
  lazy = false,
  version = false,
  opts = {
    -- add any opts here
  },
  build = "make",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons",
  },
}`,
    packer: `use {
  'yetone/avante.nvim',
  run = 'make',
  requires = {
    'nvim-treesitter/nvim-treesitter',
    'stevearc/dressing.nvim',
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  config = function()
    require('avante').setup({
      -- your config here
    })
  end
}`,
    vimplug: `Plug 'nvim-treesitter/nvim-treesitter'
Plug 'stevearc/dressing.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'yetone/avante.nvim', { 'do': 'make' }

" Then in your init.lua:
" lua require('avante').setup()`,
  };

  return (
    <section id="installation" className="py-20 bg-gray-900">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-12">
          <h2 className="text-4xl sm:text-5xl font-bold text-white mb-4">
            {t('title')}
          </h2>
          <p className="text-xl text-gray-300 mb-6">
            {t('subtitle')}
          </p>
          <p className="text-primary-400 font-semibold">
            {t('requirements')}
          </p>
        </div>

        <div className="max-w-4xl mx-auto">
          {/* Tab Navigation */}
          <div className="flex space-x-2 mb-6 border-b border-gray-700">
            <button
              onClick={() => setActiveTab('lazy')}
              className={`px-6 py-3 font-semibold transition-colors ${
                activeTab === 'lazy'
                  ? 'text-primary-400 border-b-2 border-primary-400'
                  : 'text-gray-400 hover:text-gray-300'
              }`}
            >
              {t('lazy_nvim')}
            </button>
            <button
              onClick={() => setActiveTab('packer')}
              className={`px-6 py-3 font-semibold transition-colors ${
                activeTab === 'packer'
                  ? 'text-primary-400 border-b-2 border-primary-400'
                  : 'text-gray-400 hover:text-gray-300'
              }`}
            >
              {t('packer')}
            </button>
            <button
              onClick={() => setActiveTab('vimplug')}
              className={`px-6 py-3 font-semibold transition-colors ${
                activeTab === 'vimplug'
                  ? 'text-primary-400 border-b-2 border-primary-400'
                  : 'text-gray-400 hover:text-gray-300'
              }`}
            >
              {t('vim_plug')}
            </button>
          </div>

          {/* Code Display */}
          <CodeBlock code={installationExamples[activeTab as keyof typeof installationExamples]} language="lua" />

          {/* Documentation Link */}
          <div className="mt-8 text-center">
            <a
              href="https://github.com/yetone/avante.nvim/blob/main/README.md"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center space-x-2 text-primary-400 hover:text-primary-300 font-semibold transition-colors"
            >
              <span>{t('docs_link')}</span>
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14 5l7 7m0 0l-7 7m7-7H3" />
              </svg>
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
