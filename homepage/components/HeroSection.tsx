import { useTranslations } from 'next-intl';
import { getGitHubStats } from '@/lib/github';

export default async function HeroSection() {
  const t = useTranslations('hero');
  const stats = await getGitHubStats();

  return (
    <section id="hero" className="min-h-screen flex items-center justify-center bg-gradient-to-b from-gray-900 via-gray-900 to-gray-800 pt-16">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="max-w-4xl mx-auto text-center">
          {/* GitHub Stats Badge */}
          <div className="flex justify-center items-center space-x-6 mb-8">
            <a
              href="https://github.com/yetone/avante.nvim"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center space-x-2 px-4 py-2 bg-gray-800 rounded-full hover:bg-gray-700 transition-colors"
            >
              <svg className="w-5 h-5 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
                <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
              </svg>
              <span className="text-white font-semibold">{stats.stars.toLocaleString()}</span>
              <span className="text-gray-400">{t('github_stars')}</span>
            </a>
            <div className="px-4 py-2 bg-gray-800 rounded-full">
              <span className="text-gray-400">{t('version')}:</span>
              <span className="text-white font-semibold ml-2">{stats.version}</span>
            </div>
          </div>

          {/* Main Heading */}
          <h1 className="text-5xl sm:text-6xl lg:text-7xl font-bold text-white mb-6 leading-tight">
            {t('tagline')}
          </h1>

          {/* Subtitle */}
          <p className="text-xl sm:text-2xl text-gray-300 mb-12 leading-relaxed">
            {t('subtitle')}
          </p>

          {/* CTA Buttons */}
          <div className="flex flex-col sm:flex-row justify-center items-center space-y-4 sm:space-y-0 sm:space-x-6">
            <a
              href="#installation"
              className="w-full sm:w-auto px-8 py-4 bg-primary-600 hover:bg-primary-700 text-white font-semibold rounded-lg transition-colors shadow-lg hover:shadow-xl text-lg"
              onClick={(e) => {
                e.preventDefault();
                document.getElementById('installation')?.scrollIntoView({ behavior: 'smooth' });
              }}
            >
              {t('cta_primary')}
            </a>
            <a
              href="https://github.com/yetone/avante.nvim#demo"
              target="_blank"
              rel="noopener noreferrer"
              className="w-full sm:w-auto px-8 py-4 bg-gray-800 hover:bg-gray-700 text-white font-semibold rounded-lg transition-colors shadow-lg hover:shadow-xl text-lg border border-gray-700"
            >
              {t('cta_secondary')}
            </a>
          </div>

          {/* Feature Highlights */}
          <div className="mt-16 grid grid-cols-1 sm:grid-cols-3 gap-6 text-left">
            <div className="p-6 bg-gray-800/50 rounded-lg border border-gray-700">
              <div className="text-primary-400 mb-2">
                <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Cursor-like Experience</h3>
              <p className="text-gray-400">Get the same powerful AI assistance you love from Cursor, right in Neovim</p>
            </div>
            <div className="p-6 bg-gray-800/50 rounded-lg border border-gray-700">
              <div className="text-primary-400 mb-2">
                <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Open Source</h3>
              <p className="text-gray-400">Fully open-source and extensible, community-driven development</p>
            </div>
            <div className="p-6 bg-gray-800/50 rounded-lg border border-gray-700">
              <div className="text-primary-400 mb-2">
                <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Multi-Provider</h3>
              <p className="text-gray-400">Support for Claude, OpenAI, Gemini, and more AI providers</p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
