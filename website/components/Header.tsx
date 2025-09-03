'use client'

import { useState } from 'react'
import { Menu, X, Github, MessageCircle } from 'lucide-react'
import Link from 'next/link'

export function Header() {
  const [isMenuOpen, setIsMenuOpen] = useState(false)

  return (
    <header className="fixed top-0 left-0 right-0 z-50 bg-white/80 dark:bg-gray-900/80 backdrop-blur-md border-b border-gray-200 dark:border-gray-700">
      <nav className="container-max-w">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <div className="flex items-center space-x-2">
            <div className="w-8 h-8 bg-primary-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-sm">A</span>
            </div>
            <span className="font-bold text-xl text-gray-900 dark:text-white">avante.nvim</span>
          </div>

          {/* Desktop Navigation */}
          <div className="hidden md:flex items-center space-x-8">
            <Link href="#features" className="text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors">
              Features
            </Link>
            <Link href="#installation" className="text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors">
              Installation
            </Link>
            <Link href="#community" className="text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors">
              Community
            </Link>
            <Link href="https://github.com/yetone/avante.nvim" className="text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors">
              Docs
            </Link>
          </div>

          {/* CTA Buttons */}
          <div className="hidden md:flex items-center space-x-4">
            <Link 
              href="https://discord.gg/QfnEFEdSjz" 
              className="flex items-center space-x-2 text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors"
            >
              <MessageCircle className="w-5 h-5" />
              <span>Discord</span>
            </Link>
            <Link 
              href="https://github.com/yetone/avante.nvim" 
              className="flex items-center space-x-2 btn-primary"
            >
              <Github className="w-5 h-5" />
              <span>GitHub</span>
            </Link>
          </div>

          {/* Mobile menu button */}
          <button
            onClick={() => setIsMenuOpen(!isMenuOpen)}
            className="md:hidden p-2"
            aria-label="Toggle menu"
          >
            {isMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
          </button>
        </div>

        {/* Mobile Navigation */}
        {isMenuOpen && (
          <div className="md:hidden py-4 border-t border-gray-200 dark:border-gray-700">
            <div className="flex flex-col space-y-4">
              <Link href="#features" className="text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors">
                Features
              </Link>
              <Link href="#installation" className="text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors">
                Installation
              </Link>
              <Link href="#community" className="text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors">
                Community
              </Link>
              <Link href="https://github.com/yetone/avante.nvim" className="text-gray-600 hover:text-primary-600 dark:text-gray-300 dark:hover:text-primary-400 transition-colors">
                Docs
              </Link>
              <div className="flex items-center space-x-4 pt-4">
                <Link 
                  href="https://discord.gg/QfnEFEdSjz" 
                  className="flex items-center space-x-2 btn-secondary flex-1 justify-center"
                >
                  <MessageCircle className="w-5 h-5" />
                  <span>Discord</span>
                </Link>
                <Link 
                  href="https://github.com/yetone/avante.nvim" 
                  className="flex items-center space-x-2 btn-primary flex-1 justify-center"
                >
                  <Github className="w-5 h-5" />
                  <span>GitHub</span>
                </Link>
              </div>
            </div>
          </div>
        )}
      </nav>
    </header>
  )
}