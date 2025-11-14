<<<<<<< HEAD
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
=======
'use client';

import { useTranslations } from 'next-intl';
import { useState } from 'react';
import { Link as IntlLink } from '@/i18n/routing';
import LanguageSwitcher from './LanguageSwitcher';

export default function Navigation() {
  const t = useTranslations('nav');
  const [isMenuOpen, setIsMenuOpen] = useState(false);
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)

  const scrollToSection = (sectionId: string) => {
    const element = document.getElementById(sectionId);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth' });
<<<<<<< HEAD
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
=======
      setIsMenuOpen(false);
    }
  };

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-gray-900/95 backdrop-blur-sm border-b border-gray-800">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          {/* Logo */}
          <div className="flex-shrink-0">
            <button
              onClick={() => scrollToSection('hero')}
              className="text-xl font-bold text-white hover:text-primary-400 transition-colors"
            >
              avante.nvim
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)
            </button>
          </div>

          {/* Desktop Navigation */}
<<<<<<< HEAD
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
=======
          <div className="hidden md:flex md:items-center md:space-x-8">
            <button
              onClick={() => scrollToSection('features')}
              className="text-gray-300 hover:text-white transition-colors"
            >
              {t('features')}
            </button>
            <button
              onClick={() => scrollToSection('installation')}
              className="text-gray-300 hover:text-white transition-colors"
            >
              {t('installation')}
            </button>
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)
            <a
              href="https://github.com/yetone/avante.nvim"
              target="_blank"
              rel="noopener noreferrer"
              className="text-gray-300 hover:text-white transition-colors"
            >
<<<<<<< HEAD
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
=======
              {t('community')}
            </a>
            <a
              href="https://github.com/yetone/avante.nvim/blob/main/README.md"
              target="_blank"
              rel="noopener noreferrer"
              className="text-gray-300 hover:text-white transition-colors"
            >
              {t('docs')}
            </a>
            <LanguageSwitcher />
          </div>

          {/* Mobile menu button */}
          <div className="md:hidden flex items-center space-x-4">
            <LanguageSwitcher />
            <button
              onClick={() => setIsMenuOpen(!isMenuOpen)}
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)
              className="text-gray-300 hover:text-white focus:outline-none"
              aria-label="Toggle menu"
            >
              <svg
                className="h-6 w-6"
                fill="none"
<<<<<<< HEAD
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
=======
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                {isMenuOpen ? (
                  <path d="M6 18L18 6M6 6l12 12" />
                ) : (
                  <path d="M4 6h16M4 12h16M4 18h16" />
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)
                )}
              </svg>
            </button>
          </div>
        </div>

<<<<<<< HEAD
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
=======
        {/* Mobile menu */}
        {isMenuOpen && (
          <div className="md:hidden pb-4">
            <div className="flex flex-col space-y-4">
              <button
                onClick={() => scrollToSection('features')}
                className="text-gray-300 hover:text-white transition-colors text-left"
              >
                {t('features')}
              </button>
              <button
                onClick={() => scrollToSection('installation')}
                className="text-gray-300 hover:text-white transition-colors text-left"
              >
                {t('installation')}
              </button>
              <a
                href="https://github.com/yetone/avante.nvim"
                target="_blank"
                rel="noopener noreferrer"
                className="text-gray-300 hover:text-white transition-colors"
              >
                {t('community')}
              </a>
              <a
                href="https://github.com/yetone/avante.nvim/blob/main/README.md"
                target="_blank"
                rel="noopener noreferrer"
                className="text-gray-300 hover:text-white transition-colors"
              >
                {t('docs')}
              </a>
            </div>
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)
          </div>
        )}
      </div>
    </nav>
  );
}
