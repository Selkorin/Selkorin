import axios from 'axios';
import { LeadResult, saveLeads } from './LeadStorage';
import { LeadSearchParams } from './YandexMapsService';

export interface TelegramSearchParams extends LeadSearchParams {
  // Список юзернеймов/ссылок каналов для разбора публичных t.me-страниц
  // (используется, когда нет ключа TGStat для поиска по нише)
  usernames?: string[] | string;
}

/**
 * Сбор публичных бизнес-каналов/групп Telegram как лидов.
 *
 * Два режима:
 *  1) Поиск по нише через TGStat API (нужен TGSTAT_API_KEY, https://api.tgstat.ru).
 *  2) Без ключа: разбор публичных страниц t.me/<username> по заданному списку
 *     (title, описание, число подписчиков, внешний сайт из описания).
 *
 * ⚠️ Это сбор ПУБЛИЧНЫХ каналов бизнесов для B2B-аутрича. Здесь нет накрутки,
 *    автодействий и выгрузки персональных данных участников.
 */
export class TelegramParserService {
  private readonly tgstatKey: string;

  constructor() {
    this.tgstatKey = process.env.TGSTAT_API_KEY || '';
  }

  async search(params: TelegramSearchParams): Promise<{
    total: number;
    saved: number;
    leads: LeadResult[];
  }> {
    let leads: LeadResult[] = [];

    const usernames = this.normalizeUsernames(params.usernames);

    if (usernames.length > 0) {
      // Режим 2: разбор конкретных публичных страниц t.me
      for (const u of usernames) {
        const lead = await this.parsePublicPage(u, params);
        if (lead) leads.push(lead);
      }
    } else if (this.tgstatKey && params.niche) {
      // Режим 1: поиск по нише через TGStat
      leads = await this.searchTgStat(params);
    } else {
      throw new Error(
        'Для Telegram укажите либо список каналов (usernames), либо нишу + ключ ' +
          'TGSTAT_API_KEY (https://api.tgstat.ru) для поиска по нише'
      );
    }

    if (params.noWebsiteOnly) {
      leads = leads.filter((l) => !l.hasWebsite);
    }

    let saved = 0;
    if (params.save) {
      saved = await saveLeads(leads);
    }
    return { total: leads.length, saved, leads };
  }

  private normalizeUsernames(input?: string[] | string): string[] {
    if (!input) return [];
    const arr = Array.isArray(input) ? input : input.split(/[\s,;\n]+/);
    return arr
      .map((s) =>
        s
          .trim()
          .replace(/^https?:\/\/t\.me\//i, '')
          .replace(/^@/, '')
          .replace(/\/$/, '')
      )
      .filter(Boolean);
  }

  private extractWebsite(text: string): string {
    if (!text) return '';
    // Любая внешняя ссылка, кроме самого telegram
    const m = text.match(/https?:\/\/(?!t\.me|telegram\.me)[^\s"'<>]+/i);
    return m ? m[0] : '';
  }

  /**
   * Разбор публичной превью-страницы t.me/<username>.
   */
  private async parsePublicPage(
    username: string,
    params: TelegramSearchParams
  ): Promise<LeadResult | null> {
    try {
      const { data: html } = await axios.get(`https://t.me/${username}`, {
        timeout: 15000,
        headers: { 'User-Agent': 'Mozilla/5.0 (LeadGen Bot)' },
      });

      const meta = (prop: string) => {
        const re = new RegExp(
          `<meta[^>]+property=["']${prop}["'][^>]+content=["']([^"']*)["']`,
          'i'
        );
        return (html.match(re)?.[1] || '').trim();
      };

      const title = meta('og:title') || username;
      const description = meta('og:description');

      const subsMatch = html.match(
        /tgme_page_extra[^>]*>([^<]*?(?:subscriber|подписчик|member|участник)[^<]*)</i
      );
      const subs = subsMatch ? subsMatch[1].trim() : '';

      const website = this.extractWebsite(description);

      return {
        name: title,
        category: '',
        categories: '',
        address: '',
        phone: '',
        website,
        hasWebsite: Boolean(website),
        latitude: null,
        longitude: null,
        yandexUrl: `https://t.me/${username}`,
        hours: subs,
        niche: params.niche || '',
        region: params.region || '',
        source: 'telegram',
        rawData: { username, description, subs },
      };
    } catch {
      return null;
    }
  }

  /**
   * Поиск каналов по нише через TGStat API.
   */
  private async searchTgStat(
    params: TelegramSearchParams
  ): Promise<LeadResult[]> {
    const limit = Math.min(params.limit || 50, 50);
    const q = params.region
      ? `${params.niche} ${params.region}`
      : params.niche!;

    let items: any[] = [];
    try {
      const res = await axios.get('https://api.tgstat.ru/channels/search', {
        params: {
          token: this.tgstatKey,
          q,
          limit,
          country: 'ru',
        },
        timeout: 20000,
      });
      if (res.data?.status !== 'ok') {
        throw new Error(res.data?.error || 'TGStat вернул ошибку');
      }
      items = res.data?.response?.items || [];
    } catch (error: any) {
      throw new Error(`Ошибка запроса к TGStat: ${error.message}`);
    }

    return items
      .map((item: any) => {
        const ch = item.channel || item;
        const username = (ch.username || '').replace(/^@/, '');
        const description = ch.about || ch.description || '';
        const website = this.extractWebsite(description) || (ch.site || '');
        return {
          name: ch.title || username,
          category: ch.category || '',
          categories: ch.category || '',
          address: ch.country || '',
          phone: '',
          website,
          hasWebsite: Boolean(website),
          latitude: null,
          longitude: null,
          yandexUrl: username
            ? `https://t.me/${username}`
            : ch.link || '',
          hours: ch.participants_count
            ? `${ch.participants_count} подписчиков`
            : '',
          niche: params.niche || '',
          region: params.region || '',
          source: 'telegram',
          rawData: ch,
        } as LeadResult;
      })
      .filter((l) => l.name);
  }
}
