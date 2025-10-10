import { NextApiRequest, NextApiResponse } from 'next';
import { fetchDiscordStats } from '@/lib/api';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'GET') {
    return res.status(405).json({ message: 'Method not allowed' });
  }

  try {
    const stats = await fetchDiscordStats();

    if (!stats) {
      return res.status(500).json({ message: 'Failed to fetch Discord stats' });
    }

    // Set cache headers
    res.setHeader('Cache-Control', 'public, s-maxage=900, stale-while-revalidate=3600'); // 15 minutes cache

    return res.status(200).json(stats);
  } catch (error) {
    console.error('Discord stats API error:', error);
    return res.status(500).json({ message: 'Internal server error' });
  }
}