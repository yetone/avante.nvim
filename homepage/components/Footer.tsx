import React from 'react';
import { Github, MessageCircle, Heart, ExternalLink } from 'lucide-react';

interface FooterProps {
  translations: any;
}

const Footer: React.FC<FooterProps> = ({ translations }) => {
  const currentYear = new Date().getFullYear();

  const socialLinks = [
    {
      name: 'GitHub',
      href: 'https://github.com/yetone/avante.nvim',
      icon: Github,
    },
    {
      name: 'Discord',
      href: 'https://discord.gg/QfnEFEdSjz',
      icon: MessageCircle,
    },
    {
      name: 'Sponsor',
      href: 'https://patreon.com/yetone',
      icon: Heart,
    },
  ];

  const productLinks = [
    { name: 'Features', href: '#features' },
    { name: 'Installation', href: '#installation' },
    { name: 'Documentation', href: 'https://github.com/yetone/avante.nvim#readme' },
    { name: 'Changelog', href: 'https://github.com/yetone/avante.nvim/releases' },
  ];

  const resourceLinks = [
    { name: 'Troubleshooting', href: 'https://github.com/yetone/avante.nvim#troubleshooting' },
    { name: 'Contributing', href: 'https://github.com/yetone/avante.nvim/blob/main/CONTRIBUTING.md' },
    { name: 'Issues', href: 'https://github.com/yetone/avante.nvim/issues' },
    { name: 'Discussions', href: 'https://github.com/yetone/avante.nvim/discussions' },
  ];

  const handleLinkClick = (href: string) => {
    if (href.startsWith('#')) {
      const element = document.getElementById(href.substring(1));
      if (element) {
        element.scrollIntoView({ behavior: 'smooth' });
      }
    } else {
      window.open(href, '_blank', 'noopener,noreferrer');
    }
  };

  return (
    <footer className="bg-gray-900 text-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-8">
          {/* Logo and Description */}
          <div className="lg:col-span-2">
            <div className="flex items-center space-x-3 mb-4">
              <div className="w-8 h-8 bg-primary-600 rounded-md flex items-center justify-center">
                <span className="text-white font-bold text-sm">A</span>
              </div>
              <span className="text-xl font-bold">avante.nvim</span>
            </div>
            <p className="text-gray-300 leading-relaxed mb-6 max-w-md">
              {translations.footer.description}
            </p>
            <div className="flex space-x-4">
              {socialLinks.map((link) => (
                <button
                  key={link.name}
                  onClick={() => handleLinkClick(link.href)}
                  className="w-10 h-10 bg-gray-800 hover:bg-gray-700 rounded-full flex items-center justify-center transition-colors duration-200"
                  aria-label={link.name}
                >
                  <link.icon className="w-5 h-5" />
                </button>
              ))}
            </div>
          </div>

          {/* Product Links */}
          <div>
            <h3 className="text-lg font-semibold mb-4">{translations.footer.links.product}</h3>
            <ul className="space-y-3">
              {productLinks.map((link) => (
                <li key={link.name}>
                  <button
                    onClick={() => handleLinkClick(link.href)}
                    className="text-gray-300 hover:text-white transition-colors duration-200 flex items-center gap-1"
                  >
                    {link.name}
                    {!link.href.startsWith('#') && <ExternalLink className="w-3 h-3" />}
                  </button>
                </li>
              ))}
            </ul>
          </div>

          {/* Community Links */}
          <div>
            <h3 className="text-lg font-semibold mb-4">{translations.footer.links.community}</h3>
            <ul className="space-y-3">
              <li>
                <button
                  onClick={() => handleLinkClick('https://discord.gg/QfnEFEdSjz')}
                  className="text-gray-300 hover:text-white transition-colors duration-200 flex items-center gap-1"
                >
                  Discord <ExternalLink className="w-3 h-3" />
                </button>
              </li>
              <li>
                <button
                  onClick={() => handleLinkClick('https://github.com/yetone/avante.nvim/discussions')}
                  className="text-gray-300 hover:text-white transition-colors duration-200 flex items-center gap-1"
                >
                  Discussions <ExternalLink className="w-3 h-3" />
                </button>
              </li>
              <li>
                <button
                  onClick={() => handleLinkClick('https://patreon.com/yetone')}
                  className="text-gray-300 hover:text-white transition-colors duration-200 flex items-center gap-1"
                >
                  Sponsor <ExternalLink className="w-3 h-3" />
                </button>
              </li>
            </ul>
          </div>

          {/* Resource Links */}
          <div>
            <h3 className="text-lg font-semibold mb-4">{translations.footer.links.resources}</h3>
            <ul className="space-y-3">
              {resourceLinks.map((link) => (
                <li key={link.name}>
                  <button
                    onClick={() => handleLinkClick(link.href)}
                    className="text-gray-300 hover:text-white transition-colors duration-200 flex items-center gap-1"
                  >
                    {link.name}
                    <ExternalLink className="w-3 h-3" />
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* Bottom Bar */}
        <div className="border-t border-gray-800 mt-12 pt-8 flex flex-col md:flex-row justify-between items-center">
          <div className="text-gray-400 text-sm mb-4 md:mb-0">
            © {currentYear} avante.nvim. {translations.footer.license}
          </div>
          <div className="text-gray-400 text-sm">
            Made with <Heart className="w-4 h-4 inline text-red-500" /> for the Neovim community
          </div>
        </div>
      </div>
    </footer>
  );
};

export default Footer;
