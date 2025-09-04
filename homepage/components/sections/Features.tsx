import React from 'react';
import { motion } from 'framer-motion';
import { Brain, Code, Terminal, Lock, Zap, Globe, Settings, Heart } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/Card';

interface FeaturesProps {
  translations: any;
}

const Features: React.FC<FeaturesProps> = ({ translations }) => {
  const features = [
    {
      icon: Brain,
      title: translations.features.ai_completion.title,
      description: translations.features.ai_completion.description,
      color: 'text-blue-600 dark:text-blue-400',
      bgColor: 'bg-blue-100 dark:bg-blue-900/30',
    },
    {
      icon: Code,
      title: translations.features.cursor_like.title,
      description: translations.features.cursor_like.description,
      color: 'text-purple-600 dark:text-purple-400',
      bgColor: 'bg-purple-100 dark:bg-purple-900/30',
    },
    {
      icon: Terminal,
      title: translations.features.terminal_native.title,
      description: translations.features.terminal_native.description,
      color: 'text-green-600 dark:text-green-400',
      bgColor: 'bg-green-100 dark:bg-green-900/30',
    },
    {
      icon: Lock,
      title: translations.features.open_source.title,
      description: translations.features.open_source.description,
      color: 'text-orange-600 dark:text-orange-400',
      bgColor: 'bg-orange-100 dark:bg-orange-900/30',
    },
  ];

  const comparisonData = [
    {
      feature: translations.comparison.terminal_integration,
      avante: translations.comparison.native,
      cursor: translations.comparison.separate,
      traditional: translations.comparison.separate,
    },
    {
      feature: translations.comparison.neovim_compatibility,
      avante: translations.comparison.native,
      cursor: translations.comparison.none,
      traditional: translations.comparison.limited,
    },
    {
      feature: translations.comparison.open_source,
      avante: translations.comparison.mit,
      cursor: translations.comparison.proprietary,
      traditional: translations.comparison.mixed,
    },
    {
      feature: translations.comparison.customization,
      avante: translations.comparison.unlimited,
      cursor: translations.comparison.limited,
      traditional: translations.comparison.limited,
    },
  ];

  return (
    <section id="features" className="py-20 bg-white dark:bg-gray-900">
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
            {translations.features.title}
          </h2>
          <p className="text-xl text-gray-600 dark:text-gray-300 max-w-3xl mx-auto">
            {translations.features.subtitle}
          </p>
        </motion.div>

        {/* Features Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8 mb-20">
          {features.map((feature, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: index * 0.1 }}
              viewport={{ once: true }}
            >
              <Card className="h-full hover:shadow-lg transition-shadow duration-300">
                <CardHeader className="text-center">
                  <div className={`w-16 h-16 mx-auto rounded-full ${feature.bgColor} flex items-center justify-center mb-4`}>
                    <feature.icon className={`w-8 h-8 ${feature.color}`} />
                  </div>
                  <CardTitle className="text-xl mb-2">{feature.title}</CardTitle>
                  <CardDescription className="text-base leading-relaxed">
                    {feature.description}
                  </CardDescription>
                </CardHeader>
              </Card>
            </motion.div>
          ))}
        </div>

        {/* Code Example */}
        <motion.div
          className="mb-20"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
          viewport={{ once: true }}
        >
          <div className="bg-gray-900 rounded-lg p-6 overflow-x-auto">
            <div className="flex items-center justify-between mb-4">
              <div className="flex space-x-2">
                <div className="w-3 h-3 bg-red-500 rounded-full"></div>
                <div className="w-3 h-3 bg-yellow-500 rounded-full"></div>
                <div className="w-3 h-3 bg-green-500 rounded-full"></div>
              </div>
              <span className="text-gray-400 text-sm">init.lua</span>
            </div>
            <pre className="text-green-400 text-sm leading-relaxed">
              <code>{`{
  "yetone/avante.nvim",
  event = "VeryLazy",
  lazy = false,
  version = false,
  opts = {
    -- AI provider configuration
    provider = "claude",
    behaviour = {
      auto_suggestions = true,
      auto_set_highlight_group = true,
      auto_set_keymaps = true,
    },
  },
  dependencies = {
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    -- AI completion engine
    {
      "HakonHarnes/img-clip.nvim",
      event = "VeryLazy",
      opts = {
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
        },
      },
    },
  },
}`}</code>
            </pre>
          </div>
        </motion.div>

        {/* Comparison Table */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
          viewport={{ once: true }}
        >
          <div className="text-center mb-12">
            <h3 className="text-2xl md:text-3xl font-bold text-gray-900 dark:text-white mb-4">
              {translations.comparison.title}
            </h3>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full bg-white dark:bg-gray-800 rounded-lg shadow-lg overflow-hidden">
              <thead className="bg-gray-50 dark:bg-gray-700">
                <tr>
                  <th className="px-6 py-4 text-left text-sm font-semibold text-gray-900 dark:text-white">
                    {translations.comparison.feature}
                  </th>
                  <th className="px-6 py-4 text-center text-sm font-semibold text-primary-600 dark:text-primary-400">
                    {translations.comparison.avante}
                  </th>
                  <th className="px-6 py-4 text-center text-sm font-semibold text-gray-900 dark:text-white">
                    {translations.comparison.cursor}
                  </th>
                  <th className="px-6 py-4 text-center text-sm font-semibold text-gray-900 dark:text-white">
                    {translations.comparison.traditional}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200 dark:divide-gray-600">
                {comparisonData.map((row, index) => (
                  <tr key={index} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-6 py-4 text-sm font-medium text-gray-900 dark:text-white">
                      {row.feature}
                    </td>
                    <td className="px-6 py-4 text-sm text-center text-primary-600 dark:text-primary-400 font-medium">
                      {row.avante}
                    </td>
                    <td className="px-6 py-4 text-sm text-center text-gray-600 dark:text-gray-400">
                      {row.cursor}
                    </td>
                    <td className="px-6 py-4 text-sm text-center text-gray-600 dark:text-gray-400">
                      {row.traditional}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </motion.div>
      </div>
    </section>
  );
};

export default Features;
