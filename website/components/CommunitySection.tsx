'use client'

import { useState, useEffect } from 'react'
import {
  MessageCircle,
  Github,
  Heart,
  Star,
  Users,
  ExternalLink,
  GitFork,
  Eye
} from 'lucide-react'

// Mock data - in a real implementation, these would come from APIs
const mockStats = {
  github: {
    stars: 8250,
    forks: 312,
    watchers: 145
  },
  discord: {
    members: 1200
  }
}

const testimonials = [
  {
    name: "Sarah Chen",
    role: "Senior Developer at TechCorp",
    avatar: "SC",
    content: "avante.nvim has revolutionized my coding workflow. The AI suggestions are incredibly accurate and the Neovim integration is seamless.",
    rating: 5
  },
  {
    name: "Marcus Rodriguez",
    role: "Full Stack Engineer",
    avatar: "MR",
    content: "Finally, AI-powered coding in my favorite editor! The context awareness is impressive and it actually understands what I'm trying to build.",
    rating: 5
  },
  {
    name: "Yuki Tanaka",
    role: "Open Source Contributor",
    avatar: "YT",
    content: "The project-specific instructions feature is a game changer. I can customize the AI behavior for each of my projects perfectly.",
    rating: 5
  }
]

const communityLinks = [
  {
    icon: Github,
    title: "GitHub Repository",
    description: "Star the project, report issues, and contribute",
    link: "https://github.com/yetone/avante.nvim",
    stats: `${mockStats.github.stars.toLocaleString()} stars`,
    color: "text-gray-900 dark:text-white"
  },
  {
    icon: MessageCircle,
    title: "Discord Community",
    description: "Get help, share tips, and connect with other users",
    link: "https://discord.gg/QfnEFEdSjz",
    stats: `${mockStats.discord.members.toLocaleString()} members`,
    color: "text-blue-600"
  },
  {
    icon: Heart,
    title: "Sponsor on Patreon",
    description: "Support the development and get early access to features",
    link: "https://patreon.com/yetone",
    stats: "Support development",
    color: "text-pink-600"
  }
]

