'use client'

import { useState } from 'react'
import { Play, ChevronDown, Copy, Check } from 'lucide-react'
import Link from 'next/link'

export function HeroSection() {
  const [copied, setCopied] = useState(false)
  const installCommand = 'lazy.nvim: { "yetone/avante.nvim", build = "make", event = "VeryLazy" }'

  const copyToClipboard = async () => {
    await navigator.clipboard.writeText(installCommand)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <section className="pt-32 pb-20 bg-gradient-to-br from-primary-50 via-white to-primary-100 dark:from-gray-900 dark:via-gray-900 dark:to-gray-800">
      <div className="container-max-w">
        <div className="text-center max-w-4xl mx-auto">
          {/* Hero Badge */}
          <div className="inline-flex items-center px-4 py-2 bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300 rounded-full text-sm font-medium mb-8">
            <span className="w-2 h-2 bg-green-500 rounded-full mr-2 animate-pulse"></span>
            Now available for Neovim 0.10+
          </div>

          {/* Main Headline */}
          <h1 className="text-5xl md:text-7xl font-bold mb-6 bg-gradient-to-r from-gray-900 via-primary-600 to-gray-900 dark:from-white dark:via-primary-400 dark:to-white bg-clip-text text-transparent leading-tight">
            AI-Powered Coding for Neovim
          </h1>

          {/* Subheadline */}
          <p className="text-xl md:text-2xl text-gray-600 dark:text-gray-300 mb-8 leading-relaxed">
            Experience <span className="font-semibold text-primary-600 dark:text-primary-400">Cursor IDE&apos;s intelligence</span> in your favorite terminal editor.
            <br className="hidden md:block" />
            AI-driven code suggestions with seamless Neovim integration.
          </p>

          {/* CTA Buttons */}
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-12">
            <Link href="#installation" className="btn-primary text-lg px-8 py-4 w-full sm:w-auto">
              Get Started
            </Link>
            <button className="btn-secondary text-lg px-8 py-4 w-full sm:w-auto flex items-center justify-center space-x-2">
              <Play className="w-5 h-5" />
              <span>Watch Demo</span>
            </button>
          </div>

          {/* Quick Install */}
          <div className="max-w-2xl mx-auto mb-16">
            <p className="text-sm text-gray-500 dark:text-gray-400 mb-3">Quick install with lazy.nvim:</p>
            <div className="bg-gray-900 dark:bg-gray-800 rounded-lg p-4 flex items-center justify-between">
              <code className="text-green-400 font-mono text-sm flex-1 text-left">
                {installCommand}
              </code>
              <button
                onClick={copyToClipboard}
                className="ml-4 p-2 text-gray-400 hover:text-white transition-colors"
                title="Copy to clipboard"
              >
                {copied ? <Check className="w-5 h-5" /> : <Copy className="w-5 h-5" />}
              </button>
            </div>
          </div>

          {/* Demo Video Placeholder */}
          <div className="relative max-w-4xl mx-auto">
            <div className="relative bg-gray-900 rounded-xl overflow-hidden shadow-2xl">
              <div className="aspect-video bg-gradient-to-br from-gray-800 to-gray-900 flex items-center justify-center">
                <div className="text-center">
                  <div className="w-20 h-20 bg-primary-600 rounded-full flex items-center justify-center mx-auto mb-4">
                    <Play className="w-8 h-8 text-white ml-1" />
                  </div>
                  <p className="text-gray-300 text-lg">Interactive Demo Coming Soon</p>
                  <p className="text-gray-500 text-sm mt-2">See avante.nvim in action with real-time AI code suggestions</p>
                </div>
              </div>
              {/* Terminal-like header */}
              <div className="absolute top-0 left-0 right-0 h-8 bg-gray-800 flex items-center px-4">
                <div className="flex space-x-2">
                  <div className="w-3 h-3 bg-red-500 rounded-full"></div>
                  <div className="w-3 h-3 bg-yellow-500 rounded-full"></div>
                  <div className="w-3 h-3 bg-green-500 rounded-full"></div>
                </div>
                <div className="flex-1 text-center">
                  <span className="text-gray-400 text-sm">avante.nvim - AI Assistant</span>
                </div>
              </div>
            </div>

            {/* Floating stats */}
            <div className="absolute -bottom-6 left-1/2 transform -translate-x-1/2">
              <div className="bg-white dark:bg-gray-800 rounded-full px-6 py-3 shadow-lg border border-gray-200 dark:border-gray-700">
                <div className="flex items-center space-x-6 text-sm">
                  <div className="text-center">
                    <div className="font-bold text-primary-600">8.2k+</div>
                    <div className="text-gray-500">GitHub Stars</div>
                  </div>
                  <div className="w-px h-6 bg-gray-300 dark:bg-gray-600"></div>
                  <div className="text-center">
                    <div className="font-bold text-primary-600">1k+</div>
                    <div className="text-gray-500">Discord Members</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Scroll indicator */}
        <div className="text-center mt-20">
          <ChevronDown className="w-6 h-6 text-gray-400 mx-auto animate-bounce" />
        </div>
      </div>
    </section>
  )
}
