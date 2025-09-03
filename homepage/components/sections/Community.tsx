import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { MessageCircle, Star, Heart, ExternalLink, Users, GitBranch } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/Card';
import Button from '@/components/ui/Button';
import { formatNumber } from '@/lib/utils';
import { GitHubStats, DiscordStats } from '@/lib/api';

interface CommunityProps {
  translations: any;
  githubStats?: GitHubStats | null;
  discordStats?: DiscordStats | null;
}

const Community: React.FC<CommunityProps> = ({ translations, githubStats, discordStats }) => {
  const testimonials = [
    {
      quote: translations.testimonials.user1.quote,
      author: translations.testimonials.user1.author,
      avatar: "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=100&h=100&q=80",
    },
    {
      quote: translations.testimonials.user2.quote,
      author: translations.testimonials.user2.author,
      avatar: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=100&h=100&q=80",
    },
    {
      quote: translations.testimonials.user3.quote,
      author: translations.testimonials.user3.author,
      avatar: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=100&h=100&q=80",
    },
  ];

  const communityLinks = [
    {
      title: translations.community.discord.title,
      description: translations.community.discord.description,
      icon: MessageCircle,
      color: 'text-purple-600 dark:text-purple-400',
      bgColor: 'bg-purple-100 dark:bg-purple-900/30',
      buttonText: translations.community.discord.join,
      href: 'https://discord.gg/QfnEFEdSjz',
      stat: discordStats ? formatNumber(discordStats.memberCount) : '1.5K+',
      statLabel: translations.community.discord.members,
    },
    {
      title: translations.community.github.title,
      description: translations.community.github.description,
      icon: GitBranch,
      color: 'text-gray-900 dark:text-gray-100',
      bgColor: 'bg-gray-100 dark:bg-gray-700',
      buttonText: translations.community.github.view,
      href: 'https://github.com/yetone/avante.nvim',
      stat: githubStats ? formatNumber(githubStats.stars) : '8.2K+',
      statLabel: translations.community.github.stars,
    },
    {
      title: translations.community.sponsor.title,
      description: translations.community.sponsor.description,
      icon: Heart,
      color: 'text-red-600 dark:text-red-400',
      bgColor: 'bg-red-100 dark:bg-red-900/30',
      buttonText: translations.community.sponsor.sponsor,
      href: 'https://patreon.com/yetone',
      stat: '💝',
      statLabel: 'Support Us',
    },
  ];

  return (
    <section id="community" className="py-20 bg-white dark:bg-gray-900">
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
            {translations.community.title}
          </h2>
          <p className="text-xl text-gray-600 dark:text-gray-300 max-w-3xl mx-auto">
            {translations.community.subtitle}
          </p>
        </motion.div>

        {/* Community Cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mb-20">
          {communityLinks.map((link, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: index * 0.1 }}
              viewport={{ once: true }}
            >
              <Card className="h-full hover:shadow-lg transition-all duration-300 hover:transform hover:scale-105">
                <CardHeader className="text-center pb-4">
                  <div className={`w-16 h-16 mx-auto rounded-full ${link.bgColor} flex items-center justify-center mb-4`}>
                    <link.icon className={`w-8 h-8 ${link.color}`} />
                  </div>
                  <CardTitle className="text-xl mb-2">{link.title}</CardTitle>
                  <CardDescription className="text-base leading-relaxed">
                    {link.description}
                  </CardDescription>
                </CardHeader>
                <CardContent className="text-center">
                  <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4 mb-4">
                    <div className="text-2xl font-bold text-gray-900 dark:text-white mb-1">
                      {link.stat}
                    </div>
                    <div className="text-sm text-gray-600 dark:text-gray-400">
                      {link.statLabel}
                    </div>
                  </div>
                </CardContent>
                <CardFooter>
                  <Button
                    as="a"
                    href={link.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="w-full flex items-center justify-center gap-2"
                  >
                    {link.buttonText}
                    <ExternalLink className="w-4 h-4" />
                  </Button>
                </CardFooter>
              </Card>
            </motion.div>
          ))}
        </div>

        {/* Testimonials */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
          viewport={{ once: true }}
        >
          <div className="text-center mb-12">
            <h3 className="text-2xl md:text-3xl font-bold text-gray-900 dark:text-white mb-4">
              {translations.testimonials.title}
            </h3>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {testimonials.map((testimonial, index) => (
              <motion.div
                key={index}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.8, delay: index * 0.1 }}
                viewport={{ once: true }}
              >
                <Card className="h-full bg-gradient-to-br from-blue-50 to-indigo-50 dark:from-blue-900/20 dark:to-indigo-900/20 border-blue-200 dark:border-blue-800">
                  <CardContent className="pt-6">
                    {/* Quote Icon */}
                    <div className="mb-4">
                      <svg
                        className="w-8 h-8 text-primary-600 dark:text-primary-400"
                        fill="currentColor"
                        viewBox="0 0 32 32"
                      >
                        <path d="M10 8v8c0 4.4-3.6 8-8 8v-2c3.3 0 6-2.7 6-6v-2c-1.1 0-2-.9-2-2V8c0-1.1.9-2 2-2h2c1.1 0 2 .9 2 2zM24 8v8c0 4.4-3.6 8-8 8v-2c3.3 0 6-2.7 6-6v-2c-1.1 0-2-.9-2-2V8c0-1.1.9-2 2-2h2c1.1 0 2 .9 2 2z" />
                      </svg>
                    </div>

                    {/* Quote Text */}
                    <blockquote className="text-gray-700 dark:text-gray-300 mb-6 italic leading-relaxed">
                      "{testimonial.quote}"
                    </blockquote>

                    {/* Author */}
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-full bg-primary-600 flex items-center justify-center text-white font-bold">
                        {testimonial.author.charAt(0)}
                      </div>
                      <div>
                        <div className="font-semibold text-gray-900 dark:text-white">
                          {testimonial.author}
                        </div>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* Call to Action */}
        <motion.div
          className="text-center mt-16"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.4 }}
          viewport={{ once: true }}
        >
          <div className="bg-gradient-to-r from-primary-600 to-indigo-600 rounded-2xl p-8 text-white">
            <h3 className="text-2xl font-bold mb-4">
              Ready to transform your Neovim workflow?
            </h3>
            <p className="text-primary-100 mb-6 max-w-2xl mx-auto">
              Join thousands of developers who have already enhanced their coding experience with AI-powered assistance.
            </p>
            <Button
              variant="secondary"
              size="lg"
              onClick={() => {
                const element = document.getElementById('installation');
                if (element) {
                  element.scrollIntoView({ behavior: 'smooth' });
                }
              }}
              className="bg-white text-primary-600 hover:bg-gray-100"
            >
              Get Started Now
            </Button>
          </div>
        </motion.div>
      </div>
    </section>
  );
};

export default Community;