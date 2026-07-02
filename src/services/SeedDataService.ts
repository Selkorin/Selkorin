import { AppDataSource } from '../config/database';
import { SocialAccount } from '../entities/SocialAccount';
import { ContentPlan } from '../entities/ContentPlan';
import { ContentItem } from '../entities/ContentItem';
import { SocialAgent } from '../entities/SocialAgent';
import { CompetitorAnalysis } from '../entities/CompetitorAnalysis';
import { PublishingHistory } from '../entities/PublishingHistory';

export class SeedDataService {
  async seedAll(): Promise<void> {
    console.log('🌱 Seeding database with demo data...');

    try {
      // Clear existing data
      if (process.env.SEED_CLEAR === 'true') {
        console.log('  🗑️  Clearing existing data...');
        await this.clearAllData();
      }

      // Seed data in order
      await this.seedSocialAccounts();
      await this.seedContentPlans();
      await this.seedContentItems();
      await this.seedSocialAgents();
      await this.seedCompetitorAnalyses();
      await this.seedPublishingHistory();

      console.log('✅ Seeding completed successfully!\n');
    } catch (error: any) {
      console.error('❌ Seeding failed:', error.message);
      throw error;
    }
  }

  private async seedSocialAccounts(): Promise<void> {
    const accountRepo = AppDataSource.getRepository(SocialAccount);
    const count = await accountRepo.count();

    if (count > 0) {
      console.log('  ⏭️  Social accounts already exist, skipping...');
      return;
    }

    console.log('  📱 Creating social accounts...');

    const accounts = [
      {
        id: 'account-instagram-demo',
        userId: 'demo-user',
        projectId: 'demo',
        platform: 'instagram' as const,
        accountName: '@demo_brand_official',
        status: 'connected' as const,
        authType: 'oauth' as const,
        accessTokenEncrypted: 'encrypted_token_ig_demo',
        refreshTokenEncrypted: 'refresh_token_ig_demo',
        tokenExpiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
      {
        id: 'account-telegram-demo',
        userId: 'demo-user',
        projectId: 'demo',
        platform: 'telegram' as const,
        accountName: 'Demo Brand Channel',
        status: 'connected' as const,
        authType: 'bot_token' as const,
        accessTokenEncrypted: 'encrypted_token_tg_demo',
      },
      {
        id: 'account-tiktok-demo',
        userId: 'demo-user',
        projectId: 'demo',
        platform: 'tiktok' as const,
        accountName: '@demobrand',
        status: 'connected' as const,
        authType: 'oauth' as const,
        accessTokenEncrypted: 'encrypted_token_tk_demo',
        refreshTokenEncrypted: 'refresh_token_tk_demo',
        tokenExpiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
    ];

    for (const account of accounts) {
      await accountRepo.save(account);
    }

    console.log(`    ✓ Created ${accounts.length} social accounts`);
  }

  private async seedContentPlans(): Promise<void> {
    const planRepo = AppDataSource.getRepository(ContentPlan);
    const count = await planRepo.count();

    if (count > 0) {
      console.log('  ⏭️  Content plans already exist, skipping...');
      return;
    }

    console.log('  📅 Creating content plans...');

    const now = new Date();
    const weekStart = new Date(now);
    weekStart.setDate(now.getDate() - now.getDay());
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekStart.getDate() + 6);

    const plans = [
      {
        id: 'plan-current-week',
        socialAccountId: 'account-instagram-demo',
        createdByAgentId: 'agent-instagram',
        title: 'Current Week Content Plan',
        periodStart: weekStart,
        periodEnd: weekEnd,
        status: 'active' as const,
      },
      {
        id: 'plan-next-week',
        socialAccountId: 'account-instagram-demo',
        createdByAgentId: 'agent-instagram',
        title: 'Next Week Content Plan',
        periodStart: new Date(weekEnd.getTime() + 24 * 60 * 60 * 1000),
        periodEnd: new Date(weekEnd.getTime() + 13 * 24 * 60 * 60 * 1000),
        status: 'draft' as const,
      },
    ];

    for (const plan of plans) {
      await planRepo.save(plan);
    }

    console.log(`    ✓ Created ${plans.length} content plans`);
  }

  private async seedContentItems(): Promise<void> {
    const itemRepo = AppDataSource.getRepository(ContentItem);
    const planRepo = AppDataSource.getRepository(ContentPlan);
    const count = await itemRepo.count();

    if (count > 0) {
      console.log('  ⏭️  Content items already exist, skipping...');
      return;
    }

    console.log('  📝 Creating content items...');

    const plan = await planRepo.findOneBy({ id: 'plan-current-week' });
    if (!plan) {
      console.log('    ❌ Content plan not found, skipping content items');
      return;
    }

    const items = [
      {
        contentPlanId: plan.id,
        platform: 'instagram' as const,
        contentType: 'post' as const,
        title: 'Morning Motivation Monday',
        caption:
          "🌅 Start your week with positive energy! Every Monday morning is a chance to set new goals and achieve them. What's your first win this week?\n\n#MondayMotivation #GoalSetting #Success #StartTheWeek",
        imageUrl:
          'https://images.unsplash.com/photo-1552664730-d307ca884978?w=800',
        hashtags: ['#MondayMotivation', '#Success', '#Goals'],
        publishAt: new Date(plan.periodStart.getTime() + 9 * 60 * 60 * 1000),
        status: 'approved' as const,
        approvalStatus: 'approved' as const,
      },
      {
        contentPlanId: plan.id,
        platform: 'instagram' as const,
        contentType: 'reel' as const,
        title: 'Quick Productivity Tips',
        caption:
          '⚡ 5 productivity hacks that actually work! Watch this Reel for quick tips to boost your productivity today.\n\n#ProductivityTips #TimeManagement #WorkSmart',
        videoUrl: 'https://videos.unsplash.com/video-1611162588537-b7b2dc5c4c9f',
        hashtags: ['#Productivity', '#Tips', '#TimeManagement'],
        publishAt: new Date(plan.periodStart.getTime() + 12 * 60 * 60 * 1000),
        status: 'approved' as const,
        approvalStatus: 'approved' as const,
      },
      {
        contentPlanId: plan.id,
        platform: 'telegram' as const,
        contentType: 'post' as const,
        title: 'Daily Newsletter',
        caption:
          '📰 Daily Briefing: Top 3 news stories of the day\n\n1. Innovation in Tech\n2. Market Updates\n3. Lifestyle Trends\n\nStay informed!',
        imageUrl:
          'https://images.unsplash.com/photo-1504384308090-c894fdcc538d?w=800',
        hashtags: ['#News', '#Daily', '#Updates'],
        publishAt: new Date(plan.periodStart.getTime() + 18 * 60 * 60 * 1000),
        status: 'scheduled' as const,
        approvalStatus: 'approved' as const,
      },
      {
        contentPlanId: plan.id,
        platform: 'instagram' as const,
        contentType: 'story' as const,
        title: 'Behind The Scenes',
        caption: 'What our team is working on today! 🎥',
        imageUrl: 'https://images.unsplash.com/photo-1552664730-d307ca884978?w=800',
        hashtags: ['#BTS', '#TeamWork'],
        publishAt: new Date(plan.periodStart.getTime() + 1 * 24 * 60 * 60 * 1000 + 10 * 60 * 60 * 1000),
        status: 'draft' as const,
        approvalStatus: 'pending' as const,
      },
      {
        contentPlanId: plan.id,
        platform: 'tiktok' as const,
        contentType: 'post' as const,
        title: 'Trending Sound Challenge',
        caption:
          'We took on the challenge! Can you do it better? 🎵 #TrendingSound #Challenge #FYP',
        videoUrl: 'https://videos.unsplash.com/video-1611162588537-b7b2dc5c4c9f',
        hashtags: ['#TikTok', '#Challenge', '#FYP'],
        publishAt: new Date(plan.periodStart.getTime() + 2 * 24 * 60 * 60 * 1000 + 15 * 60 * 60 * 1000),
        status: 'needs_review' as const,
        approvalStatus: 'pending' as const,
      },
      {
        contentPlanId: plan.id,
        platform: 'instagram' as const,
        contentType: 'carousel' as const,
        title: 'Product Showcase Carousel',
        caption:
          '✨ Swipe through our latest collection! Each slide features a unique product with special benefits. Which one is your favorite?\n\n🛍️ Shop link in bio!\n\n#NewCollection #ProductShowcase #Shopping',
        imageUrl: 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=800',
        hashtags: ['#NewProducts', '#Shopping', '#Collection'],
        publishAt: new Date(plan.periodStart.getTime() + 3 * 24 * 60 * 60 * 1000 + 12 * 60 * 60 * 1000),
        status: 'approved' as const,
        approvalStatus: 'approved' as const,
      },
      {
        contentPlanId: plan.id,
        platform: 'instagram' as const,
        contentType: 'reel' as const,
        title: 'Customer Testimonial',
        caption:
          '❤️ This is why we do what we do! Thank you to our amazing customer for sharing their story. Your success is our success!\n\n#CustomerLove #Testimonial #CommunityFirst',
        videoUrl: 'https://videos.unsplash.com/video-1611162588537-b7b2dc5c4c9f',
        hashtags: ['#Testimonial', '#CustomerReview', '#Success'],
        publishAt: new Date(plan.periodStart.getTime() + 4 * 24 * 60 * 60 * 1000 + 14 * 60 * 60 * 1000),
        status: 'approved' as const,
        approvalStatus: 'approved' as const,
      },
    ];

    for (const item of items) {
      await itemRepo.save(item);
    }

    console.log(`    ✓ Created ${items.length} content items`);
  }

  private async seedSocialAgents(): Promise<void> {
    const agentRepo = AppDataSource.getRepository(SocialAgent);
    const accountRepo = AppDataSource.getRepository(SocialAccount);
    const count = await agentRepo.count();

    if (count > 0) {
      console.log('  ⏭️  Social agents already exist, skipping...');
      return;
    }

    console.log('  🤖 Creating AI agents...');

    const instagramAccount = await accountRepo.findOneBy({
      id: 'account-instagram-demo',
    });
    const telegramAccount = await accountRepo.findOneBy({
      id: 'account-telegram-demo',
    });

    if (!instagramAccount || !telegramAccount) {
      console.log('    ❌ Social accounts not found, skipping agents');
      return;
    }

    const agents = [
      {
        id: 'agent-instagram',
        socialAccountId: instagramAccount.id,
        agentName: 'Instagram Brand Specialist',
        agentRole: 'Creative and visual storyteller',
        toneOfVoice: 'engaging, trendy, inspiring',
        brandRules: {
          targetAudience: 'Gen Z and young millennials, tech-savvy, value-driven',
          style: 'modern',
          offers: [],
          rules:
            'Focus on brand values: innovation, community, sustainability. Use trending sounds and formats.',
        },
        contentRules: {
          style: 'Mix of educational, entertaining, and promotional content',
        },
        autoPublishEnabled: false,
        approvalRequired: true,
        aiProvider: 'claude',
      },
      {
        id: 'agent-telegram',
        socialAccountId: telegramAccount.id,
        agentName: 'Telegram Community Manager',
        agentRole: 'Knowledgeable guide and community facilitator',
        toneOfVoice: 'professional, informative, accessible',
        brandRules: {
          targetAudience: 'Professional audience, business-minded, information seekers',
          style: 'clean',
          offers: [],
          rules:
            'Deliver value-focused content. Maintain professional tone. Foster community engagement.',
        },
        contentRules: {
          style: 'News, updates, tutorials, and community discussions',
        },
        autoPublishEnabled: false,
        approvalRequired: true,
        aiProvider: 'claude',
      },
    ];

    for (const agent of agents) {
      await agentRepo.save(agent);
    }

    console.log(`    ✓ Created ${agents.length} social agents`);
  }

  private async seedCompetitorAnalyses(): Promise<void> {
    const analysisRepo = AppDataSource.getRepository(CompetitorAnalysis);
    const count = await analysisRepo.count();

    if (count > 0) {
      console.log('  ⏭️  Competitor analyses already exist, skipping...');
      return;
    }

    console.log('  🔍 Creating competitor analyses...');

    const analyses = [
      {
        id: 'analysis-competitor-1',
        projectId: 'plan-current-week',
        socialAccountId: 'account-instagram-demo',
        platform: 'instagram' as const,
        competitorHandle: '@competitor_brand_1',
        competitorUrl: 'https://instagram.com/competitor_brand_1',
        status: 'completed' as const,
        metrics: {
          totalPosts: 156,
          totalFollowers: 125000,
          avgLikes: 2400,
          avgComments: 89,
          avgShares: 23,
          engagementRate: 2.15,
        },
        contentAnalysis: {
          topContentTypes: ['reel', 'carousel', 'post'],
          topHashtags: ['#trending', '#lifestyle', '#inspiration', '#community'],
          bestPostingTimes: ['14:00', '19:00', '21:00'],
          postFrequency: '2-3 times per week',
          captions: {
            avgLength: 145,
            patterns: ['Uses emojis', 'Includes CTAs', 'Asks questions'],
          },
          visualStyle: {
            colorPalette: ['vibrant', 'minimalist', 'warm'],
            filterUsage: ['natural', 'warm', 'bright'],
            description: 'Consistent visual branding with professional aesthetic',
          },
        },
        topPosts: [
          {
            title: 'Product Launch Announcement',
            likes: 5200,
            comments: 234,
            shares: 67,
            engagement: 5501,
            contentType: 'reel',
            postedAt: '2024-05-15T14:30:00Z',
          },
          {
            title: 'Customer Success Story',
            likes: 4800,
            comments: 198,
            shares: 54,
            engagement: 5052,
            contentType: 'post',
            postedAt: '2024-05-10T19:00:00Z',
          },
        ],
        aiReport: `Competitor Analysis Report: @competitor_brand_1

OVERVIEW:
With 125K followers and consistent 2-3x weekly posting, this competitor has built a strong engaged community focused on lifestyle and inspiration content.

KEY STRENGTHS:
1. **High Engagement Rate (2.15%)** - Well above industry average for lifestyle brands
2. **Strategic Content Mix** - Balanced between educational, entertaining, and promotional
3. **Consistent Posting Schedule** - Their audience expects content at 14:00, 19:00, and 21:00 UTC
4. **Strong Visual Branding** - Recognizable color palette and editing style

AUDIENCE INSIGHTS:
- Primary: Young professionals (25-35 years old)
- Secondary: Aspirational lifestyle seekers
- Highly engaged with CTAs (questions, challenges, polls)

CONTENT PERFORMANCE:
- Reels perform best (avg 2.8k engagement)
- Carousels provide good reach (avg 1.9k engagement)
- Long-form captions (140-160 chars) get more comments

RECOMMENDATIONS FOR COMPETITIVE ADVANTAGE:
1. Post at 14:00 and 19:00 UTC to capture their audience's active times
2. Use similar hashtag strategy but focus on niche variations
3. Create comparative content showing unique value proposition
4. Engage with their community (comment on their posts)
5. Develop exclusive behind-the-scenes content`,
        recommendations: [
          {
            title: 'Match Their Posting Schedule',
            description:
              'They post at 14:00, 19:00, and 21:00 UTC with high consistency',
            action: 'Schedule your posts 30 minutes before their peak times',
            priority: 'high' as const,
          },
          {
            title: 'Increase Reel Production',
            description: 'Reels generate 40% higher engagement than static posts',
            action: 'Create 2-3 reels weekly focusing on education and entertainment',
            priority: 'high' as const,
          },
          {
            title: 'Implement CTA Strategy',
            description: 'Questions and CTAs in captions drive 3x more comments',
            action: 'Add questions to 80% of captions, ask for saves/shares',
            priority: 'medium' as const,
          },
          {
            title: 'Visual Brand Consistency',
            description:
              'Their warm, vibrant aesthetic is instantly recognizable',
            action: 'Develop consistent filters and color grading template',
            priority: 'medium' as const,
          },
        ],
        completedAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000),
      },
    ];

    for (const analysis of analyses) {
      await analysisRepo.save(analysis);
    }

    console.log(`    ✓ Created ${analyses.length} competitor analyses`);
  }

