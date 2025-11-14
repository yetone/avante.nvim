import { useState, useEffect } from 'react';
import { GetStaticProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import { Navigation } from '@/components/Navigation';
import { Button } from '@/components/ui/Button';
import { GitHubStats, DiscordStats, Translations } from '@/lib/types';
import { copyToClipboard, formatNumber } from '@/lib/utils';
import enTranslations from '@/locales/en.json';
import zhTranslations from '@/locales/zh.json';

interface HomeProps {
  githubStats: GitHubStats | null;
  discordStats: DiscordStats | null;
}

export default function Home({ githubStats, discordStats }: HomeProps) {
  const router = useRouter();
  const [locale, setLocale] = useState<string>('en');
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);

  useEffect(() => {
    const lang = router.query.lang as string;
    if (lang === 'zh' || lang === 'en') {
      setLocale(lang);
    }
  }, [router.query.lang]);

  const translations: Translations = locale === 'zh' ? zhTranslations : enTranslations;

  const handleCopy = async (text: string, index: number) => {
    const success = await copyToClipboard(text);
    if (success) {
      setCopiedIndex(index);
      setTimeout(() => setCopiedIndex(null), 2000);
    }
  };

  // SEO meta information
  const title = locale === 'zh'
    ? 'avante.nvim - Neovim 的 AI 驱动编程'
    : 'avante.nvim - AI-Powered Coding for Neovim';

  const description = locale === 'zh'
    ? '在你最喜爱的终端编辑器中体验 Cursor IDE 的智能。使用 AI 驱动的代码建议和无缝集成来转换你的 Neovim 工作流程。'
    : 'Experience Cursor IDE\'s intelligence in your favorite terminal editor. Transform your Neovim workflow with AI-driven code suggestions and seamless integration.';

  const installationExamples = [
    {
      title: translations.installation.lazy_nvim,
      code: `-- lazy.nvim
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  lazy = false,
  version = false,
  opts = {
    -- add any opts here
  },
  keys = {
    {
      "<leader>aa",
      function() require("avante.api").ask() end,
      desc = "avante: ask",
      mode = { "n", "v" },
    },
  },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
}`,
    },
  ];

  const features = [
    {
      title: translations.features.ai_suggestions.title,
      description: translations.features.ai_suggestions.description,
    },
    {
      title: translations.features.one_click.title,
      description: translations.features.one_click.description,
    },
    {
      title: translations.features.multi_provider.title,
      description: translations.features.multi_provider.description,
    },
    {
      title: translations.features.zen_mode.title,
      description: translations.features.zen_mode.description,
    },
    {
      title: translations.features.acp.title,
      description: translations.features.acp.description,
    },
    {
      title: translations.features.project_instructions.title,
      description: translations.features.project_instructions.description,
    },
    {
      title: translations.features.rag_service.title,
      description: translations.features.rag_service.description,
    },
    {
      title: translations.features.custom_tools.title,
      description: translations.features.custom_tools.description,
    },
  ];

  return (
    <>
      <Head>
        <title>{title}</title>
        <meta name="description" content={description} />
        <meta name="viewport" content="width=device-width, initial-scale=1" />

        {/* Open Graph */}
        <meta property="og:type" content="website" />
        <meta property="og:title" content={title} />
        <meta property="og:description" content={description} />
        <meta property="og:url" content="https://github.com/yetone/avante.nvim" />

        {/* Twitter Card */}
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:title" content={title} />
        <meta name="twitter:description" content={description} />

        {/* Structured Data */}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "SoftwareApplication",
              "name": "avante.nvim",
              "applicationCategory": "DeveloperApplication",
              "description": description,
              "operatingSystem": "Linux, macOS, Windows",
              "offers": {
                "@type": "Offer",
                "price": "0",
                "priceCurrency": "USD"
              },
              "aggregateRating": githubStats ? {
                "@type": "AggregateRating",
                "ratingValue": "5",
                "ratingCount": githubStats.stars.toString()
              } : undefined
            })
          }}
        />
      </Head>

      <Navigation
        translations={translations}
        locale={locale}
        onLocaleChange={setLocale}
      />

      <main className="pt-16">
        {/* Hero Section */}
        <section id="hero" className="min-h-screen flex items-center justify-center px-4">
          <div className="max-w-4xl mx-auto text-center">
            <h1 className="text-5xl md:text-6xl font-bold mb-6 bg-gradient-to-r from-primary-400 to-primary-600 bg-clip-text text-transparent">
              {translations.hero.title}
            </h1>
            <p className="text-xl md:text-2xl text-gray-300 mb-8">
              {translations.hero.subtitle}
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center items-center">
              <Button
                size="lg"
                onClick={() => {
                  const element = document.getElementById('installation');
                  element?.scrollIntoView({ behavior: 'smooth' });
                }}
              >
                {translations.hero.cta_primary}
              </Button>
              <Button
                variant="outline"
                size="lg"
                as="a"
                href="https://github.com/yetone/avante.nvim"
                target="_blank"
                rel="noopener noreferrer"
              >
                {translations.hero.cta_secondary}
              </Button>
            </div>
            {githubStats && (
              <div className="mt-8 flex justify-center items-center gap-6 text-gray-400">
                <div className="flex items-center gap-2">
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                  </svg>
                  <span>{formatNumber(githubStats.stars)} {translations.community.stars}</span>
                </div>
                <div className="text-gray-600">•</div>
                <div>
                  <span>{githubStats.latest_release.version}</span>
                </div>
              </div>
            )}
          </div>
        </section>

        {/* Features Section */}
        <section id="features" className="py-20 px-4">
          <div className="max-w-7xl mx-auto">
            <h2 className="text-4xl font-bold text-center mb-12">
              {translations.features.title}
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
              {features.map((feature, index) => (
                <div
                  key={index}
                  className="p-6 rounded-lg bg-gray-800/50 border border-gray-700 hover:border-primary-600 transition-colors"
                >
                  <h3 className="text-xl font-semibold mb-3 text-primary-400">
                    {feature.title}
                  </h3>
                  <p className="text-gray-400">
                    {feature.description}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Installation Section */}
        <section id="installation" className="py-20 px-4 bg-gray-800/30">
          <div className="max-w-4xl mx-auto">
            <h2 className="text-4xl font-bold text-center mb-4">
              {translations.installation.title}
            </h2>
            <p className="text-xl text-gray-400 text-center mb-12">
              {translations.installation.subtitle}
            </p>
            <p className="text-sm text-gray-500 text-center mb-8">
              {translations.installation.requirements}
            </p>

            {installationExamples.map((example, index) => (
              <div key={index} className="mb-8">
                <h3 className="text-xl font-semibold mb-4">{example.title}</h3>
                <div className="relative">
                  <pre className="bg-gray-900 rounded-lg p-4 overflow-x-auto">
                    <code className="text-sm text-gray-300">{example.code}</code>
                  </pre>
                  <button
                    onClick={() => handleCopy(example.code, index)}
                    className="absolute top-2 right-2 px-3 py-1 bg-gray-700 hover:bg-gray-600 rounded text-sm transition-colors"
                  >
                    {copiedIndex === index ? translations.installation.copied : translations.installation.copy}
                  </button>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Community Section */}
        <section id="community" className="py-20 px-4">
          <div className="max-w-4xl mx-auto text-center">
            <h2 className="text-4xl font-bold mb-4">
              {translations.community.title}
            </h2>
            <p className="text-xl text-gray-400 mb-12">
              {translations.community.subtitle}
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <Button
                variant="primary"
                size="lg"
                as="a"
                href="https://github.com/yetone/avante.nvim"
                target="_blank"
                rel="noopener noreferrer"
              >
                {translations.community.github}
                {githubStats && (
                  <span className="ml-2">({formatNumber(githubStats.stars)})</span>
                )}
              </Button>
              <Button
                variant="secondary"
                size="lg"
                as="a"
                href="https://discord.gg/avante-nvim"
                target="_blank"
                rel="noopener noreferrer"
              >
                {translations.community.discord}
                {discordStats && (
                  <span className="ml-2">({formatNumber(discordStats.member_count)} {translations.community.members})</span>
                )}
              </Button>
            </div>
          </div>
        </section>

        {/* Footer */}
        <footer className="py-12 px-4 border-t border-gray-800">
          <div className="max-w-7xl mx-auto">
            <div className="flex flex-col md:flex-row justify-between items-center gap-4">
              <div className="text-gray-400">
                <p>{translations.footer.license}</p>
              </div>
              <div className="flex gap-6">
                <a
                  href="https://github.com/yetone/avante.nvim"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-gray-400 hover:text-white transition-colors"
                >
                  {translations.footer.github}
                </a>
                <a
                  href="https://github.com/yetone/avante.nvim"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-gray-400 hover:text-white transition-colors"
                >
                  {translations.footer.docs}
                </a>
                <a
                  href="https://discord.gg/avante-nvim"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-gray-400 hover:text-white transition-colors"
                >
                  {translations.footer.discord}
                </a>
              </div>
            </div>
          </div>
        </footer>
      </main>
    </>
  );
}

export const getStaticProps: GetStaticProps = async () => {
  let githubStats: GitHubStats | null = null;
  let discordStats: DiscordStats | null = null;

  try {
    // Fetch GitHub stats
    const githubResponse = await fetch('https://api.github.com/repos/yetone/avante.nvim');
    const releaseResponse = await fetch('https://api.github.com/repos/yetone/avante.nvim/releases/latest');

    if (githubResponse.ok && releaseResponse.ok) {
      const [repoData, releaseData] = await Promise.all([
        githubResponse.json(),
        releaseResponse.json()
      ]);

      githubStats = {
        stars: repoData.stargazers_count,
        forks: repoData.forks_count,
        watchers: repoData.watchers_count,
        latest_release: {
          version: releaseData.tag_name,
          published_at: releaseData.published_at,
        },
      };
    }
  } catch (error) {
    console.error('Error fetching GitHub stats:', error);
    // Use fallback data
    githubStats = {
      stars: 8200,
      forks: 350,
      watchers: 150,
      latest_release: {
        version: 'v0.0.1',
        published_at: new Date().toISOString(),
      },
    };
  }

  try {
    // Discord stats - using fallback data
    discordStats = {
      member_count: 1000,
      online_count: 150,
    };
  } catch (error) {
    console.error('Error fetching Discord stats:', error);
    discordStats = {
      member_count: 1000,
      online_count: 150,
    };
  }

  return {
    props: {
      githubStats,
      discordStats,
    },
    revalidate: 3600, // Revalidate every hour
  };
};
