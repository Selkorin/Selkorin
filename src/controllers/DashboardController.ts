import { Request, Response } from 'express';
import { AppDataSource } from '../config/database';
import { ContentItem } from '../entities/ContentItem';
import { PublishingHistory } from '../entities/PublishingHistory';
import { CompetitorAnalysis } from '../entities/CompetitorAnalysis';
import { SocialAccount } from '../entities/SocialAccount';

export class DashboardController {
  async getStats(req: Request, res: Response) {
    try {
      const contentRepo = AppDataSource.getRepository(ContentItem);
      const historyRepo = AppDataSource.getRepository(PublishingHistory);
      const accountRepo = AppDataSource.getRepository(SocialAccount);

      // Content statistics
      const totalContent = await contentRepo.count();
      const approvedContent = await contentRepo.countBy({ approvalStatus: 'approved' });
      const publishedContent = await historyRepo.count();

      // Platform stats
      const platforms = await contentRepo
        .createQueryBuilder('content')
        .select('content.platform', 'platform')
        .addSelect('COUNT(*)', 'count')
        .groupBy('content.platform')
        .getRawMany();

      // Status breakdown
      const statuses = await contentRepo
        .createQueryBuilder('content')
        .select('content.status', 'status')
        .addSelect('COUNT(*)', 'count')
        .groupBy('content.status')
        .getRawMany();

      // Total engagement
      const publishingMetrics = await historyRepo
        .createQueryBuilder('history')
        .select('SUM(CAST(history.metrics->>"likes" AS INTEGER))', 'totalLikes')
        .addSelect('SUM(CAST(history.metrics->>"comments" AS INTEGER))', 'totalComments')
        .addSelect('SUM(CAST(history.metrics->>"reach" AS INTEGER))', 'totalReach')
        .getRawOne();

      const connectedAccounts = await accountRepo.count();

      res.json({
        success: true,
        stats: {
          totalContent,
          approvedContent,
          publishedContent,
          connectedAccounts,
          engagement: {
            likes: parseInt(publishingMetrics?.totalLikes || '0'),
            comments: parseInt(publishingMetrics?.totalComments || '0'),
            reach: parseInt(publishingMetrics?.totalReach || '0'),
          },
          platformBreakdown: platforms.reduce(
            (acc: any, p: any) => {
              acc[p.platform] = parseInt(p.count);
              return acc;
            },
            {}
          ),
          statusBreakdown: statuses.reduce(
            (acc: any, s: any) => {
              acc[s.status] = parseInt(s.count);
              return acc;
            },
            {}
          ),
        },
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async getRecentActivity(req: Request, res: Response) {
    try {
      const itemRepo = AppDataSource.getRepository(ContentItem);
      const historyRepo = AppDataSource.getRepository(PublishingHistory);

      // Recent content
      const recentContent = await itemRepo.find({
        order: { updatedAt: 'DESC' },
        take: 5,
      });

      // Recent publishing activity
      const recentPublishing = await historyRepo.find({
        order: { publishedAt: 'DESC' },
        take: 5,
      });

      // Upcoming posts
      const now = new Date();
      const upcomingPosts = await itemRepo.find({
        where: {
          publishAt: { min: now } as any,
          status: 'approved',
        },
        order: { publishAt: 'ASC' },
        take: 5,
      });

      res.json({
        success: true,
        activity: {
          recentContent: recentContent.map(c => ({
            id: c.id,
            title: c.title,
            platform: c.platform,
            status: c.status,
            updatedAt: c.updatedAt,
          })),
          recentPublishing: recentPublishing.map(h => ({
            id: h.id,
            contentItemId: h.contentItemId,
            platform: h.platform,
            publishedAt: h.publishedAt,
            metrics: h.metrics,
          })),
          upcoming: upcomingPosts.map(p => ({
            id: p.id,
            title: p.title,
            platform: p.platform,
            publishAt: p.publishAt,
          })),
        },
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async getCalendar(req: Request, res: Response) {
    try {
      const { month, year } = req.query;
      const contentRepo = AppDataSource.getRepository(ContentItem);

      const targetMonth = month ? parseInt(month as string) : new Date().getMonth() + 1;
      const targetYear = year ? parseInt(year as string) : new Date().getFullYear();

      const startDate = new Date(targetYear, targetMonth - 1, 1);
      const endDate = new Date(targetYear, targetMonth, 0);

      const content = await contentRepo.find({
        where: {
          publishAt: { min: startDate, max: endDate } as any,
        },
        order: { publishAt: 'ASC' },
      });

      // Group by day
      const calendar: Record<string, any[]> = {};
      content.forEach(item => {
        const day = item.publishAt.toISOString().split('T')[0];
        if (!calendar[day]) calendar[day] = [];
        calendar[day].push({
          id: item.id,
          title: item.title,
          platform: item.platform,
          status: item.status,
          time: item.publishAt.toLocaleTimeString('en-US', {
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
          }),
        });
      });

      res.json({
        success: true,
        month: targetMonth,
        year: targetYear,
        calendar,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async getAnalytics(req: Request, res: Response) {
    try {
      const { days } = req.query;
      const daysBack = days ? parseInt(days as string) : 7;
      const historyRepo = AppDataSource.getRepository(PublishingHistory);

      const startDate = new Date();
      startDate.setDate(startDate.getDate() - daysBack);

      const data = await historyRepo.find({
        where: {
          publishedAt: { min: startDate } as any,
        },
        order: { publishedAt: 'ASC' },
      });

      // Group by day
      const timeline: Record<string, any> = {};
      data.forEach(h => {
        const day = h.publishedAt.toISOString().split('T')[0];
        if (!timeline[day]) {
          timeline[day] = {
            date: day,
            posts: 0,
            likes: 0,
            comments: 0,
            reach: 0,
          };
        }
        timeline[day].posts += 1;
        timeline[day].likes += h.metrics?.likes || 0;
        timeline[day].comments += h.metrics?.comments || 0;
        timeline[day].reach += (h.metrics as any)?.reach || 0;
      });

      // Platform analytics
      const byPlatform: Record<string, any> = {};
      data.forEach(h => {
        if (!byPlatform[h.platform]) {
          byPlatform[h.platform] = {
            platform: h.platform,
            posts: 0,
            engagement: 0,
          };
        }
        byPlatform[h.platform].posts += 1;
        byPlatform[h.platform].engagement +=
          (h.metrics?.likes || 0) + (h.metrics?.comments || 0);
      });

      res.json({
        success: true,
        period: `Last ${daysBack} days`,
        timeline: Object.values(timeline),
        byPlatform: Object.values(byPlatform),
        summary: {
          totalPosts: data.length,
          totalLikes: data.reduce((sum, h) => sum + (h.metrics?.likes || 0), 0),
          totalComments: data.reduce((sum, h) => sum + (h.metrics?.comments || 0), 0),
          totalReach: data.reduce((sum, h) => sum + ((h.metrics as any)?.reach || 0), 0),
          avgEngagement: Math.round(
            data.reduce(
              (sum, h) =>
                sum +
                ((h.metrics?.likes || 0) +
                  (h.metrics?.comments || 0) +
                  (h.metrics?.shares || 0)),
              0
            ) / Math.max(data.length, 1)
          ),
        },
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }
}