  private async seedPublishingHistory(): Promise<void> {
    const historyRepo = AppDataSource.getRepository(PublishingHistory);
    const count = await historyRepo.count();

    if (count > 0) {
      console.log('  ⏭️  Publishing history already exists, skipping...');
      return;
    }

    console.log('  📊 Creating publishing history...');

    const now = new Date();

    const histories = [
      {
        contentItemId: 'item-1',
        platform: 'instagram' as const,
        platformPostId: '123456789_987654321',
        status: 'success' as const,
        publishedAt: new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000),
        metrics: {
          likes: 1234,
          comments: 87,
          shares: 23,
          saves: 156,
          views: 8900,
          reach: 12450,
          impressions: 15670,
        },
      },
      {
        contentItemId: 'item-2',
        platform: 'instagram' as const,
        platformPostId: '234567890_098765432',
        status: 'success' as const,
        publishedAt: new Date(now.getTime() - 5 * 24 * 60 * 60 * 1000),
        metrics: {
          likes: 2156,
          comments: 145,
          shares: 67,
          saves: 289,
          views: 15600,
          reach: 21300,
          impressions: 28900,
        },
      },
    ];

    for (const history of histories) {
      await historyRepo.save(history);
    }

    console.log(`    ✓ Created ${histories.length} publishing history entries`);
  }

  private async clearAllData(): Promise<void> {
    const entities = [
      PublishingHistory,
      CompetitorAnalysis,
      SocialAgent,
      ContentItem,
      ContentPlan,
      SocialAccount,
    ];

    for (const entity of entities) {
      const repo = AppDataSource.getRepository(entity);
      await repo.delete({});
    }

    console.log('    ✓ Database cleared');
  }
}
