import type { NextApiRequest, NextApiResponse } from 'next';
import { fetchGitHubStats } from '@/lib/api';
import { GitHubStats } from '@/lib/types';

type Data = GitHubStats | { error: string };

/**
 * API endpoint to fetch GitHub repository statistics
 * Includes caching headers to reduce API calls
 */
export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<Data>
) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' } as any);
  }

  try {
    const stats = await fetchGitHubStats();

    if (!stats) {
      return res.status(500).json({ error: 'Failed to fetch GitHub stats' } as any);
    }

    // Cache for 5 minutes
    res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate');

    return res.status(200).json(stats);
  } catch (error) {
    console.error('Error in GitHub stats API:', error);
    return res.status(500).json({ error: 'Internal server error' } as any);
  }
}
