import { createMocks } from 'node-mocks-http';
import handler from '@/pages/api/github/stats';
import * as api from '@/lib/api';

// Mock the API module
jest.mock('@/lib/api');
const mockFetchGitHubStats = api.fetchGitHubStats as jest.MockedFunction<typeof api.fetchGitHubStats>;

describe('/api/github/stats', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return GitHub stats successfully', async () => {
    const mockStats = {
      stars: 8200,
      forks: 312,
      watchers: 145,
      latest_release: {
        version: 'v0.8.5',
        published_at: '2024-01-15T10:30:00Z'
      }
    };

    mockFetchGitHubStats.mockResolvedValue(mockStats);

    const { req, res } = createMocks({
      method: 'GET',
    });

    await handler(req, res);

    expect(res._getStatusCode()).toBe(200);
    expect(JSON.parse(res._getData())).toEqual(mockStats);
    expect(res.getHeaders()).toHaveProperty('cache-control', 'public, s-maxage=900, stale-while-revalidate=3600');
  });

  it('should return 405 for non-GET methods', async () => {
    const { req, res } = createMocks({
      method: 'POST',
    });

    await handler(req, res);

    expect(res._getStatusCode()).toBe(405);
    expect(JSON.parse(res._getData())).toEqual({ message: 'Method not allowed' });
  });

  it('should return 500 when fetchGitHubStats returns null', async () => {
    mockFetchGitHubStats.mockResolvedValue(null);

    const { req, res } = createMocks({
      method: 'GET',
    });

    await handler(req, res);

    expect(res._getStatusCode()).toBe(500);
    expect(JSON.parse(res._getData())).toEqual({ message: 'Failed to fetch GitHub stats' });
  });

  it('should return 500 when fetchGitHubStats throws an error', async () => {
    mockFetchGitHubStats.mockRejectedValue(new Error('Network error'));

    const { req, res } = createMocks({
      method: 'GET',
    });

    const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    await handler(req, res);

    expect(res._getStatusCode()).toBe(500);
    expect(JSON.parse(res._getData())).toEqual({ message: 'Internal server error' });
    expect(consoleSpy).toHaveBeenCalledWith('GitHub stats API error:', expect.any(Error));

    consoleSpy.mockRestore();
  });
});