import {
  Zap,
  Brain,
  Code2,
  Terminal,
  Sparkles,
  GitBranch,
  MessageSquare,
  Settings
} from 'lucide-react'

const features = [
  {
    icon: Brain,
    title: 'AI Code Completion',
    description: 'Intelligent code suggestions powered by advanced language models, understanding your context and coding patterns.',
    highlight: 'Smart & Context-Aware'
  },
  {
    icon: Zap,
    title: 'One-Click Application',
    description: 'Apply AI suggestions directly to your code with a single command, streamlining your development workflow.',
    highlight: 'Instant Integration'
  },
  {
    icon: Terminal,
    title: 'Native Neovim Integration',
    description: 'Built specifically for Neovim with seamless integration into your existing terminal-based workflow.',
    highlight: 'Terminal Native'
  },
  {
    icon: Code2,
    title: 'Multi-Language Support',
    description: 'Works with all programming languages supported by Neovim, with syntax-aware suggestions.',
    highlight: 'Universal Support'
  },
  {
    icon: Settings,
    title: 'Project-Specific Instructions',
    description: 'Customize AI behavior with project-specific instruction files (avante.md) for tailored assistance.',
    highlight: 'Highly Customizable'
  },
  {
    icon: Sparkles,
    title: 'Advanced AI Features',
    description: 'Chat with your codebase, edit selected blocks, and get intelligent refactoring suggestions.',
    highlight: 'Next-Gen Features'
  }
]

const comparisonData = [
  {
    feature: 'Terminal Integration',
    avante: true,
    cursor: false,
    traditional: false
  },
  {
    feature: 'Neovim Compatibility',
    avante: true,
    cursor: false,
    traditional: 'limited'
  },
  {
    feature: 'Open Source',
    avante: true,
    cursor: false,
    traditional: 'mixed'
  },
  {
    feature: 'Customization',
    avante: 'unlimited',
    cursor: 'limited',
    traditional: 'limited'
  },
  {
    feature: 'AI-Powered',
    avante: true,
    cursor: true,
    traditional: false
  }
]

const StatusIcon = ({ status }: { status: boolean | string }) => {
  if (status === true || status === 'unlimited') {
    return <span className="text-green-500 text-xl">✓</span>
  }
  if (status === false) {
    return <span className="text-red-500 text-xl">✗</span>
  }
  if (status === 'limited' || status === 'mixed') {
    return <span className="text-yellow-500 text-xl">◐</span>
  }
  return <span className="text-gray-400">-</span>
}

export function FeaturesSection() {
  return (
    <section id="features" className="section-padding bg-white dark:bg-gray-900">
      <div className="container-max-w">
        {/* Section Header */}
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold mb-6 text-gray-900 dark:text-white">
            Powerful Features for
            <span className="text-primary-600 dark:text-primary-400"> Modern Development</span>
          </h2>
          <p className="text-xl text-gray-600 dark:text-gray-300 max-w-3xl mx-auto">
            avante.nvim brings the power of AI-assisted coding to your terminal,
            combining the flexibility of Neovim with intelligent code suggestions.
          </p>
        </div>

        {/* Features Grid */}
        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8 mb-20">
          {features.map((feature, index) => {
            const Icon = feature.icon
            return (
              <div key={index} className="feature-card group hover:scale-105">
                <div className="flex items-center mb-4">
                  <div className="w-12 h-12 bg-primary-100 dark:bg-primary-900/30 rounded-lg flex items-center justify-center mr-4 group-hover:scale-110 transition-transform">
                    <Icon className="w-6 h-6 text-primary-600 dark:text-primary-400" />
                  </div>
                  <div>
                    <h3 className="text-xl font-semibold mb-1 text-gray-900 dark:text-white">
                      {feature.title}
                    </h3>
                    <span className="text-sm text-primary-600 dark:text-primary-400 font-medium">
                      {feature.highlight}
                    </span>
                  </div>
                </div>
                <p className="text-gray-600 dark:text-gray-300 leading-relaxed">
                  {feature.description}
                </p>
              </div>
            )
          })}
        </div>

        {/* Comparison Table */}
        <div className="bg-gray-50 dark:bg-gray-800 rounded-2xl p-8">
          <div className="text-center mb-8">
            <h3 className="text-3xl font-bold mb-4 text-gray-900 dark:text-white">
              Why Choose avante.nvim?
            </h3>
            <p className="text-lg text-gray-600 dark:text-gray-300">
              See how avante.nvim compares to other AI coding tools
            </p>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-gray-200 dark:border-gray-700">
                  <th className="text-left py-4 px-6 text-lg font-semibold text-gray-900 dark:text-white">
                    Feature
                  </th>
                  <th className="text-center py-4 px-6 text-lg font-semibold text-primary-600 dark:text-primary-400">
                    avante.nvim
                  </th>
                  <th className="text-center py-4 px-6 text-lg font-semibold text-gray-600 dark:text-gray-400">
                    Cursor IDE
                  </th>
                  <th className="text-center py-4 px-6 text-lg font-semibold text-gray-600 dark:text-gray-400">
                    Traditional IDEs
                  </th>
                </tr>
              </thead>
              <tbody>
                {comparisonData.map((row, index) => (
                  <tr key={index} className="border-b border-gray-200 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-700/50 transition-colors">
                    <td className="py-4 px-6 font-medium text-gray-900 dark:text-white">
                      {row.feature}
                    </td>
                    <td className="py-4 px-6 text-center">
                      <StatusIcon status={row.avante} />
                    </td>
                    <td className="py-4 px-6 text-center">
                      <StatusIcon status={row.cursor} />
                    </td>
                    <td className="py-4 px-6 text-center">
                      <StatusIcon status={row.traditional} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  )
}
