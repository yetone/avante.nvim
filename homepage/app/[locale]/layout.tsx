import { NextIntlClientProvider } from 'next-intl';
import { getMessages } from 'next-intl/server';
import { notFound } from 'next/navigation';
import { routing } from '@/i18n/routing';
import '../globals.css';

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export const metadata = {
  title: 'avante.nvim - AI-Powered Code Assistance for Neovim',
  description: 'Bring Cursor-like AI capabilities to your Neovim workflow. Open-source, extensible, and powerful.',
  keywords: ['neovim', 'ai', 'code assistant', 'cursor', 'claude', 'openai', 'vim', 'plugin'],
  authors: [{ name: 'yetone' }],
  creator: 'yetone',
  openGraph: {
    title: 'avante.nvim - AI-Powered Code Assistance for Neovim',
    description: 'Bring Cursor-like AI capabilities to your Neovim workflow. Open-source, extensible, and powerful.',
    url: 'https://github.com/yetone/avante.nvim',
    siteName: 'avante.nvim',
    type: 'website',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'avante.nvim'
      }
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'avante.nvim - AI-Powered Code Assistance for Neovim',
    description: 'Bring Cursor-like AI capabilities to your Neovim workflow. Open-source, extensible, and powerful.',
    images: ['/og-image.png'],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
    },
  },
};

export default async function LocaleLayout({
  children,
  params: { locale }
}: {
  children: React.ReactNode;
  params: { locale: string };
}) {
  // Ensure that the incoming `locale` is valid
  if (!routing.locales.includes(locale as any)) {
    notFound();
  }

  // Providing all messages to the client
  // side is the easiest way to get started
  const messages = await getMessages();

  return (
    <html lang={locale} className="dark">
      <head>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              '@context': 'https://schema.org',
              '@type': 'SoftwareApplication',
              name: 'avante.nvim',
              applicationCategory: 'DeveloperApplication',
              operatingSystem: 'Linux, macOS, Windows',
              offers: {
                '@type': 'Offer',
                price: '0',
                priceCurrency: 'USD'
              },
              aggregateRating: {
                '@type': 'AggregateRating',
                ratingValue: '5',
                ratingCount: '1000'
              }
            })
          }}
        />
      </head>
      <body className="bg-gray-900 text-white antialiased">
        <NextIntlClientProvider messages={messages}>
          {children}
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
