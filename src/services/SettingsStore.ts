import { AppDataSource } from '../config/database';
import { AppSetting } from '../entities/AppSetting';
import { TokenEncryption } from '../utils/encryption';

/**
 * Resolves configuration values, preferring a value saved through the Settings UI
 * (stored encrypted in app_settings) and falling back to an environment variable.
 */
export class SettingsStore {
  static async getSecret(key: string, envVar?: string): Promise<string | undefined> {
    try {
      if (AppDataSource.isInitialized) {
        const row = await AppDataSource.getRepository(AppSetting).findOneBy({ key });
        if (row && row.value) {
          return row.isSecret ? TokenEncryption.decrypt(row.value) : row.value;
        }
      }
    } catch {
      // Fall through to env — a decryption/DB error should not break the feature.
    }
    if (envVar && process.env[envVar]) return process.env[envVar];
    return undefined;
  }
}
