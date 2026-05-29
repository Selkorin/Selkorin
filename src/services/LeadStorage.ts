import { AppDataSource } from '../config/database';
import { Lead } from '../entities/Lead';

/**
 * Унифицированный результат поиска лида — общий для всех источников
 * (Яндекс.Карты, 2ГИС и т.д.).
 */
export interface LeadResult {
  name: string;
  category: string;
  categories: string;
  address: string;
  phone: string;
  website: string;
  hasWebsite: boolean;
  latitude: number | null;
  longitude: number | null;
  yandexUrl: string; // ссылка на карточку (в Яндексе или 2ГИС)
  hours: string;
  niche: string;
  region: string;
  source: string; // 'yandex_maps' | '2gis'
  rawData?: any;
}

/**
 * Сохраняет лиды в БД, пропуская уже существующие (по названию+адресу).
 * Возвращает количество новых записей.
 */
export async function saveLeads(leads: LeadResult[]): Promise<number> {
  const repo = AppDataSource.getRepository(Lead);
  let saved = 0;

  for (const item of leads) {
    const existing = await repo.findOne({
      where: { name: item.name, address: item.address },
    });
    if (existing) continue;

    const lead = repo.create({
      name: item.name,
      category: item.category,
      categories: item.categories,
      address: item.address,
      phone: item.phone,
      website: item.website,
      hasWebsite: item.hasWebsite,
      latitude: item.latitude ?? undefined,
      longitude: item.longitude ?? undefined,
      yandexUrl: item.yandexUrl,
      hours: item.hours,
      niche: item.niche,
      region: item.region,
      source: item.source,
      status: 'new',
      rawData: item.rawData,
    });
    await repo.save(lead);
    saved++;
  }

  return saved;
}

/**
 * Убирает дубликаты внутри одного набора лидов по названию+адресу.
 */
export function dedupeLeads(leads: LeadResult[]): LeadResult[] {
  const seen = new Set<string>();
  const out: LeadResult[] = [];
  for (const lead of leads) {
    const key = `${lead.name}|${lead.address}`.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(lead);
  }
  return out;
}
