import axios from 'axios';
import { LeadResult, saveLeads } from './LeadStorage';
import { LeadSearchParams } from './YandexMapsService';

/**
 * Сервис сбора компаний через официальный 2GIS Catalog API (Places).
 *
 * Документация: https://docs.2gis.com/ru/api/search/places/overview
 * Ключ выдаётся в кабинете: https://dev.2gis.com/ (продукт "Places API / Catalog API").
 */
export class TwoGisService {
  private readonly apiUrl = 'https://catalog.api.2gis.com/3.0/items';
  private readonly apiKey: string;
  // 2ГИС отдаёт максимум 50 объектов на страницу
  private readonly PAGE_SIZE = 50;
  // Глубина выдачи у 2ГИС ограничена (примерно 10 страниц по 50 = 500)
  private readonly MAX_RESULTS = 500;
  // Какие поля просим вернуть
  private readonly FIELDS =
    'items.point,items.contact_groups,items.rubrics,items.address,items.full_address_name,items.schedule';

  constructor() {
    this.apiKey = process.env.TWOGIS_API_KEY || '';
  }

  isConfigured(): boolean {
    return Boolean(this.apiKey);
  }

  async search(params: LeadSearchParams): Promise<{
    total: number;
    saved: number;
    leads: LeadResult[];
  }> {
    if (!this.isConfigured()) {
      throw new Error(
        'TWOGIS_API_KEY не задан. Получите ключ Places/Catalog API ' +
          'в кабинете https://dev.2gis.com/ и добавьте его в .env'
      );
    }

    if (!params.niche || !params.niche.trim()) {
      throw new Error('Не указана ниша (niche) для поиска');
    }

    const q = params.region ? `${params.niche} ${params.region}` : params.niche;
    const targetLimit = Math.min(
      params.limit || this.MAX_RESULTS,
      this.MAX_RESULTS
    );

    const collected: LeadResult[] = [];
    const seen = new Set<string>();
    const maxPages = Math.ceil(targetLimit / this.PAGE_SIZE);

    for (let page = 1; page <= maxPages; page++) {
      const query: Record<string, any> = {
        key: this.apiKey,
        q,
        page,
        page_size: this.PAGE_SIZE,
        fields: this.FIELDS,
        locale: 'ru_RU',
      };

      let items: any[] = [];
      try {
        const response = await axios.get(this.apiUrl, {
          params: query,
          timeout: 20000,
        });

        const apiMeta = response.data?.meta;
        // 2ГИС возвращает код 404 в meta когда по запросу ничего не найдено
        if (apiMeta?.code && apiMeta.code >= 400 && apiMeta.code !== 404) {
          throw new Error(
            `2GIS API error ${apiMeta.code}: ${apiMeta?.error?.message || ''}`
          );
        }
        items = response.data?.result?.items || [];
      } catch (error: any) {
        const status = error.response?.status;
        if (status === 403) {
          throw new Error('2GIS API вернул 403: ключ недействителен или не активирован');
        }
        if (status === 404) {
          // ничего не найдено на этой странице — завершаем
          break;
        }
        throw new Error(`Ошибка запроса к 2GIS API: ${error.message}`);
      }

      if (items.length === 0) break;

      for (const item of items) {
        const lead = this.mapItem(item, params);
        if (!lead) continue;

        if (params.noWebsiteOnly && lead.hasWebsite) continue;

        const key = `${lead.name}|${lead.address}`.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);

        collected.push(lead);
      }

      if (items.length < this.PAGE_SIZE) break;
    }

    let saved = 0;
    if (params.save) {
      saved = await saveLeads(collected);
    }

    return { total: collected.length, saved, leads: collected };
  }

  /**
   * Преобразует один объект 2ГИС в унифицированный лид.
   */
  private mapItem(item: any, params: LeadSearchParams): LeadResult | null {
    if (!item?.name) return null;

    const rubrics: string[] = Array.isArray(item.rubrics)
      ? item.rubrics.map((r: any) => r.name).filter(Boolean)
      : [];

    // Контакты лежат в contact_groups[].contacts[] с типами phone/website
    const phones: string[] = [];
    let website = '';
    const groups = Array.isArray(item.contact_groups) ? item.contact_groups : [];
    for (const group of groups) {
      const contacts = Array.isArray(group.contacts) ? group.contacts : [];
      for (const c of contacts) {
        if (c.type === 'phone' && (c.value || c.text)) {
          phones.push(c.value || c.text);
        } else if (
          (c.type === 'website' || c.type === 'url') &&
          (c.url || c.value || c.text)
        ) {
          if (!website) website = c.url || c.value || c.text;
        }
      }
    }
    website = (website || '').trim();

    const point = item.point || {};

    return {
      name: item.name,
      category: rubrics[0] || '',
      categories: rubrics.join(', '),
      address: item.full_address_name || item.address_name || '',
      phone: phones.join(', '),
      website,
      hasWebsite: Boolean(website),
      latitude: typeof point.lat === 'number' ? point.lat : null,
      longitude: typeof point.lon === 'number' ? point.lon : null,
      yandexUrl: item.id ? `https://2gis.ru/firm/${item.id}` : '',
      hours: item.schedule?.comment || '',
      niche: params.niche,
      region: params.region || '',
      source: '2gis',
      rawData: item,
    };
  }
}