export function CommunitySection() {
  const [currentTestimonial, setCurrentTestimonial] = useState(0)

  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentTestimonial((prev) => (prev + 1) % testimonials.length)
    }, 5000)
    return () => clearInterval(interval)
  }, [])

  return (
    <section id="community" className="section-padding bg-white dark:bg-gray-900">
      <div className="container-max-w">
        {/* Section Header */}
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold mb-6 text-gray-900 dark:text-white">
            Join Our
            <span className="text-primary-600 dark:text-primary-400"> Community</span>
          </h2>
          <p className="text-xl text-gray-600 dark:text-gray-300 max-w-3xl mx-auto">
            Connect with developers worldwide, get support, and help shape the future of AI-powered coding in Neovim.
          </p>
        </div>

        {/* Community Stats */}
        <div className="grid md:grid-cols-3 gap-8 mb-16">
          {communityLinks.map((link, index) => {
            const Icon = link.icon
            return (
              <a
                key={index}
                href={link.link}
                target="_blank"
                rel="noopener noreferrer"
                className="feature-card group hover:scale-105"
              >
                <div className="flex items-center mb-4">
                  <div className={`w-12 h-12 rounded-lg flex items-center justify-center mr-4 group-hover:scale-110 transition-transform ${
                    link.color === "text-gray-900 dark:text-white" ? "bg-gray-100 dark:bg-gray-800" :
                    link.color === "text-blue-600" ? "bg-blue-100 dark:bg-blue-900/30" :
                    "bg-pink-100 dark:bg-pink-900/30"
                  }`}>
                    <Icon className={`w-6 h-6 ${link.color}`} />
                  </div>
                  <div className="flex-1">
                    <h3 className="text-xl font-semibold mb-1 text-gray-900 dark:text-white flex items-center">
                      {link.title}
                      <ExternalLink className="w-4 h-4 ml-2 opacity-50" />
                    </h3>
                    <span className={`text-sm font-medium ${link.color}`}>
                      {link.stats}
                    </span>
                  </div>
                </div>
                <p className="text-gray-600 dark:text-gray-300">
                  {link.description}
                </p>
              </a>
            )
          })}
        </div>

        {/* Testimonials */}
        <div className="bg-gray-50 dark:bg-gray-800 rounded-2xl p-8 mb-16">
          <div className="text-center mb-8">
            <h3 className="text-3xl font-bold mb-4 text-gray-900 dark:text-white">
              What Developers Say
            </h3>
            <p className="text-lg text-gray-600 dark:text-gray-300">
              Real feedback from our community members
            </p>
          </div>

          <div className="max-w-4xl mx-auto">
            <div className="relative">
              {testimonials.map((testimonial, index) => (
                <div
                  key={index}
                  className={`transition-all duration-500 ${
                    index === currentTestimonial
                      ? 'opacity-100 translate-x-0'
                      : 'opacity-0 absolute top-0 left-0 right-0 translate-x-4'
                  }`}
                >
                  <div className="bg-white dark:bg-gray-900 rounded-xl p-8 shadow-lg">
                    <div className="flex items-center mb-6">
                      <div className="w-12 h-12 bg-primary-600 rounded-full flex items-center justify-center mr-4">
                        <span className="text-white font-bold">
                          {testimonial.avatar}
                        </span>
                      </div>
                      <div>
                        <h4 className="font-semibold text-gray-900 dark:text-white">
                          {testimonial.name}
                        </h4>
                        <p className="text-sm text-gray-500 dark:text-gray-400">
                          {testimonial.role}
                        </p>
                      </div>
                    </div>

                    <p className="text-lg text-gray-700 dark:text-gray-300 mb-4 italic">
                      &quot;{testimonial.content}&quot;
                    </p>

                    <div className="flex items-center">
                      {[...Array(testimonial.rating)].map((_, i) => (
                        <Star key={i} className="w-5 h-5 text-yellow-400 fill-current" />
                      ))}
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {/* Testimonial dots */}
            <div className="flex justify-center mt-6 space-x-2">
              {testimonials.map((_, index) => (
                <button
                  key={index}
                  onClick={() => setCurrentTestimonial(index)}
                  className={`w-3 h-3 rounded-full transition-colors ${
                    index === currentTestimonial
                      ? 'bg-primary-600'
                      : 'bg-gray-300 dark:bg-gray-600'
                  }`}
                />
              ))}
            </div>
          </div>
        </div>

        {/* GitHub Stats */}
        <div className="bg-gradient-to-r from-gray-900 to-gray-800 rounded-2xl p-8 text-white">
          <div className="text-center mb-8">
            <h3 className="text-3xl font-bold mb-4">Open Source & Growing</h3>
            <p className="text-gray-300 text-lg">
              Join thousands of developers contributing to the future of AI-powered coding
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8 text-center">
            <div className="flex flex-col items-center">
              <div className="w-16 h-16 bg-yellow-600 rounded-full flex items-center justify-center mb-4">
                <Star className="w-8 h-8" />
              </div>
              <div className="text-3xl font-bold mb-2">{mockStats.github.stars.toLocaleString()}</div>
              <div className="text-gray-300">GitHub Stars</div>
            </div>

            <div className="flex flex-col items-center">
              <div className="w-16 h-16 bg-blue-600 rounded-full flex items-center justify-center mb-4">
                <GitFork className="w-8 h-8" />
              </div>
              <div className="text-3xl font-bold mb-2">{mockStats.github.forks.toLocaleString()}</div>
              <div className="text-gray-300">Forks</div>
            </div>

            <div className="flex flex-col items-center">
              <div className="w-16 h-16 bg-green-600 rounded-full flex items-center justify-center mb-4">
                <Users className="w-8 h-8" />
              </div>
              <div className="text-3xl font-bold mb-2">{mockStats.discord.members.toLocaleString()}</div>
              <div className="text-gray-300">Community Members</div>
            </div>
          </div>

          <div className="text-center mt-8">
            <a
              href="https://github.com/yetone/avante.nvim"
              className="btn-primary inline-flex items-center space-x-2"
              target="_blank"
              rel="noopener noreferrer"
            >
              <Github className="w-5 h-5" />
              <span>Star on GitHub</span>
            </a>
          </div>
        </div>
      </div>
    </section>
  )
}
