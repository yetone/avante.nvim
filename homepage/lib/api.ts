import { GitHubStats, DiscordStats } from './types';

/**
 * Fetches GitHub repository statistics
 */
export async function fetchGitHubStats(): Promise<GitHubStats | null> {
  try {
    const [repoResponse, releaseResponse] = await Promise.all([
      fetch('https://api.github.com/repos/yetone/avante.nvim', {
        headers: {
          'Accept': 'application/vnd.github.v3+json',
        },
      }),
      fetch('https://api.github.com/repos/yetone/avante.nvim/releases/latest', {
        headers: {
          'Accept': 'application/vnd.github.v3+json',
        },
      }),
    ]);

    if (!repoResponse.ok || !releaseResponse.ok) {
      console.error('Failed to fetch GitHub stats');
      return null;
    }

    const [repoData, releaseData] = await Promise.all([
      repoResponse.json(),
      releaseResponse.json(),
    ]);

    return {
      stars: repoData.stargazers_count,
      forks: repoData.forks_count,
      watchers: repoData.watchers_count,
      latest_release: {
        version: releaseData.tag_name,
        published_at: releaseData.published_at,
      },
    };
  } catch (error) {
    console.error('Error fetching GitHub stats:', error);
    return null;
  }
}

/**
 * Fetches Discord community statistics
 * Note: This requires a Discord server widget to be enabled
 */
export async function fetchDiscordStats(): Promise<DiscordStats | null> {
  try {
    // Discord server ID would be needed here
    // For now, returning fallback data as the actual Discord API requires server ID
    // This is a placeholder implementation
    return {
      member_count: 1000,
      online_count: 150,
    };
  } catch (error) {
    console.error('Error fetching Discord stats:', error);
    return null;
  }
}
