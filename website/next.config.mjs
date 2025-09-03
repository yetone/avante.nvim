/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
  images: {
    unoptimized: true
  },
  i18n: {
    locales: ['en', 'zh'],
    defaultLocale: 'en',
    localeDetection: true,
  },
  async generateStaticParams() {
    return [
      { locale: 'en' },
      { locale: 'zh' }
    ]
  }
};

export default nextConfig;