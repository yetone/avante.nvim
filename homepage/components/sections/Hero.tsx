import React, { useState, useEffect } from 'react';
import { Play, Star, Users, ChevronDown } from 'lucide-react';
import { motion } from 'framer-motion';
import Button from '@/components/ui/Button';
import { formatNumber } from '@/lib/utils';
import { GitHubStats, DiscordStats } from '@/lib/api';

interface HeroProps {
  translations: any;
  githubStats?: GitHubStats | null;
  discordStats?: DiscordStats | null;
}

const Hero: React.FC<HeroProps> = ({ translations, githubStats, discordStats }) => {
  const [currentText, setCurrentText] = useState('');
  const [currentIndex, setCurrentIndex] = useState(0);
  const [isDeleting, setIsDeleting] = useState(false);

  const texts = [
    'AI-powered code completion',
    'Context-aware suggestions',
    'Seamless Neovim integration',
    'Cursor-like experience'
  ];

  useEffect(() => {
    const timeout = setTimeout(() => {
      const current = texts[currentIndex];
      
      if (isDeleting) {
        setCurrentText(current.substring(0, currentText.length - 1));
      } else {
        setCurrentText(current.substring(0, currentText.length + 1));
      }

      if (!isDeleting && currentText === current) {
        setTimeout(() => setIsDeleting(true), 2000);
      } else if (isDeleting && currentText === '') {
        setIsDeleting(false);
        setCurrentIndex((prevIndex) => (prevIndex + 1) % texts.length);
      }
    }, isDeleting ? 50 : 100);

    return () => clearTimeout(timeout);
  }, [currentText, currentIndex, isDeleting, texts]);

  const scrollToInstallation = () => {
    const element = document.getElementById('installation');
    if (element) {
      element.scrollIntoView({ behavior: 'smooth' });
    }
  };

  const openDemo = () => {
    // For now, link to the GitHub repository video
    window.open('https://github.com/yetone/avante.nvim#demo', '_blank');
  };

  return (
    <section className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 via-indigo-50 to-purple-50 dark:from-gray-900 dark:via-blue-900 dark:to-indigo-900">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="text-center">
          {/* Main Title */}
          <motion.h1 
            className="text-4xl sm:text-5xl md:text-6xl lg:text-7xl font-bold text-gray-900 dark:text-white mb-6"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8 }}
          >
            {translations.hero.title}
          </motion.h1>

          {/* Animated Subtitle */}
          <motion.div 
            className="text-xl sm:text-2xl md:text-3xl text-primary-600 dark:text-primary-400 mb-8 h-10"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.2 }}
          >
            <span className="border-r-2 border-primary-600 dark:border-primary-400 animate-typing">
              {currentText}
            </span>
          </motion.div>

          {/* Description */}
          <motion.p 
            className="text-lg sm:text-xl text-gray-600 dark:text-gray-300 mb-12 max-w-4xl mx-auto leading-relaxed"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.4 }}
          >
            {translations.hero.subtitle}
          </motion.p>

          {/* CTA Buttons */}
          <motion.div 
            className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-16"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.6 }}
          >
            <Button
              size="lg"
              onClick={scrollToInstallation}
              className="w-full sm:w-auto px-8 py-4 text-lg"
            >
              {translations.hero.cta_primary}
            </Button>
            <Button
              variant="outline"
              size="lg"
              onClick={openDemo}
              className="w-full sm:w-auto px-8 py-4 text-lg flex items-center gap-2"
            >
              <Play className="w-5 h-5" />
              {translations.hero.cta_secondary}
            </Button>
          </motion.div>

          {/* Stats */}
          <motion.div 
            className="grid grid-cols-1 sm:grid-cols-2 gap-8 max-w-lg mx-auto"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.8 }}
          >
            <div className="flex items-center justify-center gap-3">
              <div className="p-3 bg-yellow-100 dark:bg-yellow-900/30 rounded-full">
                <Star className="w-6 h-6 text-yellow-600 dark:text-yellow-400" />
              </div>
              <div className="text-left">
                <div className="text-2xl font-bold text-gray-900 dark:text-white">
                  {githubStats ? formatNumber(githubStats.stars) : '8.2K+'}
                </div>
                <div className="text-sm text-gray-600 dark:text-gray-400">
                  {translations.hero.github_stars}
                </div>
              </div>
            </div>

            <div className="flex items-center justify-center gap-3">
              <div className="p-3 bg-purple-100 dark:bg-purple-900/30 rounded-full">
                <Users className="w-6 h-6 text-purple-600 dark:text-purple-400" />
              </div>
              <div className="text-left">
                <div className="text-2xl font-bold text-gray-900 dark:text-white">
                  {discordStats ? formatNumber(discordStats.memberCount) : '1.5K+'}
                </div>
                <div className="text-sm text-gray-600 dark:text-gray-400">
                  {translations.hero.discord_members}
                </div>
              </div>
            </div>
          </motion.div>

          {/* Scroll Indicator */}
          <motion.div 
            className="absolute bottom-8 left-1/2 transform -translate-x-1/2"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 1, delay: 1.5 }}
          >
            <motion.div
              animate={{ y: [0, 10, 0] }}
              transition={{ duration: 2, repeat: Infinity }}
            >
              <ChevronDown className="w-6 h-6 text-gray-400" />
            </motion.div>
          </motion.div>
        </div>
      </div>
    </section>
  );
};

export default Hero;