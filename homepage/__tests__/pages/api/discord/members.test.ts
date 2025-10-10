import { createMocks } from 'node-mocks-http';
import handler from '@/pages/api/discord/members';
import * as api from '@/lib/api';

// Mock the API module
jest.mock('@/lib/api');
const mockFetchDiscordStats = api.fetchDiscordStats as jest.MockedFunction<typeof api.fetchDiscordStats>;

describe('/api/discord/members', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return Discord stats successfully', async () => {
    const mockStats = {
      memberCount: 1500,
      onlineCount: 200
    };

    mockFetchDiscordStats.mockResolvedValue(mockStats);

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

  it('should return 500 when fetchDiscordStats returns null', async () => {
    mockFetchDiscordStats.mockResolvedValue(null);

    const { req, res } = createMocks({
      method: 'GET',
    });

    await handler(req, res);

    expect(res._getStatusCode()).toBe(500);
    expect(JSON.parse(res._getData())).toEqual({ message: 'Failed to fetch Discord stats' });
  });

  it('should return 500 when fetchDiscordStats throws an error', async () => {
    mockFetchDiscordStats.mockRejectedValue(new Error('Network error'));

    const { req, res } = createMocks({
      method: 'GET',
    });

    const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    await handler(req, res);

    expect(res._getStatusCode()).toBe(500);
    expect(JSON.parse(res._getData())).toEqual({ message: 'Internal server error' });
    expect(consoleSpy).toHaveBeenCalledWith('Discord stats API error:', expect.any(Error));

    consoleSpy.mockRestore();
  });
});