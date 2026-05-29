import { Request, Response } from 'express';
import { GoogleDriveService } from '../services/GoogleDriveService';
import { AppDataSource } from '../config/database';
import { ContentItem } from '../entities/ContentItem';

export class GoogleDriveController {
  private driveService = new GoogleDriveService({
    clientId: process.env.GOOGLE_CLIENT_ID || '',
    clientSecret: process.env.GOOGLE_CLIENT_SECRET || '',
    redirectUrl: process.env.GOOGLE_REDIRECT_URL || 'http://localhost:3000/auth/google/callback',
  });

  // Get Google Drive OAuth URL
  getGoogleDriveAuthUrl(req: Request, res: Response) {
    try {
      const authUrl = this.driveService.getAuthUrl();
      res.json({
        success: true,
        authUrl,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Handle Google Drive OAuth callback
  async googleDriveCallback(req: Request, res: Response) {
    try {
      const { code } = req.query;

      if (!code) {
        return res.status(400).json({ error: 'No authorization code provided' });
      }

      const tokens = await this.driveService.getTokensFromCode(code as string);

      res.json({
        success: true,
        message: 'Google Drive connected successfully',
        tokens,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Upload content item to Google Drive
  async uploadToGoogleDrive(req: Request, res: Response) {
    try {
      const { contentItemId, accessToken } = req.body;

      if (!contentItemId || !accessToken) {
        return res.status(400).json({
          error: 'contentItemId and accessToken required',
        });
      }

      const contentRepo = AppDataSource.getRepository(ContentItem);
      const content = await contentRepo.findOneBy({ id: contentItemId });

      if (!content) {
        return res.status(404).json({ error: 'Content item not found' });
      }

      this.driveService.setCredentials({ access_token: accessToken });

      const file = await this.driveService.uploadContentFile(contentItemId, content);

      // Update content item with Google Drive file ID
      content.googleDriveFileId = file.id;
      await contentRepo.save(content);

      res.json({
        success: true,
        message: 'Content uploaded to Google Drive',
        file,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Download content item from Google Drive
  async downloadFromGoogleDrive(req: Request, res: Response) {
    try {
      const { contentItemId, accessToken } = req.body;

      if (!contentItemId || !accessToken) {
        return res.status(400).json({
          error: 'contentItemId and accessToken required',
        });
      }

      this.driveService.setCredentials({ access_token: accessToken });

      const contentData = await this.driveService.downloadContentFile(contentItemId);

      res.json({
        success: true,
        data: contentData,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Sync content plan with Google Drive
  async syncContentPlan(req: Request, res: Response) {
    try {
      const { contentPlanId, accessToken } = req.body;

      if (!contentPlanId || !accessToken) {
        return res.status(400).json({
          error: 'contentPlanId and accessToken required',
        });
      }

      const contentRepo = AppDataSource.getRepository(ContentItem);
      const contents = await contentRepo.find({
        where: { contentPlanId },
      });

      this.driveService.setCredentials({ access_token: accessToken });

      const uploadedFiles = [];

      for (const content of contents) {
        try {
          const file = await this.driveService.uploadContentFile(content.id, content);
          content.googleDriveFileId = file.id;
          await contentRepo.save(content);
          uploadedFiles.push(file);
        } catch (error: any) {
          console.error(`Failed to upload content ${content.id}:`, error.message);
        }
      }

      res.json({
        success: true,
        message: `Synced ${uploadedFiles.length} items to Google Drive`,
        count: uploadedFiles.length,
        files: uploadedFiles,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // List content files in Google Drive
  async listGoogleDriveFiles(req: Request, res: Response) {
    try {
      const { accessToken } = req.query;

      if (!accessToken) {
        return res.status(400).json({ error: 'accessToken query parameter required' });
      }

      this.driveService.setCredentials({ access_token: accessToken as string });

      const files = await this.driveService.listContentFiles();

      res.json({
        success: true,
        count: files.length,
        files,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Delete content from Google Drive
  async deleteFromGoogleDrive(req: Request, res: Response) {
    try {
      const { contentItemId, accessToken } = req.body;

      if (!contentItemId || !accessToken) {
        return res.status(400).json({
          error: 'contentItemId and accessToken required',
        });
      }

      this.driveService.setCredentials({ access_token: accessToken });

      const deleted = await this.driveService.deleteContentFile(contentItemId);

      if (!deleted) {
        return res.status(404).json({ error: 'File not found in Google Drive' });
      }

      // Clear Google Drive file ID from content item
      const contentRepo = AppDataSource.getRepository(ContentItem);
      const content = await contentRepo.findOneBy({ id: contentItemId });

      if (content) {
        content.googleDriveFileId = null as any;
        await contentRepo.save(content);
      }

      res.json({
        success: true,
        message: 'Content deleted from Google Drive',
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // Share Google Drive content with user
  async shareWithUser(req: Request, res: Response) {
    try {
      const { contentItemId, email, accessToken, role } = req.body;

      if (!contentItemId || !email || !accessToken) {
        return res.status(400).json({
          error: 'contentItemId, email, and accessToken required',
        });
      }

      const contentRepo = AppDataSource.getRepository(ContentItem);
      const content = await contentRepo.findOneBy({ id: contentItemId });

      if (!content || !content.googleDriveFileId) {
        return res.status(404).json({ error: 'Content not found or not synced to Google Drive' });
      }

      this.driveService.setCredentials({ access_token: accessToken });

      await this.driveService.shareWithUser(content.googleDriveFileId, email, role || 'reader');

      res.json({
        success: true,
        message: `Content shared with ${email}`,
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }
}
