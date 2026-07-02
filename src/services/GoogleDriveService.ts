import { google } from 'googleapis';
import { OAuth2Client } from 'google-auth-library';
import * as fs from 'fs';
import * as path from 'path';

export interface GoogleDriveConfig {
  clientId: string;
  clientSecret: string;
  redirectUrl: string;
}

export interface ContentFile {
  id: string;
  name: string;
  mimeType: string;
  webViewLink: string;
  createdTime: Date;
  modifiedTime: Date;
  content?: string;
}

export class GoogleDriveService {
  private oauth2Client: OAuth2Client;
  private drive: any;
  private contentFolderId: string = '';

  constructor(config: GoogleDriveConfig) {
    this.oauth2Client = new google.auth.OAuth2(
      config.clientId,
      config.clientSecret,
      config.redirectUrl
    );

    this.drive = google.drive({ version: 'v3', auth: this.oauth2Client });
  }

  // Set OAuth tokens
  setCredentials(tokens: any) {
    this.oauth2Client.setCredentials(tokens);
  }

  // Get authorization URL
  getAuthUrl(scopes: string[] = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive',
  ]): string {
    return this.oauth2Client.generateAuthUrl({
      access_type: 'offline',
      scope: scopes,
    });
  }

  // Get tokens from authorization code
  async getTokensFromCode(code: string): Promise<any> {
    const { tokens } = await this.oauth2Client.getToken(code);
    this.oauth2Client.setCredentials(tokens);
    return tokens;
  }

  // Create or get the WAI Social content folder
  async ensureContentFolder(): Promise<string> {
    if (this.contentFolderId) {
      return this.contentFolderId;
    }

    const folderName = 'WAI Social Content';

    // Search for existing folder
    const res = await this.drive.files.list({
      q: `name='${folderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false`,
      spaces: 'drive',
      fields: 'files(id, name)',
      pageSize: 1,
    });

    if (res.data.files && res.data.files.length > 0) {
      this.contentFolderId = res.data.files[0].id ?? '';
      return this.contentFolderId;
    }

    // Create new folder
    const folderRes = await this.drive.files.create({
      resource: {
        name: folderName,
        mimeType: 'application/vnd.google-apps.folder',
      },
      fields: 'id',
    });

    this.contentFolderId = folderRes.data.id ?? '';
    return this.contentFolderId;
  }

  // Upload content as JSON file
  async uploadContentFile(contentId: string, contentData: any): Promise<ContentFile> {
    const folderId = await this.ensureContentFolder();

    const fileName = `content-${contentId}.json`;
    const fileContent = JSON.stringify(contentData, null, 2);

    // Check if file exists
    const existingRes = await this.drive.files.list({
      q: `name='${fileName}' and '${folderId}' in parents and trashed=false`,
      spaces: 'drive',
      fields: 'files(id)',
      pageSize: 1,
    });

    let fileId: string;

    if (existingRes.data.files && existingRes.data.files.length > 0) {
      // Update existing file
      fileId = existingRes.data.files[0].id;
      await this.drive.files.update({
        fileId,
        media: {
          mimeType: 'application/json',
          body: fileContent,
        },
      });
    } else {
      // Create new file
      const res = await this.drive.files.create({
        resource: {
          name: fileName,
          parents: [folderId],
          mimeType: 'application/json',
        },
        media: {
          mimeType: 'application/json',
          body: fileContent,
        },
        fields: 'id, name, mimeType, webViewLink, createdTime, modifiedTime',
      });
      fileId = res.data.id;
    }

    // Get file details
    const fileRes = await this.drive.files.get({
      fileId,
      fields: 'id, name, mimeType, webViewLink, createdTime, modifiedTime',
    });

    return {
      id: fileRes.data.id,
      name: fileRes.data.name,
      mimeType: fileRes.data.mimeType,
      webViewLink: fileRes.data.webViewLink,
      createdTime: new Date(fileRes.data.createdTime),
      modifiedTime: new Date(fileRes.data.modifiedTime),
    };
  }

  // Download content file
  async downloadContentFile(contentId: string): Promise<any> {
    const folderId = await this.ensureContentFolder();
    const fileName = `content-${contentId}.json`;

    const res = await this.drive.files.list({
      q: `name='${fileName}' and '${folderId}' in parents and trashed=false`,
      spaces: 'drive',
      fields: 'files(id)',
      pageSize: 1,
    });

    if (!res.data.files || res.data.files.length === 0) {
      throw new Error(`Content file not found: ${fileName}`);
    }

    const fileId = res.data.files[0].id;

    const fileRes = await this.drive.files.get({
      fileId,
      alt: 'media',
    });

    return fileRes.data;
  }

  // List all content files
  async listContentFiles(): Promise<ContentFile[]> {
    const folderId = await this.ensureContentFolder();

    const res = await this.drive.files.list({
      q: `'${folderId}' in parents and name like 'content-%' and trashed=false`,
      spaces: 'drive',
      fields: 'files(id, name, mimeType, webViewLink, createdTime, modifiedTime)',
      pageSize: 100,
    });

    return (res.data.files || []).map((file: any) => ({
      id: file.id,
      name: file.name,
      mimeType: file.mimeType,
      webViewLink: file.webViewLink,
      createdTime: new Date(file.createdTime),
      modifiedTime: new Date(file.modifiedTime),
    }));
  }

  // Upload asset file (image/video)
  async uploadAsset(filePath: string, fileName: string): Promise<ContentFile> {
    const folderId = await this.ensureContentFolder();
    const assetsFolderId = await this.ensureSubFolder(folderId, 'Assets');

    const fileContent = fs.readFileSync(filePath);
    const mimeType = this.getMimeType(filePath);

    const res = await this.drive.files.create({
      resource: {
        name: fileName,
        parents: [assetsFolderId],
      },
      media: {
        mimeType,
        body: fileContent,
      },
      fields: 'id, name, mimeType, webViewLink, createdTime, modifiedTime',
    });

    return {
      id: res.data.id,
      name: res.data.name,
      mimeType: res.data.mimeType,
      webViewLink: res.data.webViewLink,
      createdTime: new Date(res.data.createdTime),
      modifiedTime: new Date(res.data.modifiedTime),
    };
  }

  // Delete content file
  async deleteContentFile(contentId: string): Promise<boolean> {
    const folderId = await this.ensureContentFolder();
    const fileName = `content-${contentId}.json`;

    const res = await this.drive.files.list({
      q: `name='${fileName}' and '${folderId}' in parents`,
      spaces: 'drive',
      fields: 'files(id)',
      pageSize: 1,
    });

    if (!res.data.files || res.data.files.length === 0) {
      return false;
    }

    const fileId = res.data.files[0].id;
    await this.drive.files.delete({ fileId });

    return true;
  }

  // Share file/folder with email
  async shareWithUser(fileId: string, email: string, role: string = 'reader'): Promise<void> {
    await this.drive.permissions.create({
      fileId,
      resource: {
        kind: 'drive#permission',
        type: 'user',
        role,
        emailAddress: email,
      },
      sendNotificationEmail: true,
    });
  }

  // Private helper methods
  private async ensureSubFolder(parentId: string, folderName: string): Promise<string> {
    const res = await this.drive.files.list({
      q: `name='${folderName}' and '${parentId}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false`,
      spaces: 'drive',
      fields: 'files(id)',
      pageSize: 1,
    });

    if (res.data.files && res.data.files.length > 0) {
      return res.data.files[0].id;
    }

    const folderRes = await this.drive.files.create({
      resource: {
        name: folderName,
        parents: [parentId],
        mimeType: 'application/vnd.google-apps.folder',
      },
      fields: 'id',
    });

    return folderRes.data.id;
  }

  private getMimeType(filePath: string): string {
    const ext = path.extname(filePath).toLowerCase();
    const mimeTypes: Record<string, string> = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.mp4': 'video/mp4',
      '.webm': 'video/webm',
      '.pdf': 'application/pdf',
    };
    return mimeTypes[ext] || 'application/octet-stream';
  }
}
