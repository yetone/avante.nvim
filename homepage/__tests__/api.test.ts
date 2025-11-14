import { fetchGitHubStats, fetchDiscordStats } from '@/lib/api';

global.fetch = jest.fn();

describe('API Functions', () => {
  beforeEach(() => {
    (fetch as jest.Mock).mockClear();
  });

  describe('fetchGitHubStats', () => {
    it('should fetch and return GitHub stats', async () => {
      const mockRepoData = {
        stargazers_count: 8200,
        forks_count: 350,
        watchers_count: 150,
      };

      const mockReleaseData = {
        tag_name: 'v1.0.0',
        published_at: '2024-01-01T00:00:00Z',
      };

      (fetch as jest.Mock)
        .mockResolvedValueOnce({
          ok: true,
          json: async () => mockRepoData,
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => mockReleaseData,
        });

      const stats = await fetchGitHubStats();

      expect(stats).toEqual({
        stars: 8200,
        forks: 350,
        watchers: 150,
        latest_release: {
          version: 'v1.0.0',
          published_at: '2024-01-01T00:00:00Z',
        },
      });
    });

    it('should return null on API failure', async () => {
      (fetch as jest.Mock).mockResolvedValue({
        ok: false,
      });

      const stats = await fetchGitHubStats();

      expect(stats).toBeNull();
    });
  });

  describe('fetchDiscordStats', () => {
    it('should return Discord stats', async () => {
      const stats = await fetchDiscordStats();

      expect(stats).toEqual({
        member_count: 1000,
        online_count: 150,
      });
    });
  });
});
