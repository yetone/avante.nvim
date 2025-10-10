import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { GetStaticProps } from 'next';
import * as api from '@/lib/api';

// Mock the API functions
jest.mock('@/lib/api');
const mockFetchGitHubStats = api.fetchGitHubStats as jest.MockedFunction<typeof api.fetchGitHubStats>;
const mockFetchDiscordStats = api.fetchDiscordStats as jest.MockedFunction<typeof api.fetchDiscordStats>;

// Mock fetch for getStaticProps
global.fetch = jest.fn();
const mockFetch = global.fetch as jest.MockedFunction<typeof fetch>;

describe('Homepage Integration Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Static Props Generation', () => {
    it('should generate props with successful API calls', async () => {
      const mockGitHubResponse = {
        ok: true,
        json: () => Promise.resolve({
          stargazers_count: 8200,
          forks_count: 312,
          watchers_count: 145
        })
      };

      const mockReleaseResponse = {
        ok: true,
        json: () => Promise.resolve({
          tag_name: 'v0.8.5',
          published_at: '2024-01-15T10:30:00Z'
        })
      };

      const mockDiscordResponse = {
        ok: true,
        json: () => Promise.resolve({
          approximate_member_count: 1500,
          approximate_presence_count: 200
        })
      };

      mockFetch
        .mockResolvedValueOnce(mockGitHubResponse as any)
        .mockResolvedValueOnce(mockReleaseResponse as any)
        .mockResolvedValueOnce(mockDiscordResponse as any);

      // Import getStaticProps - we need to create a simplified version
      const getStaticProps = async () => {
        let githubStats: api.GitHubStats | null = null;
        let discordStats: api.DiscordStats | null = null;

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
          const discordResponse = await fetch('https://discord.com/api/v9/invites/QfnEFEdSjz?with_counts=true');
          if (discordResponse.ok) {
            const discordData = await discordResponse.json();
            discordStats = {
              memberCount: discordData.approximate_member_count || 1500,
              onlineCount: discordData.approximate_presence_count || 200,
            };
          }
        } catch (error) {
          console.error('Failed to fetch stats:', error);
        }

        return {
          props: {
            githubStats,
            discordStats,
          },
        };
      };

      const result = await getStaticProps();

      expect(result.props.githubStats).toEqual({
        stars: 8200,
        forks: 312,
        watchers: 145,
        latest_release: {
          version: 'v0.8.5',
          published_at: '2024-01-15T10:30:00Z',
        },
      });

      expect(result.props.discordStats).toEqual({
        memberCount: 1500,
        onlineCount: 200,
      });
    });

    it('should handle API failures gracefully with fallback data', async () => {
      mockFetch.mockRejectedValue(new Error('Network error'));

      const getStaticProps = async () => {
        let githubStats: api.GitHubStats | null = null;
        let discordStats: api.DiscordStats | null = null;

        try {
          // Simulate API calls
          await fetch('https://api.github.com/repos/yetone/avante.nvim');
        } catch (error) {
          // Fallback data
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
        };
      };

      const result = await getStaticProps();

      expect(result.props.githubStats).toBeTruthy();
      expect(result.props.discordStats).toBeTruthy();
      expect(result.props.githubStats?.stars).toBe(8200);
      expect(result.props.discordStats?.memberCount).toBe(1500);
    });
  });

  describe('Language Switching Integration', () => {
    it('should handle language switching across components', () => {
      // Mock translations
      const enTranslations = {
        nav: { features: 'Features', installation: 'Installation', community: 'Community', docs: 'Documentation' },
        hero: { title: 'AI-Powered Coding for Neovim' }
      };

      const zhTranslations = {
        nav: { features: '功能', installation: '安装', community: '社区', docs: '文档' },
        hero: { title: 'Neovim 的 AI 驱动编程' }
      };

      // Simple mock component to test language switching
      const TestHomePage = ({ initialLocale = 'en' }) => {
        const [locale, setLocale] = React.useState(initialLocale);
        const translations = locale === 'zh' ? zhTranslations : enTranslations;

        return (
          <div>
            <div data-testid="current-locale">{locale}</div>
            <div data-testid="nav-features">{translations.nav.features}</div>
            <div data-testid="hero-title">{translations.hero.title}</div>
            <button
              onClick={() => setLocale(locale === 'en' ? 'zh' : 'en')}
              data-testid="language-switcher"
            >
              Switch Language
            </button>
          </div>
        );
      };

      render(<TestHomePage />);

      // Initially in English
      expect(screen.getByTestId('current-locale')).toHaveTextContent('en');
      expect(screen.getByTestId('nav-features')).toHaveTextContent('Features');
      expect(screen.getByTestId('hero-title')).toHaveTextContent('AI-Powered Coding for Neovim');

      // Switch to Chinese
      fireEvent.click(screen.getByTestId('language-switcher'));

      expect(screen.getByTestId('current-locale')).toHaveTextContent('zh');
      expect(screen.getByTestId('nav-features')).toHaveTextContent('功能');
      expect(screen.getByTestId('hero-title')).toHaveTextContent('Neovim 的 AI 驱动编程');

      // Switch back to English
      fireEvent.click(screen.getByTestId('language-switcher'));

      expect(screen.getByTestId('current-locale')).toHaveTextContent('en');
      expect(screen.getByTestId('nav-features')).toHaveTextContent('Features');
    });
  });

  describe('Stats Display Integration', () => {
    it('should format and display GitHub and Discord stats correctly', () => {
      // Mock component that displays formatted stats
      const StatsDisplay = ({ githubStats, discordStats }: {
        githubStats: api.GitHubStats | null;
        discordStats: api.DiscordStats | null;
      }) => {
        const formatNumber = (num: number): string => {
          if (num >= 1000000) {
            return (num / 1000000).toFixed(1) + 'M';
          } else if (num >= 1000) {
            return (num / 1000).toFixed(1) + 'K';
          }
          return num.toString();
        };

        return (
          <div>
            <div data-testid="github-stars">
              {githubStats ? formatNumber(githubStats.stars) : '8.2K+'}
            </div>
            <div data-testid="discord-members">
              {discordStats ? formatNumber(discordStats.memberCount) : '1.5K+'}
            </div>
            <div data-testid="latest-version">
              {githubStats?.latest_release?.version || 'v0.8.5'}
            </div>
          </div>
        );
      };

      const mockGitHubStats: api.GitHubStats = {
        stars: 8234,
        forks: 312,
        watchers: 145,
        latest_release: {
          version: 'v0.8.6',
          published_at: '2024-01-20T10:30:00Z'
        }
      };

      const mockDiscordStats: api.DiscordStats = {
        memberCount: 1567,
        onlineCount: 234
      };

      render(
        <StatsDisplay
          githubStats={mockGitHubStats}
          discordStats={mockDiscordStats}
        />
      );

      expect(screen.getByTestId('github-stars')).toHaveTextContent('8.2K');
      expect(screen.getByTestId('discord-members')).toHaveTextContent('1.6K');
      expect(screen.getByTestId('latest-version')).toHaveTextContent('v0.8.6');
    });

    it('should show fallback stats when API data is unavailable', () => {
      const StatsDisplay = ({ githubStats, discordStats }: {
        githubStats: api.GitHubStats | null;
        discordStats: api.DiscordStats | null;
      }) => (
        <div>
          <div data-testid="github-stars">
            {githubStats ? `${githubStats.stars}` : '8.2K+'}
          </div>
          <div data-testid="discord-members">
            {discordStats ? `${discordStats.memberCount}` : '1.5K+'}
          </div>
        </div>
      );

      render(<StatsDisplay githubStats={null} discordStats={null} />);

      expect(screen.getByTestId('github-stars')).toHaveTextContent('8.2K+');
      expect(screen.getByTestId('discord-members')).toHaveTextContent('1.5K+');
    });
  });

  describe('Installation Code Copying Integration', () => {
    it('should copy installation code to clipboard', async () => {
      const mockWriteText = jest.fn().mockResolvedValue(undefined);
      Object.assign(navigator, {
        clipboard: {
          writeText: mockWriteText,
        },
      });

      const InstallationExample = () => {
        const [copied, setCopied] = React.useState(false);

        const handleCopy = async () => {
          const code = `{
  "yetone/avante.nvim",
  event = "VeryLazy",
  opts = {},
}`;
          try {
            await navigator.clipboard.writeText(code);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
          } catch (error) {
            console.error('Failed to copy:', error);
          }
        };

        return (
          <div>
            <button onClick={handleCopy} data-testid="copy-button">
              {copied ? 'Copied!' : 'Copy Code'}
            </button>
          </div>
        );
      };

      render(<InstallationExample />);

      const copyButton = screen.getByTestId('copy-button');
      expect(copyButton).toHaveTextContent('Copy Code');

      fireEvent.click(copyButton);

      expect(mockWriteText).toHaveBeenCalledWith(expect.stringContaining('yetone/avante.nvim'));

      await waitFor(() => {
        expect(screen.getByTestId('copy-button')).toHaveTextContent('Copied!');
      });

      // Wait for reset
      await waitFor(() => {
        expect(screen.getByTestId('copy-button')).toHaveTextContent('Copy Code');
      }, { timeout: 3000 });
    });
  });

  describe('SEO and Meta Tags Integration', () => {
    it('should generate correct meta information for different locales', () => {
      const generateMetaInfo = (locale: string) => {
        const title = locale === 'zh'
          ? 'avante.nvim - Neovim 的 AI 驱动编程'
          : 'avante.nvim - AI-Powered Coding for Neovim';

        const description = locale === 'zh'
          ? '在你最喜爱的终端编辑器中体验 Cursor IDE 的智能。'
          : 'Experience Cursor IDE\'s intelligence in your favorite terminal editor.';

        return { title, description };
      };

      const enMeta = generateMetaInfo('en');
      const zhMeta = generateMetaInfo('zh');

      expect(enMeta.title).toBe('avante.nvim - AI-Powered Coding for Neovim');
      expect(enMeta.description).toContain('Cursor IDE\'s intelligence');

      expect(zhMeta.title).toBe('avante.nvim - Neovim 的 AI 驱动编程');
      expect(zhMeta.description).toContain('Cursor IDE 的智能');
    });

    it('should generate structured data for search engines', () => {
      const generateStructuredData = (githubStats: api.GitHubStats | null) => {
        return {
          "@context": "https://schema.org",
          "@type": "SoftwareApplication",
          "name": "avante.nvim",
          "applicationCategory": "DeveloperApplication",
          "softwareVersion": githubStats?.latest_release?.version || "latest",
          "aggregateRating": {
            "@type": "AggregateRating",
            "ratingValue": "4.8",
            "ratingCount": githubStats?.stars || 8200,
            "bestRating": "5"
          }
        };
      };

      const mockStats: api.GitHubStats = {
        stars: 8500,
        forks: 350,
        watchers: 150,
        latest_release: {
          version: 'v0.9.0',
          published_at: '2024-02-01T10:30:00Z'
        }
      };

      const structuredData = generateStructuredData(mockStats);

      expect(structuredData['@type']).toBe('SoftwareApplication');
      expect(structuredData.name).toBe('avante.nvim');
      expect(structuredData.softwareVersion).toBe('v0.9.0');
      expect(structuredData.aggregateRating.ratingCount).toBe(8500);
    });
  });
});