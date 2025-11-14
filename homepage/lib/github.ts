export interface GitHubStats {
  stars: number;
  forks: number;
  watchers: number;
  version: string;
}

export async function getGitHubStats(): Promise<GitHubStats> {
  try {
    const repoResponse = await fetch('https://api.github.com/repos/yetone/avante.nvim', {
      next: { revalidate: 3600 } // Cache for 1 hour
    });

    if (!repoResponse.ok) {
      throw new Error('Failed to fetch GitHub repo data');
    }

    const repoData = await repoResponse.json();

    // Fetch latest release
    const releaseResponse = await fetch('https://api.github.com/repos/yetone/avante.nvim/releases/latest', {
      next: { revalidate: 3600 }
    });

    let version = 'v1.0.0'; // Fallback version
    if (releaseResponse.ok) {
      const releaseData = await releaseResponse.json();
      version = releaseData.tag_name || version;
    }

    return {
      stars: repoData.stargazers_count || 0,
      forks: repoData.forks_count || 0,
      watchers: repoData.watchers_count || 0,
      version: version
    };
  } catch (error) {
    console.error('Error fetching GitHub stats:', error);
    // Return fallback data
    return {
      stars: 5000,
      forks: 300,
      watchers: 100,
      version: 'v1.0.0'
    };
  }
}
