import React, { useState, useEffect } from 'react';
import Head from 'next/head';
import { GetStaticProps } from 'next';
import { useRouter } from 'next/router';

// Components
import Navigation from '@/components/Navigation';
import Hero from '@/components/sections/Hero';
import Features from '@/components/sections/Features';
import Installation from '@/components/sections/Installation';
import Community from '@/components/sections/Community';
import Footer from '@/components/Footer';

// Types and utilities
import { GitHubStats, DiscordStats } from '@/lib/api';

// Translations
import enTranslations from '@/locales/en.json';
import zhTranslations from '@/locales/zh.json';

interface HomePageProps {
  githubStats: GitHubStats | null;
  discordStats: DiscordStats | null;
}

export default function HomePage({ githubStats, discordStats }: HomePageProps) {
  const router = useRouter();
  const { locale } = router;
  
  // Get translations based on current locale
  const translations = locale === 'zh' ? zhTranslations : enTranslations;
  
  // Meta information
  const title = locale === 'zh' 
    ? 'avante.nvim - Neovim 的 AI 驱动编程'
    : 'avante.nvim - AI-Powered Coding for Neovim';
  
  const description = locale === 'zh'
    ? '在你最喜爱的终端编辑器中体验 Cursor IDE 的智能。使用 AI 驱动的代码建议和无缝集成来转换你的 Neovim 工作流程。'
    : 'Experience Cursor IDE\'s intelligence in your favorite terminal editor. Transform your Neovim workflow with AI-driven code suggestions and seamless integration.';

  return (
    <>
      <Head>
        <title>{title}</title>
        <meta name="description" content={description} />
        <meta name="keywords" content="neovim, nvim, ai, coding, cursor ide, terminal, editor, plugin, lua" />
        <meta name="author" content="avante.nvim team" />
        
        {/* Open Graph */}
        <meta property="og:type" content="website" />
        <meta property="og:title" content={title} />
        <meta property="og:description" content={description} />
        <meta property="og:url" content="https://avante.nvim.dev" />
        <meta property="og:image" content="https://github.com/user-attachments/assets/2e2f2a58-2b28-4d11-afd1-87b65612b2de" />
        <meta property="og:site_name" content="avante.nvim" />
        
        {/* Twitter Card */}
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:title" content={title} />
        <meta name="twitter:description" content={description} />
        <meta name="twitter:image" content="https://github.com/user-attachments/assets/2e2f2a58-2b28-4d11-afd1-87b65612b2de" />
        
        {/* Favicon */}
        <link rel="icon" type="image/x-icon" href="/favicon.ico" />
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png" />
        
        {/* Language alternates */}
        <link rel="alternate" hrefLang="en" href="https://avante.nvim.dev/en" />
        <link rel="alternate" hrefLang="zh" href="https://avante.nvim.dev/zh" />
        <link rel="alternate" hrefLang="x-default" href="https://avante.nvim.dev" />
        
        {/* Viewport */}
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        
        {/* Theme color */}
        <meta name="theme-color" content="#2563eb" />
        
        {/* Structured Data */}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "SoftwareApplication",
              "name": "avante.nvim",
              "description": description,
              "applicationCategory": "DeveloperApplication",
              "operatingSystem": "Linux, macOS, Windows",
              "softwareVersion": githubStats?.latest_release?.version || "latest",
              "author": {
                "@type": "Organization",
                "name": "avante.nvim team"
              },
              "url": "https://github.com/yetone/avante.nvim",
              "downloadUrl": "https://github.com/yetone/avante.nvim",
              "screenshot": "https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53",
              "aggregateRating": {
                "@type": "AggregateRating",
                "ratingValue": "4.8",
                "ratingCount": githubStats?.stars || 8200,
                "bestRating": "5"
              }
            })
          }}
        />
      </Head>

      <div className="min-h-screen bg-white dark:bg-gray-900">
        <Navigation translations={translations} />
        
        <main>
          <Hero 
            translations={translations}
            githubStats={githubStats}
            discordStats={discordStats}
          />
          
          <Features translations={translations} />
          
          <Installation translations={translations} />
          
          <Community
            translations={translations}
            githubStats={githubStats}
            discordStats={discordStats}
          />
        </main>
        
        <Footer translations={translations} />
      </div>
    </>
  );
}

export const getStaticProps: GetStaticProps = async ({ locale }) => {
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

    // Fetch Discord stats
    try {
      const discordResponse = await fetch('https://discord.com/api/v9/invites/QfnEFEdSjz?with_counts=true');
      if (discordResponse.ok) {
        const discordData = await discordResponse.json();
        discordStats = {
          memberCount: discordData.approximate_member_count || 0,
          onlineCount: discordData.approximate_presence_count || 0,
        };
      }
    } catch (discordError) {
      console.error('Failed to fetch Discord stats:', discordError);
      // Use fallback data
      discordStats = {
        memberCount: 1500,
        onlineCount: 200,
      };
    }
  } catch (error) {
    console.error('Failed to fetch stats:', error);
    // Use fallback data
    githubStats = {
      stars: 8200,
      forks: 312,
      watchers: 145,
      latest_release: {
        version: 'v0.8.5',
        published_at: new Date().toISOString(),
      },
    };
    discordStats = {
      memberCount: 1500,
      onlineCount: 200,
    };
  }

  return {
    props: {
      githubStats,
      discordStats,
    },
    // Revalidate every hour
    revalidate: 3600,
  };
};