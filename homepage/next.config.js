/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  i18n: {
    locales: ['en', 'zh'],
    defaultLocale: 'en',
  },
  images: {
    domains: ['github.com', 'img.shields.io', 'github.user-attachments.assets'],
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'github.com',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: 'img.shields.io',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: 'github.user-attachments.assets',
        pathname: '/**',
      },
    ],
  },
  output: 'export',
  trailingSlash: true,
  assetPrefix: process.env.NODE_ENV === 'production' ? '/avante.nvim' : '',
  basePath: process.env.NODE_ENV === 'production' ? '/avante.nvim' : '',
};

module.exports = nextConfig;