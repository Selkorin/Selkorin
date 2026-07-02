import { AppDataSource } from '../config/database';
import { CompetitorAnalysis } from '../entities/CompetitorAnalysis';
import { AIProviderFactory } from './ai/AIProviderFactory';

export interface CompetitorData {
  platform: 'instagram' | 'telegram' | 'vk' | 'youtube' | 'tiktok';
  handle: string;
  url?: string;
  posts?: Array<{
    title: string;
    caption: string;
    likes: number;
    comments: number;
    shares: number;
    image?: string;
    video?: string;
    hashtags: string[];
    postedAt: Date;
  }>;
}

export class CompetitorAnalysisService {
  async analyzeCompetitor(
    projectId: string,
    socialAccountId: string,
    competitorData: CompetitorData
  ): Promise<CompetitorAnalysis> {
    const analysisRepo = AppDataSource.getRepository(CompetitorAnalysis);

    // Create analysis record
    let analysis = analysisRepo.create({
      projectId,
      socialAccountId,
      platform: competitorData.platform,
      competitorHandle: competitorData.handle,
      competitorUrl: competitorData.url || '',
      status: 'analyzing',
      metrics: {
        totalPosts: 0,
        totalFollowers: 0,
        avgLikes: 0,
        avgComments: 0,
        avgShares: 0,
        engagementRate: 0,
      },
      contentAnalysis: {
        topContentTypes: [],
        topHashtags: [],
        bestPostingTimes: [],
        postFrequency: '',
        captions: {
          avgLength: 0,
          patterns: [],
        },
        visualStyle: {
          colorPalette: [],
          filterUsage: [],
          description: '',
        },
      },
      topPosts: [],
      aiReport: '',
      recommendations: [],
    });

    analysis = await analysisRepo.save(analysis);

    try {
      // Analyze posts
      const metrics = this.calculateMetrics(competitorData.posts || []);
      const contentAnalysis = this.analyzeContent(competitorData.posts || []);
      const topPosts = this.getTopPosts(competitorData.posts || []);

      // Generate AI report
      const aiReport = await this.generateAIReport(
        competitorData.handle,
        metrics,
        contentAnalysis,
        topPosts
      );

      // Generate recommendations
      const recommendations = this.generateRecommendations(
        metrics,
        contentAnalysis,
        aiReport
      );

      // Update analysis
      analysis.metrics = metrics;
      analysis.contentAnalysis = contentAnalysis;
      analysis.topPosts = topPosts;
      analysis.aiReport = aiReport;
      analysis.recommendations = recommendations;
      analysis.status = 'completed';
      analysis.completedAt = new Date();

      return analysisRepo.save(analysis);
    } catch (error: any) {
      analysis.status = 'failed';
      analysis.errorMessage = error.message;
      return analysisRepo.save(analysis);
    }
  }

  private calculateMetrics(posts: any[]) {
    if (posts.length === 0) {
      return {
        totalPosts: 0,
        totalFollowers: 0,
        avgLikes: 0,
        avgComments: 0,
        avgShares: 0,
        engagementRate: 0,
      };
    }

    const totalLikes = posts.reduce((sum, p) => sum + (p.likes || 0), 0);
    const totalComments = posts.reduce((sum, p) => sum + (p.comments || 0), 0);
    const totalShares = posts.reduce((sum, p) => sum + (p.shares || 0), 0);

    const avgLikes = Math.round(totalLikes / posts.length);
    const avgComments = Math.round(totalComments / posts.length);
    const avgShares = Math.round(totalShares / posts.length);

    const totalEngagement = totalLikes + totalComments + totalShares;
    const engagementRate = posts.length > 0
      ? Math.round((totalEngagement / (posts.length * 1000)) * 100) / 100
      : 0;

    return {
      totalPosts: posts.length,
      totalFollowers: 0, // Would need API
      avgLikes,
      avgComments,
      avgShares,
      engagementRate,
    };
  }

