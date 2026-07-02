import { AppDataSource } from '../config/database';
import { SocialAgent } from '../entities/SocialAgent';
import { ContentPlan } from '../entities/ContentPlan';
import { ContentItem } from '../entities/ContentItem';
import { KnowledgeFile } from '../entities/KnowledgeFile';
import { AIProviderFactory } from './ai/AIProviderFactory';
import { IBrandKnowledge, IContentItem } from '../types';

export class SmmAgentService {
  private agentId: string;
  private socialAccountId: string;
  private projectId: string;
  private agent: SocialAgent;
  private brandKnowledge: IBrandKnowledge;

  async initialize(agentId: string, socialAccountId: string, projectId: string) {
    this.agentId = agentId;
    this.socialAccountId = socialAccountId;
    this.projectId = projectId;

    const agentRepo = AppDataSource.getRepository(SocialAgent);
    const agent = await agentRepo.findOneBy({ id: agentId });
    if (!agent) {
      throw new Error(`Agent not found: ${agentId}`);
    }
    this.agent = agent;

    await this.loadBrandKnowledge();
  }

  private async loadBrandKnowledge(): Promise<void> {
    const fileRepo = AppDataSource.getRepository(KnowledgeFile);
    const files = await fileRepo.findBy({ socialAccountId: this.socialAccountId });

    const parsedTexts = files
      .filter(f => f.parsedText)
      .map(f => f.parsedText)
      .join('\n\n');

    this.brandKnowledge = {
      businessDescription: parsedTexts,
      targetAudience: this.agent.brandRules.targetAudience || 'Not specified',
      tone: this.agent.toneOfVoice || 'professional',
      style: this.agent.brandRules.style || 'modern',
      mainOffers: this.agent.brandRules.offers || [],
      pastPosts: [],
      references: files.map(f => f.fileUrl),
    };
  }

  async createContentPlan(
    title: string,
    periodStart: Date,
    periodEnd: Date,
    userBriefing: string,
  ): Promise<ContentPlan> {
    const aiProvider = AIProviderFactory.getProvider(this.agent.aiProvider as any);

    const plan = await aiProvider.generateContentPlan(
      `${userBriefing}\n\nBrand Knowledge:\n${this.brandKnowledge.businessDescription}`,
      this.brandKnowledge.references,
    );

    const contentPlanRepo = AppDataSource.getRepository(ContentPlan);
    const contentPlan = contentPlanRepo.create({
      socialAccountId: this.socialAccountId,
      title,
      periodStart,
      periodEnd,
      status: 'draft',
      createdByAgentId: this.agentId,
    });

    return contentPlanRepo.save(contentPlan);
  }

  async generateContentItems(
    contentPlanId: string,
    count: number,
    platform: 'instagram' | 'telegram' | 'vk' | 'youtube' | 'tiktok',
  ): Promise<ContentItem[]> {
    const aiProvider = AIProviderFactory.getProvider(this.agent.aiProvider as any);

    const contentPlanRepo = AppDataSource.getRepository(ContentPlan);
    const plan = await contentPlanRepo.findOneBy({ id: contentPlanId });
    if (!plan) {
      throw new Error(`Content plan not found: ${contentPlanId}`);
    }

    const items: ContentItem[] = [];
    const contentItemRepo = AppDataSource.getRepository(ContentItem);

    for (let i = 0; i < count; i++) {
      const caption = await aiProvider.generateCaption(
        `Post ${i + 1} for ${platform}`,
        this.agent.toneOfVoice,
        this.brandKnowledge.businessDescription,
      );

      const imagePrompt = await aiProvider.generateImagePrompt(
        `Visual for post ${i + 1}`,
        this.agent.brandRules.style,
      );

      const publishAt = new Date(plan.periodStart);
      publishAt.setDate(publishAt.getDate() + Math.floor(i / 2));
      publishAt.setHours(i % 2 === 0 ? 12 : 19, 0, 0);

      const item = contentItemRepo.create({
        contentPlanId,
        platform,
        contentType: this.selectContentType(platform, i),
        title: `Post ${i + 1}`,
        caption,
        imagePrompt,
        hashtags: ['#content', '#social'],
        publishAt,
        status: 'draft',
        approvalStatus: 'pending',
      });

      items.push(item);
    }

    return contentItemRepo.save(items);
  }

  private selectContentType(
    platform: 'instagram' | 'telegram' | 'vk' | 'youtube' | 'tiktok',
    index: number,
  ): 'post' | 'story' | 'reel' | 'short' | 'carousel' {
    const typeMap = {
      instagram: ['post', 'story', 'reel', 'carousel'],
      telegram: ['post', 'carousel'],
      vk: ['post', 'carousel'],
      youtube: ['short'],
      tiktok: ['short'],
    };

    const types = typeMap[platform];
    return (types[index % types.length] as any) || 'post';
  }

  async approveContent(contentItemId: string): Promise<ContentItem> {
    const contentItemRepo = AppDataSource.getRepository(ContentItem);
    const item = await contentItemRepo.findOneBy({ id: contentItemId });
    if (!item) {
      throw new Error(`Content item not found: ${contentItemId}`);
    }

    item.approvalStatus = 'approved';
    item.status = 'approved';

    return contentItemRepo.save(item);
  }

  async publishContent(contentItemId: string): Promise<ContentItem> {
    const contentItemRepo = AppDataSource.getRepository(ContentItem);
    let item = await contentItemRepo.findOneBy({ id: contentItemId });
    if (!item) {
      throw new Error(`Content item not found: ${contentItemId}`);
    }

    item.status = 'publishing';
    item = await contentItemRepo.save(item);

    // TODO: Call platform-specific publisher
    // For now, just mark as published
    item.status = 'published';
    item.platformPostId = `mock_${Date.now()}`;

    return contentItemRepo.save(item);
  }
}
