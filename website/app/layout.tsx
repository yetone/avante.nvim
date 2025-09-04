import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'avante.nvim - AI-Powered Coding for Neovim',
  description: 'Experience Cursor IDE\'s intelligence in your favorite terminal editor. AI-powered code assistance for Neovim with seamless integration and powerful features.',
  keywords: ['Neovim', 'AI', 'Code Assistant', 'Cursor IDE', 'Terminal Editor', 'Programming'],
  authors: [{ name: 'avante.nvim Team' }],
  openGraph: {
    title: 'avante.nvim - AI-Powered Coding for Neovim',
    description: 'Experience Cursor IDE\'s intelligence in your favorite terminal editor',
    type: 'website',
    locale: 'en_US',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'avante.nvim - AI-Powered Coding for Neovim',
    description: 'Experience Cursor IDE\'s intelligence in your favorite terminal editor',
  },
  robots: {
    index: true,
    follow: true,
  }
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className="h-full">
      <body className={`${inter.className} h-full antialiased`}>
        {children}
      </body>
    </html>
  )
}
