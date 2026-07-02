import axios from 'axios';
import { ISearchProvider, SearchResult } from './ISearchProvider';
import { SettingsStore } from '../SettingsStore';

/**
 * Yandex XML search API (https://yandex.com/dev/xml/).
 * Requires a Yandex user login and an API key. Returns XML which we parse
 * defensively without an external XML dependency.
 */
export class YandexSearchProvider implements ISearchProvider {
  readonly name = 'yandex';

  async isConfigured(): Promise<boolean> {
    const key = await SettingsStore.getSecret('yandexApiKey', 'YANDEX_API_KEY');
    const user = await SettingsStore.getSecret('yandexUser', 'YANDEX_USER');
    return !!(key && user);
  }

  async search(query: string, limit: number): Promise<SearchResult[]> {
    const key = await SettingsStore.getSecret('yandexApiKey', 'YANDEX_API_KEY');
    const user = await SettingsStore.getSecret('yandexUser', 'YANDEX_USER');
    if (!key || !user) {
      throw new Error('Yandex search is not configured (missing API key or user).');
    }

    const { data } = await axios.get('https://yandex.com/search/xml', {
      params: { user, key, query, l10n: 'en', filter: 'strict' },
      responseType: 'text',
      timeout: 15000,
    });

    return this.parseXml(String(data)).slice(0, Math.max(limit, 1));
  }

  private parseXml(xml: string): SearchResult[] {
    const results: SearchResult[] = [];
    const docRegex = /<doc[\s\S]*?<\/doc>/g;
    const docs = xml.match(docRegex) || [];

    for (const doc of docs) {
      const url = this.extract(doc, 'url');
      const title = this.stripTags(this.extract(doc, 'title'));
      const passages = (doc.match(/<passage[\s\S]*?<\/passage>/g) || [])
        .map((p) => this.stripTags(p))
        .join(' ');
      const headline = this.stripTags(this.extract(doc, 'headline'));
      const snippet = (passages || headline).trim();
      if (url) {
        results.push({ title: title || url, url, snippet });
      }
    }
    return results;
  }

  private extract(block: string, tag: string): string {
    const m = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`));
    return m ? m[1] : '';
  }

  private stripTags(s: string): string {
    return s
      .replace(/<[^>]+>/g, '')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/\s+/g, ' ')
      .trim();
  }
}
