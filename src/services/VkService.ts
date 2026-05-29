import axios from 'axios';
import { LeadResult, saveLeads } from './LeadStorage';
import { LeadSearchParams } from './YandexMapsService';

/**
 * Сбор бизнес-сообществ из ВКонтакте через официальный VK API.
 *
 * Логика лид-гена: ищем публичные сообщества/страницы по нише (groups.search),
 * обогащаем их публичными контактами (groups.getById) и складываем как лиды.
 * Фильтр "без сайта" = у сообщества не указан внешний сайт (поле site).
 *
 * Нужен service-токен VK-приложения (https://dev.vk.com/) в VK_SERVICE_TOKEN
 * (или пользовательский токен в VK_ACCESS_TOKEN).
 */
export class VkService {
  private readonly apiUrl = 'https://api.vk.com/method';
  private readonly apiVersion = '5.199';
  private readonly token: string;
  private readonly PAGE_SIZE = 1000; // максимум groups.search
  private readonly MAX_RESULTS = 1000;

  constructor() {
    this.token =
      process.env.VK_SERVICE_TOKEN || process.env.VK_ACCESS_TOKEN || '';
  }

  isConfigured(): boolean {
    return Boolean(this.token);
  }

  private async call(method: string, params: Record<string, any>) {
    const response = await axios.get(`${this.apiUrl}/${method}`, {
      params: { ...params, access_token: this.token, v: this.apiVersion },
      timeout: 20000,
    });
    if (response.data?.error) {
      const e = response.data.error;
      throw new Error(`VK API ${e.error_code}: ${e.error_msg}`);
    }
    return response.data?.response;
  }

  async search(params: LeadSearchParams): Promise<{
    total: number;
    saved: number;
    leads: LeadResult[];
  }> {
    if (!this.isConfigured()) {
      throw new Error(
        'VK_SERVICE_TOKEN не задан. Создайте приложение на https://dev.vk.com/ ' +
          'и получите сервисный ключ доступа, добавьте его в .env'
      );
    }
    if (!params.niche || !params.niche.trim()) {
      throw new Error('Не указана ниша (niche) для поиска');
    }

    const q = params.region
      ? `${params.niche} ${params.region}`
      : params.niche;
    const targetLimit = Math.min(
      params.limit || this.MAX_RESULTS,
      this.MAX_RESULTS
    );

    // 1) Поиск сообществ
    const ids: string[] = [];
    for (let offset = 0; offset < targetLimit; offset += this.PAGE_SIZE) {
      const count = Math.min(this.PAGE_SIZE, targetLimit - offset);
      const res = await this.call('groups.search', {
        q,
        type: 'group',
        count,
        offset,
      });
      const items = res?.items || [];
      for (const it of items) ids.push(String(it.id));
      if (items.length < count) break;
    }

    if (ids.length === 0) {
      return { total: 0, saved: 0, leads: [] };
    }

    // 2) Обогащение контактами (чанками по 500)
    const collected: LeadResult[] = [];
    const fields =
      'activity,description,contacts,site,members_count,city,addresses,screen_name';

    for (let i = 0; i < ids.length; i += 500) {
      const chunk = ids.slice(i, i + 500);
      const res = await this.call('groups.getById', {
        group_ids: chunk.join(','),
        fields,
      });
      // VK может вернуть либо массив, либо { groups: [...] }
      const groups = Array.isArray(res) ? res : res?.groups || [];
      for (const g of groups) {
        const lead = this.mapGroup(g, params);
        if (!lead) continue;
        if (params.noWebsiteOnly && lead.hasWebsite) continue;
        collected.push(lead);
      }
    }

    let saved = 0;
    if (params.save) {
      saved = await saveLeads(collected);
    }
    return { total: collected.length, saved, leads: collected };
  }

  private mapGroup(g: any, params: LeadSearchParams): LeadResult | null {
    if (!g?.name) return null;

    const phones: string[] = Array.isArray(g.contacts)
      ? g.contacts.map((c: any) => c.phone).filter(Boolean)
      : [];
    const website: string = (g.site || '').trim();
    const screen = g.screen_name || `club${g.id}`;
    const city = g.city?.title || '';

    return {
      name: g.name,
      category: g.activity || '',
      categories: g.activity || '',
      address: city,
      phone: phones.join(', '),
      website,
      hasWebsite: Boolean(website),
      latitude: null,
      longitude: null,
      yandexUrl: `https://vk.com/${screen}`,
      hours: g.members_count ? `${g.members_count} подписчиков` : '',
      niche: params.niche,
      region: params.region || '',
      source: 'vk',
      rawData: g,
    };
  }
}
