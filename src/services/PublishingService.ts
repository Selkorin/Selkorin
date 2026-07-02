import { AppDataSource } from '../config/database';
import { SocialAccount } from '../entities/SocialAccount';
import { ContentItem } from '../entities/ContentItem';
import { ContentPlan } from '../entities/ContentPlan';
import { PublishingHistory } from '../entities/PublishingHistory';
import { TelegramAdapter } from '../adapters/TelegramAdapter';
import { InstagramAdapter } from '../adapters/InstagramAdapter';
import { TokenEncryption } from '../utils/encryption';
import { IPublishingAdapter } from '../adapters/IPublishingAdapter';

export class PublishingService {
  async publishContentItem(contentItemId: string): Promise<{ postId: string; url: string }> {
    const contentItemRepo = AppDataSource.getRepository(ContentItem);
    const socialAccountRepo = AppDataSource.getRepository(SocialAccount);

    const contentItem = await contentItemRepo.findOneBy({ id: contentItemId });
    if (!contentItem) {
      throw new Error('Content item not found');
    }

    // Check approval status
    if (contentItem.approvalStatus !== 'approved') {
      throw new Error('Content not approved for publishing');
    }

    // Find the social account
    const contentPlan = await AppDataSource.getRepository(ContentPlan)
      .findOneBy({ id: contentItem.contentPlanId });
    if (!contentPlan) {
      throw new Error('Content plan not found');
    }
    const socialAccount = await socialAccountRepo.findOneBy({
      id: contentPlan.socialAccountId,
    });

    if (!socialAccount) {
      throw new Error('Social account not found');
    }

    // Get adapter for platform
    const adapter = this.getAdapter(socialAccount);

    // Validate token
    const isValid = await adapter.validateToken();
    if (!isValid) {
      throw new Error(`${socialAccount.platform} token is invalid`);
    }

    try {
      // Publish
      contentItem.status = 'publishing';
      await contentItemRepo.save(contentItem);

      const result = await adapter.publishPost({
        caption: contentItem.caption,
        imageUrl: contentItem.imageUrl,
        videoUrl: contentItem.videoUrl,
        hashtags: contentItem.hashtags,
      });

      // Update content item
      contentItem.status = 'published';
      contentItem.platformPostId = result.postId;
      await contentItemRepo.save(contentItem);

      // Save to publishing history
      const historyRepo = AppDataSource.getRepository(PublishingHistory);
      const history = historyRepo.create({
        contentItemId: contentItem.id,
        socialAccountId: contentPlan.socialAccountId,
        platform: contentItem.platform,
        platformPostId: result.postId,
        postUrl: result.url,
        status: 'success',
        contentSnapshot: {
          title: contentItem.title,
          caption: contentItem.caption,
          hashtags: contentItem.hashtags || [],
          imageUrl: contentItem.imageUrl,
          videoUrl: contentItem.videoUrl,
        },
      });
      await historyRepo.save(history);

      return result;
    } catch (error: any) {
      contentItem.status = 'failed';
      contentItem.errorMessage = error.message;
      await contentItemRepo.save(contentItem);

      // Save failed attempt to history
      const historyRepo = AppDataSource.getRepository(PublishingHistory);
      const history = historyRepo.create({
        contentItemId: contentItem.id,
        socialAccountId: contentPlan.socialAccountId,
        platform: contentItem.platform,
        platformPostId: '',
        postUrl: '',
        status: 'failed',
        errorMessage: error.message,
        contentSnapshot: {
          title: contentItem.title,
          caption: contentItem.caption,
          hashtags: contentItem.hashtags || [],
          imageUrl: contentItem.imageUrl,
          videoUrl: contentItem.videoUrl,
        },
      });
      await historyRepo.save(history);

      throw error;
    }
  }

  async connectSocialAccount(
    platform: string,
    credentials: {
      accessToken?: string;
      refreshToken?: string;
      botToken?: string;
      chatId?: string;
      igUserId?: string;
    }
  ): Promise<{ accountId: string; accountName: string }> {
    // Validate credentials
    const adapter = this.createTemporaryAdapter(platform, credentials);
    const isValid = await adapter.validateToken();

    if (!isValid) {
      throw new Error(`Invalid ${platform} credentials`);
    }

    // Get account info
    const accountInfo = await adapter.getAccountInfo();

    // Get or create social account
    const socialAccountRepo = AppDataSource.getRepository(SocialAccount);

    let socialAccount = await socialAccountRepo.findOneBy({
      platform: platform as any,
      accountName: accountInfo.name,
    });

    if (!socialAccount) {
      socialAccount = socialAccountRepo.create({
        platform: platform as any,
        accountName: accountInfo.name,
        accountAvatar: '',
        status: 'connected',
        authType: credentials.botToken ? 'bot_token' : 'oauth',
        accessTokenEncrypted: credentials.accessToken
          ? TokenEncryption.encrypt(credentials.accessToken)
          : '',
        refreshTokenEncrypted: credentials.refreshToken
          ? TokenEncryption.encrypt(credentials.refreshToken)
          : '',
      });
    } else {
      if (credentials.accessToken) {
        socialAccount.accessTokenEncrypted = TokenEncryption.encrypt(
          credentials.accessToken
        );
      }
      if (credentials.botToken) {
        socialAccount.accessTokenEncrypted = TokenEncryption.encrypt(
          credentials.botToken
        );
      }
      socialAccount.status = 'connected';
    }

    await socialAccountRepo.save(socialAccount);

    return {
      accountId: socialAccount.id,
      accountName: socialAccount.accountName,
    };
  }

  private getAdapter(socialAccount: SocialAccount): IPublishingAdapter {
    const decryptedToken = TokenEncryption.decrypt(
      socialAccount.accessTokenEncrypted
    );

    switch (socialAccount.platform) {
      case 'telegram':
        return new TelegramAdapter(decryptedToken, decryptedToken);
      case 'instagram':
        // In real implementation, you'd store igUserId separately
        return new InstagramAdapter(decryptedToken, socialAccount.id);
      default:
        throw new Error(`Unsupported platform: ${socialAccount.platform}`);
    }
  }

  private createTemporaryAdapter(
    platform: string,
    credentials: any
  ): IPublishingAdapter {
    if (platform === 'telegram') {
      return new TelegramAdapter(credentials.botToken, credentials.chatId);
    } else if (platform === 'instagram') {
      return new InstagramAdapter(credentials.accessToken, credentials.igUserId || '');
    }
    throw new Error(`Unsupported platform: ${platform}`);
  }
}
