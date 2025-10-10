export interface GitHubStats {
  stars: number;
  forks: number;
  watchers: number;
  latest_release: {
    version: string;
    published_at: string;
  };
}

export interface DiscordStats {
  memberCount: number;
  onlineCount: number;
}

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
      throw new Error('Failed to fetch GitHub data');
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

export async function fetchDiscordStats(): Promise<DiscordStats | null> {
  try {
    // Discord invite API to get approximate member count
    const response = await fetch('https://discord.com/api/v9/invites/QfnEFEdSjz?with_counts=true', {
      headers: {
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error('Failed to fetch Discord data');
    }

    const data = await response.json();

    return {
      memberCount: data.approximate_member_count || 0,
      onlineCount: data.approximate_presence_count || 0,
    };
  } catch (error) {
    console.error('Error fetching Discord stats:', error);
    return null;
  }
}