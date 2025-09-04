import React, { useState } from 'react';
import { useRouter } from 'next/router';
import { Menu, X, Globe } from 'lucide-react';
import { cn } from '@/lib/utils';

interface NavigationProps {
  translations: any;
}

const Navigation: React.FC<NavigationProps> = ({ translations }) => {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();
  const { locale, pathname, asPath, query } = router;

  const handleLanguageChange = (newLocale: string) => {
    router.push({ pathname, query }, asPath, { locale: newLocale });
  };

  const scrollToSection = (sectionId: string) => {
    const element = document.getElementById(sectionId);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth' });
    }
    setIsOpen(false);
  };

  const navItems = [
    { key: 'features', label: translations.nav.features },
    { key: 'installation', label: translations.nav.installation },
    { key: 'community', label: translations.nav.community },
  ];

  return (
    <nav className="bg-white/80 backdrop-blur-md border-b border-gray-200 sticky top-0 z-50 dark:bg-gray-900/80 dark:border-gray-700">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          {/* Logo */}
          <div className="flex items-center">
            <div className="flex-shrink-0 flex items-center space-x-3">
              <div className="w-8 h-8 bg-primary-600 rounded-md flex items-center justify-center">
                <span className="text-white font-bold text-sm">A</span>
              </div>
              <span className="text-xl font-bold text-gray-900 dark:text-white">
                avante.nvim
              </span>
            </div>
          </div>

          {/* Desktop Navigation */}
          <div className="hidden md:block">
            <div className="ml-10 flex items-baseline space-x-8">
              {navItems.map((item) => (
                <button
                  key={item.key}
                  onClick={() => scrollToSection(item.key)}
                  className="text-gray-700 hover:text-primary-600 px-3 py-2 text-sm font-medium transition-colors dark:text-gray-300 dark:hover:text-primary-400"
                >
                  {item.label}
                </button>
              ))}
              <a
                href="https://github.com/yetone/avante.nvim"
                target="_blank"
                rel="noopener noreferrer"
                className="text-gray-700 hover:text-primary-600 px-3 py-2 text-sm font-medium transition-colors dark:text-gray-300 dark:hover:text-primary-400"
              >
                {translations.nav.docs}
              </a>
            </div>
          </div>

          {/* Language Switcher & Mobile Menu Button */}
          <div className="flex items-center space-x-4">
            {/* Language Switcher */}
            <div className="relative">
              <button
                onClick={() => handleLanguageChange(locale === 'en' ? 'zh' : 'en')}
                className="flex items-center space-x-1 px-3 py-2 text-sm font-medium text-gray-700 hover:text-primary-600 transition-colors dark:text-gray-300 dark:hover:text-primary-400"
              >
                <Globe className="w-4 h-4" />
                <span>{locale === 'en' ? '中文' : 'EN'}</span>
              </button>
            </div>

            {/* Mobile menu button */}
            <div className="md:hidden">
              <button
                onClick={() => setIsOpen(!isOpen)}
                className="inline-flex items-center justify-center p-2 rounded-md text-gray-700 hover:text-primary-600 hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-primary-500 dark:text-gray-300 dark:hover:text-primary-400 dark:hover:bg-gray-800"
              >
                {isOpen ? (
                  <X className="block h-6 w-6" />
                ) : (
                  <Menu className="block h-6 w-6" />
                )}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Mobile menu */}
      <div className={cn('md:hidden', isOpen ? 'block' : 'hidden')}>
        <div className="px-2 pt-2 pb-3 space-y-1 sm:px-3 bg-white border-t border-gray-200 dark:bg-gray-900 dark:border-gray-700">
          {navItems.map((item) => (
            <button
              key={item.key}
              onClick={() => scrollToSection(item.key)}
              className="text-gray-700 hover:text-primary-600 block px-3 py-2 text-base font-medium w-full text-left transition-colors dark:text-gray-300 dark:hover:text-primary-400"
            >
              {item.label}
            </button>
          ))}
          <a
            href="https://github.com/yetone/avante.nvim"
            target="_blank"
            rel="noopener noreferrer"
            className="text-gray-700 hover:text-primary-600 block px-3 py-2 text-base font-medium transition-colors dark:text-gray-300 dark:hover:text-primary-400"
          >
            {translations.nav.docs}
          </a>
        </div>
      </div>
    </nav>
  );
};

export default Navigation;
