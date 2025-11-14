import React, { useState } from 'react';
import { useRouter } from 'next/router';
import { Translations } from '@/lib/types';

interface NavigationProps {
  translations: Translations;
  locale: string;
  onLocaleChange: (locale: string) => void;
}

/**
 * Navigation component with language switching and mobile menu support
 */
export function Navigation({ translations, locale, onLocaleChange }: NavigationProps) {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();

  const handleLanguageChange = (newLocale: string) => {
    onLocaleChange(newLocale);
    router.push(`${router.pathname}?lang=${newLocale}`, undefined, { shallow: true });
  };

  const scrollToSection = (sectionId: string) => {
    const element = document.getElementById(sectionId);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth' });
    }
    setIsOpen(false);
  };

  const navItems = [
    { key: 'home', section: 'hero' },
    { key: 'features', section: 'features' },
    { key: 'installation', section: 'installation' },
    { key: 'community', section: 'community' },
  ];

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-gray-900/95 backdrop-blur-sm border-b border-gray-800">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo and Title */}
          <div className="flex items-center">
            <button
              onClick={() => scrollToSection('hero')}
              className="flex items-center space-x-2 text-white font-bold text-xl hover:text-primary-400 transition-colors"
            >
              <span>avante.nvim</span>
            </button>
          </div>

          {/* Desktop Navigation */}
          <div className="hidden md:flex items-center space-x-8">
            {navItems.map((item) => (
              <button
                key={item.key}
                onClick={() => scrollToSection(item.section)}
                className="text-gray-300 hover:text-white transition-colors"
              >
                {translations.nav[item.key as keyof typeof translations.nav]}
              </button>
            ))}
            <a
              href="https://github.com/yetone/avante.nvim"
              target="_blank"
              rel="noopener noreferrer"
              className="text-gray-300 hover:text-white transition-colors"
            >
              {translations.nav.docs}
            </a>

            {/* Language Switcher */}
            <button
              onClick={() => handleLanguageChange(locale === 'en' ? 'zh' : 'en')}
              className="px-3 py-1 rounded border border-gray-600 text-gray-300 hover:text-white hover:border-gray-500 transition-colors text-sm"
            >
              {locale === 'en' ? '中文' : 'English'}
            </button>
          </div>

          {/* Mobile Menu Button */}
          <div className="md:hidden">
            <button
              onClick={() => setIsOpen(!isOpen)}
              className="text-gray-300 hover:text-white focus:outline-none"
              aria-label="Toggle menu"
            >
              <svg
                className="h-6 w-6"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                {isOpen ? (
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M6 18L18 6M6 6l12 12"
                  />
                ) : (
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M4 6h16M4 12h16M4 18h16"
                  />
                )}
              </svg>
            </button>
          </div>
        </div>

        {/* Mobile Menu */}
        {isOpen && (
          <div className="md:hidden pb-4">
            {navItems.map((item) => (
              <button
                key={item.key}
                onClick={() => scrollToSection(item.section)}
                className="block w-full text-left py-2 text-gray-300 hover:text-white transition-colors"
              >
                {translations.nav[item.key as keyof typeof translations.nav]}
              </button>
            ))}
            <a
              href="https://github.com/yetone/avante.nvim"
              target="_blank"
              rel="noopener noreferrer"
              className="block py-2 text-gray-300 hover:text-white transition-colors"
            >
              {translations.nav.docs}
            </a>
            <button
              onClick={() => handleLanguageChange(locale === 'en' ? 'zh' : 'en')}
              className="mt-2 px-3 py-1 rounded border border-gray-600 text-gray-300 hover:text-white hover:border-gray-500 transition-colors text-sm"
            >
              {locale === 'en' ? '中文' : 'English'}
            </button>
          </div>
        )}
      </div>
    </nav>
  );
}
