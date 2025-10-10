import { fetchGitHubStats, fetchDiscordStats, GitHubStats, DiscordStats } from '@/lib/api';

// Mock fetch globally
const mockFetch = global.fetch as jest.MockedFunction<typeof fetch>;

describe('API Functions', () => {
  beforeEach(() => {
    mockFetch.mockClear();
  });

  describe('fetchGitHubStats', () => {
    const mockRepoData = {
      stargazers_count: 8200,
      forks_count: 312,
      watchers_count: 145
    };

    const mockReleaseData = {
      tag_name: 'v0.8.5',
      published_at: '2024-01-15T10:30:00Z'
    };

    it('should fetch and return GitHub stats successfully', async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve(mockRepoData)
        } as Response)
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve(mockReleaseData)
        } as Response);

      const result = await fetchGitHubStats();

      expect(result).toEqual({
        stars: 8200,
        forks: 312,
        watchers: 145,
        latest_release: {
          version: 'v0.8.5',
          published_at: '2024-01-15T10:30:00Z'
        }
      });

      expect(mockFetch).toHaveBeenCalledTimes(2);
      expect(mockFetch).toHaveBeenNthCalledWith(1, 'https://api.github.com/repos/yetone/avante.nvim', {
        headers: {
          'Accept': 'application/vnd.github.v3+json',
        },
      });
      expect(mockFetch).toHaveBeenNthCalledWith(2, 'https://api.github.com/repos/yetone/avante.nvim/releases/latest', {
        headers: {
          'Accept': 'application/vnd.github.v3+json',
        },
      });
    });

    it('should return null when repo request fails', async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: false,
          status: 404
        } as Response)
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve(mockReleaseData)
        } as Response);

      const result = await fetchGitHubStats();

      expect(result).toBeNull();
    });

    it('should return null when release request fails', async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve(mockRepoData)
        } as Response)
        .mockResolvedValueOnce({
          ok: false,
          status: 404
        } as Response);

      const result = await fetchGitHubStats();

      expect(result).toBeNull();
    });

    it('should return null when fetch throws an error', async () => {
      mockFetch.mockRejectedValue(new Error('Network error'));

      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
      const result = await fetchGitHubStats();

      expect(result).toBeNull();
      expect(consoleSpy).toHaveBeenCalledWith('Error fetching GitHub stats:', expect.any(Error));

      consoleSpy.mockRestore();
    });

    it('should return null when JSON parsing fails', async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.reject(new Error('Invalid JSON'))
        } as Response)
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve(mockReleaseData)
        } as Response);

      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
      const result = await fetchGitHubStats();

      expect(result).toBeNull();
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });

  describe('fetchDiscordStats', () => {
    const mockDiscordData = {
      approximate_member_count: 1500,
      approximate_presence_count: 200
    };

    it('should fetch and return Discord stats successfully', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve(mockDiscordData)
      } as Response);

      const result = await fetchDiscordStats();

      expect(result).toEqual({
        memberCount: 1500,
        onlineCount: 200
      });

      expect(mockFetch).toHaveBeenCalledWith('https://discord.com/api/v9/invites/QfnEFEdSjz?with_counts=true', {
        headers: {
          'Accept': 'application/json',
        },
      });
    });

    it('should handle missing member count data', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({})
      } as Response);

      const result = await fetchDiscordStats();

      expect(result).toEqual({
        memberCount: 0,
        onlineCount: 0
      });
    });

    it('should return null when Discord request fails', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 403
      } as Response);

      const result = await fetchDiscordStats();

      expect(result).toBeNull();
    });

    it('should return null when fetch throws an error', async () => {
      mockFetch.mockRejectedValue(new Error('Network error'));

      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
      const result = await fetchDiscordStats();

      expect(result).toBeNull();
      expect(consoleSpy).toHaveBeenCalledWith('Error fetching Discord stats:', expect.any(Error));

      consoleSpy.mockRestore();
    });

    it('should return null when JSON parsing fails', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.reject(new Error('Invalid JSON'))
      } as Response);

      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
      const result = await fetchDiscordStats();

      expect(result).toBeNull();
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });
});