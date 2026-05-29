import { Request, Response } from 'express';
import axios from 'axios';
import { PublishingService } from '../services/PublishingService';

export class AuthController {
  private publishingService = new PublishingService();

  // Instagram OAuth callback
  async instagramCallback(req: Request, res: Response) {
    try {
      const { code, state } = req.query;

      if (!code) {
        return res.status(400).json({ error: 'No code provided' });
      }

      // Exchange code for access token
      const response = await axios.post(
        'https://graph.instagram.com/v18.0/oauth/access_token',
        {
          client_id: process.env.INSTAGRAM_APP_ID,
          client_secret: process.env.INSTAGRAM_APP_SECRET,
          grant_type: 'authorization_code',
          redirect_uri: `${process.env.APP_URL}/auth/instagram/callback`,
          code,
        }
      );

      const accessToken = response.data.access_token;
      const userId = response.data.user_id;

      // Connect account
      const result = await this.publishingService.connectSocialAccount('instagram', {
        accessToken,
        igUserId: userId,
      } as any);

      // Redirect to success page
      res.redirect(
        `${process.env.WAI_APP_URL}/connected?account=${result.accountId}&platform=instagram`
      );
    } catch (error: any) {
      console.error('Instagram OAuth error:', error);
      res.status(500).json({ error: error.message });
    }
  }

  // Telegram token submission
  async telegramConnect(req: Request, res: Response) {
    try {
      const { botToken, chatId } = req.body;

      if (!botToken || !chatId) {
        return res.status(400).json({
          error: 'botToken and chatId are required',
        });
      }

      // Connect account
      const result = await this.publishingService.connectSocialAccount('telegram', {
        botToken,
        chatId,
      });

      res.json({
        success: true,
        accountId: result.accountId,
        accountName: result.accountName,
      });
    } catch (error: any) {
      console.error('Telegram connection error:', error);
      res.status(500).json({ error: error.message });
    }
  }

  // Get Instagram OAuth URL
  getInstagramOAuthUrl(req: Request, res: Response) {
    const appId = process.env.INSTAGRAM_APP_ID;
    const redirectUri = `${process.env.APP_URL}/auth/instagram/callback`;
    const scopes = [
      'instagram_basic',
      'instagram_content_publish',
      'pages_read_engagement',
    ].join(',');

    const oauthUrl = `https://api.instagram.com/oauth/authorize?client_id=${appId}&redirect_uri=${redirectUri}&scope=${scopes}&response_type=code`;

    res.json({ url: oauthUrl });
  }

  // VK OAuth callback
  async vkCallback(req: Request, res: Response) {
    try {
      const { code } = req.query;

      if (!code) {
        return res.status(400).json({ error: 'No code provided' });
      }

      // Exchange code for access token
      const response = await axios.get(
        'https://oauth.vk.com/access_token',
        {
          params: {
            client_id: process.env.VK_APP_ID,
            client_secret: process.env.VK_APP_SECRET,
            code,
            redirect_uri: `${process.env.APP_URL}/auth/vk/callback`,
          },
        }
      );

      const accessToken = response.data.access_token;
      const userId = response.data.user_id;

      // Connect account
      const result = await this.publishingService.connectSocialAccount('vk', {
        accessToken,
      });

      res.redirect(
        `${process.env.WAI_APP_URL}/connected?account=${result.accountId}&platform=vk`
      );
    } catch (error: any) {
      console.error('VK OAuth error:', error);
      res.status(500).json({ error: error.message });
    }
  }

  // Get VK OAuth URL
  getVkOAuthUrl(req: Request, res: Response) {
    const appId = process.env.VK_APP_ID;
    const redirectUri = `${process.env.APP_URL}/auth/vk/callback`;
    const scope = 'photos,wall,offline';

    const oauthUrl = `https://oauth.vk.com/authorize?client_id=${appId}&redirect_uri=${redirectUri}&scope=${scope}&response_type=code&v=5.131`;

    res.json({ url: oauthUrl });
  }
}
