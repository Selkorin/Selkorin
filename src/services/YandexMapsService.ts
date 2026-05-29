import axios from 'axios';
import { LeadResult, saveLeads } from './LeadStorage';

/**
 * Параметры поиска компаний.
 */
export interface LeadSearchParams {
  // Ниша / что ищем, например "кофейня", "стоматология", "автосервис"
  niche: string;
  // Город или регион, например "Москва". Будет добавлен к запросу.
  region?: string;
  // Центр области поиска "долгота,широта" (например "37.62,55.75" для Москвы).
  // Если не задан — Яндекс определит область по тексту запроса.
  ll?: string;
  // Размер области поиска "ширина,высота" в градусах, например "0.5,0.5".
  spn?: string;
  // Собирать только компании БЕЗ сайта (потенциальные клиенты на разработку)
  noWebsiteOnly?: boolean;
  // Сколько максимум результатов собрать (Яндекс отдаёт до 500 на запрос)
  limit?: number;
  // Сохранять ли результаты в БД
  save?: boolean;
}

/**
 * Сервис сбора компаний через официальный Yandex Places API
 * (Поиск по организациям / Geosearch API).
 *
 * Документация: https://yandex.ru/dev/geosearch/doc/ru/
 * Ключ выдаётся бесплатно в кабинете разработчика: https://developer.tech.yandex.ru/
 */
export class YandexMapsService {
  private readonly apiUrl = 'https://search-maps.yandex.ru/v1/';
  private readonly apiKey: string;
  // Яндекс отдаёт максимум 500 объектов на один поиск
  private readonly MAX_RESULTS = 500;
  // За один запрос можно запросить до 50 объектов, дальше — пагинация через skip
  private readonly PAGE_SIZE = 50;

  constructor() {
    this.apiKey = process.env.YANDEX_MAPS_API_KEY || '';
  }

  isConfigured(): boolean {
    return Boolean(this.apiKey);
  }

  /**
   * Ищет компании и (опционально) сохраняет их в БД.
   */
  async search(params: LeadSearchParams): Promise<{
    total: number;
    saved: number;
    leads: LeadResult[];
  }> {
    if (!this.isConfigured()) {
      throw new Error(
        'YANDEX_MAPS_API_KEY не задан. Получите ключ Geosearch ' +
          'в кабинете https://developer.tech.yandex.ru/ и добавьте его в .env'
      );
    }

    if (!params.niche || !params.niche.trim()) {
      throw new Error('Не указана ниша (niche) для поиска');
    }

    const text = params.region
      ? `${params.niche} ${params.region}`
      : params.niche;

    const targetLimit = Math.min(
      params.limit || this.MAX_RESULTS,
      this.MAX_RESULTS
    );

    const collected: LeadResult[] = [];
    const seen = new Set<string>();

    for (let skip = 0; skip < targetLimit; skip += this.PAGE_SIZE) {
      const results = Math.min(this.PAGE_SIZE, targetLimit - skip);

      const query: Record<string, any> = {
        apikey: this.apiKey,
        text,
        type: 'biz', // только организации
        lang: 'ru_RU',
        results,
        skip,
      };
      if (params.ll) query.ll = params.ll;
      if (params.spn) query.spn = params.spn;

      let features: any[] = [];
      try {
        const response = await axios.get(this.apiUrl, {
          params: query,
          timeout: 20000,
        });
        features = response.data?.features || [];
      } catch (error: any) {
        const status = error.response?.status;
        if (status === 403) {
          throw new Error(
            'Yandex API вернул 403: ключ недействителен или не активирован для Geosearch API'
          );
        }
        if (status === 429) {
          throw new Error('Yandex API: превышен лимит запросов (429). Попробуйте позже.');
        }
        throw new Error(`Ошибка запроса к Yandex API: ${error.message}`);
      }

      if (features.length === 0) break;

      for (const feature of features) {
        const lead = this.mapFeature(feature, params);
        if (!lead) continue;

        // Фильтр "только без сайта"
        if (params.noWebsiteOnly && lead.hasWebsite) continue;

        // Дедупликация по названию+адресу
        const key = `${lead.name}|${lead.address}`.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);

        collected.push(lead);
      }

      // Если страница пришла неполной — больше данных нет
      if (features.length < results) break;
    }

    let saved = 0;
    if (params.save) {
      saved = await saveLeads(collected);
    }

    return { total: collected.length, saved, leads: collected };
  }

  /**
   * Преобразует один объект GeoJSON из ответа Яндекса в лид.
   */
  private mapFeature(feature: any, params: LeadSearchParams): LeadResult | null {
    const meta = feature?.properties?.CompanyMetaData;
    if (!meta || !meta.name) return null;

    const categories: string[] = Array.isArray(meta.Categories)
      ? meta.Categories.map((c: any) => c.name).filter(Boolean)
      : [];

    const phones: string[] = Array.isArray(meta.Phones)
      ? meta.Phones.map((p: any) => p.formatted || p.value).filter(Boolean)
      : [];

    const website: string = (meta.url || '').trim();

    const coords: number[] = feature?.geometry?.coordinates || [];

    let hours = '';
    if (meta.Hours?.text) hours = meta.Hours.text;

    return {
      name: meta.name,
      category: categories[0] || '',
      categories: categories.join(', '),
      address: meta.address || meta.AddressDetails?.Country?.AddressLine || '',
      phone: phones.join(', '),
      website,
      hasWebsite: Boolean(website),
      longitude: coords.length === 2 ? coords[0] : null,
      latitude: coords.length === 2 ? coords[1] : null,
      yandexUrl: meta.id ? `https://yandex.ru/maps/org/${meta.id}` : '',
      hours,
      niche: params.niche,
      region: params.region || '',
      source: 'yandex_maps',
      rawData: meta,
    };
  }
}