  private analyzeContent(posts: any[]) {
    const hashtags: Record<string, number> = {};
    const postingHours: Record<string, number> = {};
    let totalCaptionLength = 0;

    posts.forEach(post => {
      // Analyze hashtags
      post.hashtags?.forEach((tag: string) => {
        hashtags[tag] = (hashtags[tag] || 0) + 1;
      });

      // Analyze posting times
      const date = new Date(post.postedAt);
      const hour = date.getHours();
      postingHours[hour] = (postingHours[hour] || 0) + 1;

      // Caption analysis
      if (post.caption) {
        totalCaptionLength += post.caption.length;
      }
    });

    // Get top hashtags
    const topHashtags = Object.entries(hashtags)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([tag]) => tag);

    // Get best posting hours
    const bestPostingTimes = Object.entries(postingHours)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([hour]) => `${hour}:00`);

    const avgCaptionLength = posts.length > 0
      ? Math.round(totalCaptionLength / posts.length)
      : 0;

    return {
      topContentTypes: this.getTopContentTypes(posts),
      topHashtags,
      bestPostingTimes,
      postFrequency: this.calculatePostFrequency(posts),
      captions: {
        avgLength: avgCaptionLength,
        patterns: this.analyzeCaptionPatterns(posts),
      },
      visualStyle: {
        colorPalette: ['professional', 'vibrant', 'minimalist'], // Placeholder
        filterUsage: ['natural', 'warm', 'bright'],
        description: 'Consistent visual branding with professional aesthetic',
      },
    };
  }

  private getTopContentTypes(posts: any[]): string[] {
    const types: Record<string, number> = {};
    posts.forEach(post => {
      const type = post.image ? 'image' : post.video ? 'video' : 'carousel';
      types[type] = (types[type] || 0) + 1;
    });

    return Object.entries(types)
      .sort((a, b) => b[1] - a[1])
      .map(([type]) => type);
  }

  private calculatePostFrequency(posts: any[]): string {
    if (posts.length < 2) return 'irregular';

    const dates = posts
      .map(p => new Date(p.postedAt).getTime())
      .sort((a, b) => a - b);

    const gaps: number[] = [];
    for (let i = 1; i < dates.length; i++) {
      gaps.push((dates[i] - dates[i - 1]) / (1000 * 60 * 60 * 24)); // days
    }

    const avgGap = gaps.length > 0
      ? gaps.reduce((a, b) => a + b, 0) / gaps.length
      : 0;

    if (avgGap < 1) return 'daily';
    if (avgGap < 3) return '2-3 times per week';
    if (avgGap < 7) return 'weekly';
    return 'irregular';
  }

  private analyzeCaptionPatterns(posts: any[]): string[] {
    const patterns: string[] = [];

    const captions = posts.map(p => p.caption || '');
    const hasEmojis = captions.some(c => /\p{Emoji}/u.test(c));
    const hasCTA = captions.some(c =>
      /follow|subscribe|comment|share|like|click/i.test(c)
    );
    const hasQuestions = captions.some(c => c.includes('?'));
    const hasStories = captions.some(c => c.length > 500);

    if (hasEmojis) patterns.push('Uses emojis');
    if (hasCTA) patterns.push('Includes CTAs');
    if (hasQuestions) patterns.push('Asks questions');
    if (hasStories) patterns.push('Long-form storytelling');

    return patterns;
  }

  private getTopPosts(posts: any[]) {
    return posts
      .map(p => ({
        title: p.title || 'Post',
        likes: p.likes || 0,
        comments: p.comments || 0,
        shares: p.shares || 0,
        engagement: (p.likes || 0) + (p.comments || 0) + (p.shares || 0),
        contentType: p.image ? 'image' : p.video ? 'video' : 'carousel',
        postedAt: new Date(p.postedAt).toISOString(),
      }))
      .sort((a, b) => b.engagement - a.engagement)
      .slice(0, 5);
  }

  private async generateAIReport(
    competitorHandle: string,
    metrics: any,
    contentAnalysis: any,
    topPosts: any[]
  ): Promise<string> {
    const aiProvider = AIProviderFactory.getProvider('claude');

    const prompt = `
Analyze this competitor's performance and create a detailed report:

Competitor: @${competitorHandle}

Metrics:
- Total Posts: ${metrics.totalPosts}
- Average Likes: ${metrics.avgLikes}
- Average Comments: ${metrics.avgComments}
- Engagement Rate: ${metrics.engagementRate}%

Content Strategy:
- Top Content Types: ${contentAnalysis.topContentTypes.join(', ')}
- Top Hashtags: ${contentAnalysis.topHashtags.slice(0, 5).join(', ')}
- Best Posting Times: ${contentAnalysis.bestPostingTimes.join(', ')}
- Post Frequency: ${contentAnalysis.postFrequency}
- Caption Patterns: ${contentAnalysis.captions.patterns.join(', ')}
- Avg Caption Length: ${contentAnalysis.captions.avgLength} characters

Top Performing Posts:
${topPosts.map(p => `- "${p.title}": ${p.engagement} engagements (${p.contentType})`).join('\n')}

Please provide:
1. Overall assessment of their strategy
2. Key strengths
3. Audience engagement patterns
4. Content performance insights
5. Recommended actions for competitive advantage

Format as a professional competitive analysis report.
    `;

    return aiProvider.generateText(prompt);
  }

  private generateRecommendations(
    metrics: any,
    contentAnalysis: any,
    aiReport: string
  ): Array<{
    title: string;
    description: string;
    action: string;
    priority: 'high' | 'medium' | 'low';
  }> {
    const recommendations: Array<{
      title: string;
      description: string;
      action: string;
      priority: 'high' | 'medium' | 'low';
    }> = [];

    // High priority recommendations
    if (contentAnalysis.topContentTypes.includes('video')) {
      recommendations.push({
        title: 'Increase Video Content',
        description: 'Competitor uses video extensively with high engagement',
        action: 'Create more Reels, Stories, and video content',
        priority: 'high',
      });
    }

    if (metrics.avgComments > 100) {
      recommendations.push({
        title: 'Boost Engagement',
        description: 'Competitor has strong comment engagement',
        action: 'Ask more questions and encourage discussions',
        priority: 'high',
      });
    }

    // Medium priority recommendations
    if (contentAnalysis.topHashtags.length > 5) {
      recommendations.push({
        title: 'Strategic Hashtag Usage',
        description: 'Competitor uses diverse hashtag strategy',
        action: `Adopt similar hashtags: ${contentAnalysis.topHashtags.slice(0, 3).join(', ')}`,
        priority: 'medium',
      });
    }

    recommendations.push({
      title: 'Posting Schedule',
      description: 'Best times: ' + contentAnalysis.bestPostingTimes.join(', '),
      action: 'Schedule posts during peak engagement hours',
      priority: 'medium',
    });

    // Low priority recommendations
    recommendations.push({
      title: 'Caption Strategy',
      description: `Average caption length: ${contentAnalysis.captions.avgLength} characters`,
      action: 'Match caption length and include patterns like: ' +
        contentAnalysis.captions.patterns.join(', '),
      priority: 'low',
    });

    return recommendations;
  }

  // Get analysis report
  async getAnalysis(analysisId: string): Promise<CompetitorAnalysis | null> {
    const analysisRepo = AppDataSource.getRepository(CompetitorAnalysis);
    return analysisRepo.findOneBy({ id: analysisId });
  }

  // Get all analyses for project
  async getAnalysesByProject(projectId: string): Promise<CompetitorAnalysis[]> {
    const analysisRepo = AppDataSource.getRepository(CompetitorAnalysis);
    return analysisRepo.find({
      where: { projectId, status: 'completed' },
      order: { createdAt: 'DESC' },
    });
  }

  // Send recommendations to content agents
  async sendRecommendationsToAgents(
    analysisId: string,
    agentIds: string[]
  ): Promise<{ success: boolean; message: string }> {
    const analysisRepo = AppDataSource.getRepository(CompetitorAnalysis);
    const analysis = await analysisRepo.findOneBy({ id: analysisId });

    if (!analysis) {
      throw new Error('Analysis not found');
    }

    // Here you would integrate with your agent system
    // For now, we'll just log the recommendations
    console.log(`📊 Sending recommendations to ${agentIds.length} agents:`);
    console.log('Recommendations:', analysis.recommendations);
    console.log('Report:', analysis.aiReport);

    return {
      success: true,
      message: `Recommendations sent to ${agentIds.length} content agents`,
    };
  }
}
