import { Request, Response } from 'express';
import { AppDataSource } from '../config/database';
import { ContentItem } from '../entities/ContentItem';
import { SocialAccount } from '../entities/SocialAccount';
import { ContentPlan } from '../entities/ContentPlan';
import { AppSetting } from '../entities/AppSetting';
import { TokenEncryption } from '../utils/encryption';

// Non-secret preferences the Settings screen persists.
const PREFERENCE_KEYS = [
  'contentLanguage',
  'timezone',
  'aiProvider',
  'contentTone',
  'brandValues',
  'notifyScheduled',
  'notifyThreshold',
  'autoRespond',
] as const;

// Sensitive credentials (API keys / tokens). Stored encrypted, never returned in plaintext.
const SECRET_KEYS = [
  'anthropicApiKey',
  'openaiApiKey',
  'googleSearchApiKey',
  'googleSearchCx',
  'yandexApiKey',
  'yandexUser',
] as const;

export class APIController {
  // Content endpoints
  async listContent(req: Request, res: Response) {
    try {
      const { status, platform, planId, page = 1, limit = 20 } = req.query;
      const contentRepo = AppDataSource.getRepository(ContentItem);

      let query = contentRepo.createQueryBuilder('content');

      if (status) {
        query = query.andWhere('content.status = :status', {
          status: status as string,
        });
      }

      if (platform) {
        query = query.andWhere('content.platform = :platform', {
          platform: platform as string,
        });
      }

      if (planId) {
        query = query.andWhere('content.contentPlanId = :planId', {
          planId: planId as string,
        });
      }

      const total = await query.getCount();
      const skip = ((Number(page) || 1) - 1) * Number(limit);

      const items = await query
        .orderBy('content.publishAt', 'DESC')
        .skip(skip)
        .take(Number(limit))
        .getMany();

      res.json({
        success: true,
        total,
        page: Number(page),
        limit: Number(limit),
        items,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async getContent(req: Request, res: Response) {
    try {
      const { id } = req.params;
      const contentRepo = AppDataSource.getRepository(ContentItem);

      const item = await contentRepo.findOneBy({ id });

      if (!item) {
        return res.status(404).json({ error: 'Content not found' });
      }

      res.json({
        success: true,
        item,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async createContent(req: Request, res: Response) {
    try {
      const {
        contentPlanId,
        platform,
        contentType,
        title,
        caption,
        imageUrl,
        videoUrl,
        hashtags,
        publishAt,
      } = req.body;

      const contentRepo = AppDataSource.getRepository(ContentItem);

      if (!contentPlanId || !platform || !contentType || !title || !caption) {
        return res.status(400).json({
          error:
            'Missing required fields: contentPlanId, platform, contentType, title, caption',
        });
      }

      const item = contentRepo.create({
        contentPlanId,
        platform,
        contentType,
        title,
        caption,
        imageUrl: imageUrl || null,
        videoUrl: videoUrl || null,
        hashtags: hashtags || [],
        publishAt: new Date(publishAt),
        status: 'draft',
        approvalStatus: 'pending',
      });

      const saved = await contentRepo.save(item);

      res.status(201).json({
        success: true,
        item: saved,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async updateContent(req: Request, res: Response) {
    try {
      const { id } = req.params;
      const {
        title,
        caption,
        imageUrl,
        videoUrl,
        hashtags,
        publishAt,
        status,
        approvalStatus,
      } = req.body;

      const contentRepo = AppDataSource.getRepository(ContentItem);

      const item = await contentRepo.findOneBy({ id });

      if (!item) {
        return res.status(404).json({ error: 'Content not found' });
      }

      if (title) item.title = title;
      if (caption) item.caption = caption;
      if (imageUrl !== undefined) item.imageUrl = imageUrl;
      if (videoUrl !== undefined) item.videoUrl = videoUrl;
      if (hashtags) item.hashtags = hashtags;
      if (publishAt) item.publishAt = new Date(publishAt);
      if (status) item.status = status;
      if (approvalStatus) item.approvalStatus = approvalStatus;

      const updated = await contentRepo.save(item);

      res.json({
        success: true,
        item: updated,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async deleteContent(req: Request, res: Response) {
    try {
      const { id } = req.params;
      const contentRepo = AppDataSource.getRepository(ContentItem);

      const item = await contentRepo.findOneBy({ id });

      if (!item) {
        return res.status(404).json({ error: 'Content not found' });
      }

      await contentRepo.remove(item);

      res.json({
        success: true,
        message: 'Content deleted successfully',
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Social account endpoints
  async listSocialAccounts(req: Request, res: Response) {
    try {
      const accountRepo = AppDataSource.getRepository(SocialAccount);

      const accounts = await accountRepo.find({
        select: ['id', 'platform', 'accountName', 'status', 'createdAt'],
      });

      res.json({
        success: true,
        accounts,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async getSocialAccount(req: Request, res: Response) {
    try {
      const { id } = req.params;
      const accountRepo = AppDataSource.getRepository(SocialAccount);

      const account = await accountRepo.findOneBy({ id });

      if (!account) {
        return res.status(404).json({ error: 'Account not found' });
      }

      res.json({
        success: true,
        account,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Content plan endpoints
  async listContentPlans(req: Request, res: Response) {
    try {
      const planRepo = AppDataSource.getRepository(ContentPlan);

      const plans = await planRepo.find({
        order: { createdAt: 'DESC' },
      });

      res.json({
        success: true,
        plans,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async getContentPlan(req: Request, res: Response) {
    try {
      const { id } = req.params;
      const planRepo = AppDataSource.getRepository(ContentPlan);

      const plan = await planRepo.findOneBy({ id });

      if (!plan) {
        return res.status(404).json({ error: 'Plan not found' });
      }

      res.json({
        success: true,
        plan,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async createContentPlan(req: Request, res: Response) {
    try {
      const { title, periodStart, periodEnd, socialAccountId, createdByAgentId } = req.body;

      if (!title || !periodStart || !periodEnd) {
        return res.status(400).json({
          error: 'Missing required fields: title, periodStart, periodEnd',
        });
      }

      const planRepo = AppDataSource.getRepository(ContentPlan);

      const plan = planRepo.create({
        title,
        socialAccountId: socialAccountId || '',
        createdByAgentId: createdByAgentId || '',
        periodStart: new Date(periodStart),
        periodEnd: new Date(periodEnd),
        status: 'draft',
      });

      const saved = await planRepo.save(plan);

      res.status(201).json({
        success: true,
        plan: saved,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Social account: manual connect (stores a persisted connection so permissions stop re-prompting)
  async createSocialAccount(req: Request, res: Response) {
    try {
      const { platform, accountName, token } = req.body;

      if (!platform || !accountName) {
        return res
          .status(400)
          .json({ error: 'Missing required fields: platform, accountName' });
      }

      const accountRepo = AppDataSource.getRepository(SocialAccount);

      const account = accountRepo.create({
        userId: 'demo-user',
        projectId: 'demo',
        platform,
        accountName,
        status: 'connected',
        authType: token ? 'token' : 'oauth',
        accessTokenEncrypted: token ? TokenEncryption.encrypt(token) : '',
      });

      const saved = await accountRepo.save(account);

      // Never return the encrypted token to the client.
      const { accessTokenEncrypted, refreshTokenEncrypted, ...safe } = saved;
      res.status(201).json({ success: true, account: safe });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async deleteSocialAccount(req: Request, res: Response) {
    try {
      const { id } = req.params;
      const accountRepo = AppDataSource.getRepository(SocialAccount);

      const account = await accountRepo.findOneBy({ id });
      if (!account) {
        return res.status(404).json({ error: 'Account not found' });
      }

      await accountRepo.remove(account);
      res.json({ success: true, message: 'Account disconnected' });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Settings: return preferences plus a boolean "is set" map for secrets (never the secret values).
  async getSettings(req: Request, res: Response) {
    try {
      const repo = AppDataSource.getRepository(AppSetting);
      const rows = await repo.find();
      const byKey = new Map(rows.map((r) => [r.key, r]));

      const settings: Record<string, any> = {};
      for (const key of PREFERENCE_KEYS) {
        const row = byKey.get(key);
        settings[key] = row ? this.parseValue(row.value) : null;
      }

      const secrets: Record<string, boolean> = {};
      for (const key of SECRET_KEYS) {
        const row = byKey.get(key);
        secrets[key] = !!(row && row.value);
      }

      res.json({ success: true, settings, secrets });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Settings: upsert preferences and secrets. Empty secret values are ignored (do not overwrite).
  async updateSettings(req: Request, res: Response) {
    try {
      const repo = AppDataSource.getRepository(AppSetting);
      const { settings = {}, secrets = {} } = req.body || {};

      const upsert = async (key: string, value: string, isSecret: boolean) => {
        let row = await repo.findOneBy({ key });
        if (!row) {
          row = repo.create({ key });
        }
        row.value = value;
        row.isSecret = isSecret;
        await repo.save(row);
      };

      for (const key of PREFERENCE_KEYS) {
        if (key in settings && settings[key] !== undefined) {
          await upsert(key, this.stringifyValue(settings[key]), false);
        }
      }

      for (const key of SECRET_KEYS) {
        const raw = secrets[key];
        if (typeof raw === 'string' && raw.trim().length > 0) {
          await upsert(key, TokenEncryption.encrypt(raw.trim()), true);
        }
      }

      // Return the fresh, non-sensitive view.
      return this.getSettings(req, res);
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  private parseValue(value: string | null): any {
    if (value === null || value === undefined) return null;
    try {
      return JSON.parse(value);
    } catch {
      return value;
    }
  }

  private stringifyValue(value: any): string {
    return typeof value === 'string' ? value : JSON.stringify(value);
  }

  // Health check
  async health(req: Request, res: Response) {
    try {
      const isConnected = AppDataSource.isInitialized;

      res.json({
        success: true,
        status: isConnected ? 'healthy' : 'disconnected',
        database: isConnected ? 'connected' : 'not connected',
        timestamp: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }
}
