import { Github, MessageCircle, Heart, ExternalLink } from 'lucide-react'
import Link from 'next/link'

const footerLinks = {
  product: [
    { name: 'Features', href: '#features' },
    { name: 'Installation', href: '#installation' },
    { name: 'Documentation', href: 'https://github.com/yetone/avante.nvim#readme' },
    { name: 'Changelog', href: 'https://github.com/yetone/avante.nvim/releases' }
  ],
  community: [
    { name: 'Discord', href: 'https://discord.gg/QfnEFEdSjz' },
    { name: 'GitHub', href: 'https://github.com/yetone/avante.nvim' },
    { name: 'Issues', href: 'https://github.com/yetone/avante.nvim/issues' },
    { name: 'Discussions', href: 'https://github.com/yetone/avante.nvim/discussions' }
  ],
  support: [
    { name: 'Sponsor', href: 'https://patreon.com/yetone' },
    { name: 'Contributing', href: 'https://github.com/yetone/avante.nvim/blob/main/CONTRIBUTING.md' },
    { name: 'License', href: 'https://github.com/yetone/avante.nvim/blob/main/LICENSE' },
    { name: 'Security', href: 'https://github.com/yetone/avante.nvim/security' }
  ]
}

const socialLinks = [
  {
    name: 'GitHub',
    href: 'https://github.com/yetone/avante.nvim',
    icon: Github
  },
  {
    name: 'Discord',
    href: 'https://discord.gg/QfnEFEdSjz',
    icon: MessageCircle
  },
  {
    name: 'Sponsor',
    href: 'https://patreon.com/yetone',
    icon: Heart
  }
]

export function Footer() {
  return (
    <footer className="bg-gray-900 text-white">
      <div className="container-max-w section-padding">
        {/* Main Footer Content */}
        <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8 mb-12">
          {/* Brand Section */}
          <div className="lg:col-span-1">
            <div className="flex items-center space-x-2 mb-4">
              <div className="w-8 h-8 bg-primary-600 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold text-sm">A</span>
              </div>
              <span className="font-bold text-xl">avante.nvim</span>
            </div>
            <p className="text-gray-400 mb-6 leading-relaxed">
              AI-powered coding for Neovim. Experience the future of terminal-based development with intelligent code suggestions and seamless integration.
            </p>
            <div className="flex space-x-4">
              {socialLinks.map((social, index) => {
                const Icon = social.icon
                return (
                  <a
                    key={index}
                    href={social.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="w-10 h-10 bg-gray-800 hover:bg-gray-700 rounded-lg flex items-center justify-center transition-colors group"
                    aria-label={social.name}
                  >
                    <Icon className="w-5 h-5 text-gray-400 group-hover:text-white" />
                  </a>
                )
              })}
            </div>
          </div>

          {/* Product Links */}
          <div>
            <h3 className="font-semibold text-lg mb-4">Product</h3>
            <ul className="space-y-3">
              {footerLinks.product.map((link, index) => (
                <li key={index}>
                  <Link 
                    href={link.href}
                    className="text-gray-400 hover:text-white transition-colors flex items-center"
                  >
                    {link.name}
                    {link.href.startsWith('http') && (
                      <ExternalLink className="w-3 h-3 ml-1 opacity-50" />
                    )}
                  </Link>
                </li>
              ))}
            </ul>
          </div>

          {/* Community Links */}
          <div>
            <h3 className="font-semibold text-lg mb-4">Community</h3>
            <ul className="space-y-3">
              {footerLinks.community.map((link, index) => (
                <li key={index}>
                  <a 
                    href={link.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-gray-400 hover:text-white transition-colors flex items-center"
                  >
                    {link.name}
                    <ExternalLink className="w-3 h-3 ml-1 opacity-50" />
                  </a>
                </li>
              ))}
            </ul>
          </div>

          {/* Support Links */}
          <div>
            <h3 className="font-semibold text-lg mb-4">Support</h3>
            <ul className="space-y-3">
              {footerLinks.support.map((link, index) => (
                <li key={index}>
                  <a 
                    href={link.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-gray-400 hover:text-white transition-colors flex items-center"
                  >
                    {link.name}
                    <ExternalLink className="w-3 h-3 ml-1 opacity-50" />
                  </a>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* Sponsor Section */}
        <div className="border-t border-gray-800 py-8 mb-8">
          <div className="text-center">
            <h3 className="text-lg font-semibold mb-4">Support the Project</h3>
            <p className="text-gray-400 mb-6 max-w-2xl mx-auto">
              avante.nvim is free and open source. Your support helps us maintain and improve the project for the entire community.
            </p>
            <a 
              href="https://patreon.com/yetone"
              target="_blank"
              rel="noopener noreferrer"
              className="btn-primary inline-flex items-center space-x-2"
            >
              <Heart className="w-5 h-5" />
              <span>Become a Sponsor</span>
            </a>
          </div>
        </div>

        {/* Bottom Section */}
        <div className="border-t border-gray-800 pt-8 flex flex-col md:flex-row items-center justify-between space-y-4 md:space-y-0">
          <div className="text-gray-400 text-sm">
            <p>
              © {new Date().getFullYear()} avante.nvim. Released under the{' '}
              <a 
                href="https://github.com/yetone/avante.nvim/blob/main/LICENSE" 
                className="text-primary-400 hover:underline"
                target="_blank"
                rel="noopener noreferrer"
              >
                Apache 2.0 License
              </a>
              .
            </p>
          </div>
          
          <div className="text-gray-400 text-sm">
            <p>
              Made with ❤️ by the{' '}
              <a 
                href="https://github.com/yetone/avante.nvim/graphs/contributors"
                className="text-primary-400 hover:underline"
                target="_blank"
                rel="noopener noreferrer"
              >
                open source community
              </a>
            </p>
          </div>
        </div>
      </div>
    </footer>
  )
}