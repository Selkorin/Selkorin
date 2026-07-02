import axios from 'axios';
import { ISearchProvider, SearchResult } from './ISearchProvider';
import { SettingsStore } from '../SettingsStore';

/**
 * Google Programmable Search (Custom Search JSON API).
 * Requires an API key and a Search Engine ID (cx). This is the ToS-compliant
 * way to query Google results, instead of scraping the HTML SERP.
 * https://developers.google.com/custom-search/v1/overview
 */
export class GoogleSearchProvider implements ISearchProvider {
  readonly name = 'google';

  async isConfigured(): Promise<boolean> {
    const key = await SettingsStore.getSecret('googleSearchApiKey', 'GOOGLE_SEARCH_API_KEY');
    const cx = await SettingsStore.getSecret('googleSearchCx', 'GOOGLE_SEARCH_CX');
    return !!(key && cx);
  }

  async search(query: string, limit: number): Promise<SearchResult[]> {
    const key = await SettingsStore.getSecret('googleSearchApiKey', 'GOOGLE_SEARCH_API_KEY');
    const cx = await SettingsStore.getSecret('googleSearchCx', 'GOOGLE_SEARCH_CX');
    if (!key || !cx) {
      throw new Error('Google search is not configured (missing API key or CX).');
    }

    const num = Math.min(Math.max(limit, 1), 10); // API caps num at 10 per call
    const { data } = await axios.get('https://www.googleapis.com/customsearch/v1', {
      params: { key, cx, q: query, num },
      timeout: 15000,
    });

    const items = Array.isArray(data.items) ? data.items : [];
    return items.map((it: any) => ({
      title: it.title || '',
      url: it.link || '',
      snippet: it.snippet || '',
    }));
  }
}
