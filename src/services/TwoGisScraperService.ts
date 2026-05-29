import { spawn } from 'child_process';
import { promises as fs } from 'fs';
import os from 'os';
import path from 'path';
import { parse } from 'csv-parse/sync';
import { LeadResult, saveLeads } from './LeadStorage';
import { LeadSearchParams } from './YandexMapsService';

/**
 * Адаптер к внешнему OSS-инструменту parser-2gis
 * (https://github.com/interlark/parser-2gis).
 *
 * В отличие от официального 2GIS API, это браузерный СКРАПЕР: он гоняет Chrome
 * по сайту 2gis.ru и собирает публичные карточки компаний. API-ключ не нужен.
 *
 * ⚠️ Это серая зона по ToS 2ГИС, требует установленного Python-пакета и Chrome,
 *    и может натыкаться на капчу (parser-2gis в этом случае ставит сбор на паузу
 *    для ручного решения — автоматического обхода капчи здесь НЕТ).
 *
 * Установка инструмента:
 *   pipx install parser-2gis        (или: pip install parser-2gis)
 *   + установленный Google Chrome / Chromium
 *
 * Путь к бинарю можно переопределить через PARSER_2GIS_BIN (по умолчанию "parser-2gis").
 */
export interface ScraperParams extends LeadSearchParams {
  // Прямой URL поиска на 2gis.ru, например
  // https://2gis.ru/moscow/search/кофейня
  url?: string;
}

export class TwoGisScraperService {
  private readonly bin: string;
  private readonly maxRecords: number;

  constructor() {
    this.bin = process.env.PARSER_2GIS_BIN || 'parser-2gis';
    this.maxRecords = Number(process.env.PARSER_2GIS_MAX || '0') || 0;
  }

  /**
   * Строит URL поиска 2ГИС из ниши и региона, если не передан явный url.
   */
  private buildUrl(params: ScraperParams): string {
    if (params.url) return params.url;
    const query = encodeURIComponent(
      [params.niche, params.region].filter(Boolean).join(' ')
    );
    // Без города 2ГИС сам определит регион по тексту запроса
    return `https://2gis.ru/search/${query}`;
  }

  async search(params: ScraperParams): Promise<{
    total: number;
    saved: number;
    leads: LeadResult[];
  }> {
    const url = this.buildUrl(params);
    if (!params.niche && !params.url) {
      throw new Error('Для скрапера 2ГИС укажите niche+region или прямой url');
    }

    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'p2gis-'));
    const outFile = path.join(tmpDir, 'result.csv');

    const args = ['-u', url, '-f', 'csv', '-o', outFile];
    const limit = params.limit || this.maxRecords;
    if (limit) {
      // ограничиваем количество записей через конфиг parser-2gis
      args.push(`--parser.max-records=${limit}`);
    }

    try {
      await this.runProcess(args);
      const raw = await fs.readFile(outFile, 'utf-8').catch(() => '');
      const leads = this.parseCsv(raw, params);
      const filtered = params.noWebsiteOnly
        ? leads.filter((l) => !l.hasWebsite)
        : leads;

      let saved = 0;
      if (params.save) {
        saved = await saveLeads(filtered);
      }
      return { total: filtered.length, saved, leads: filtered };
    } finally {
      await fs.rm(tmpDir, { recursive: true, force: true }).catch(() => {});
    }
  }

  private runProcess(args: string[]): Promise<void> {
    return new Promise((resolve, reject) => {
      let child;
      try {
        child = spawn(this.bin, args, { stdio: ['ignore', 'pipe', 'pipe'] });
      } catch (e: any) {
        return reject(new Error(`Не удалось запустить ${this.bin}: ${e.message}`));
      }

      let stderr = '';
      child.stderr?.on('data', (d) => (stderr += d.toString()));

      child.on('error', (err: any) => {
        if (err.code === 'ENOENT') {
          reject(
            new Error(
              `parser-2gis не установлен. Установите: "pipx install parser-2gis" ` +
                `(+ Google Chrome), либо задайте PARSER_2GIS_BIN в .env`
            )
          );
        } else {
          reject(new Error(`Ошибка запуска parser-2gis: ${err.message}`));
        }
      });

      child.on('close', (code) => {
        if (code === 0) resolve();
        else
          reject(
            new Error(
              `parser-2gis завершился с кодом ${code}. ${stderr.slice(0, 500)}`
            )
          );
      });
    });
  }

  /**
   * Парсит CSV-вывод parser-2gis. Колонки сопоставляются по ключевым словам
   * в заголовке, поэтому устойчивы к точным названиям/локали.
   */
  private parseCsv(raw: string, params: ScraperParams): LeadResult[] {
    if (!raw.trim()) return [];

    let records: Record<string, string>[] = [];
    try {
      records = parse(raw, {
        columns: true,
        skip_empty_lines: true,
        bom: true,
        relax_column_count: true,
      });
    } catch {
      return [];
    }
    if (records.length === 0) return [];

    const headers = Object.keys(records[0]);
    const find = (keywords: string[]) =>
      headers.find((h) =>
        keywords.some((k) => h.toLowerCase().includes(k))
      );

    const colName = find(['name', 'назв', 'наимен']);
    const colAddress = find(['address', 'адрес']);
    const colPhone = find(['phone', 'телеф', 'тел.']);
    const colSite = find(['site', 'сайт', 'url', 'веб']);
    const colRubric = find(['rubric', 'рубрик', 'категор']);
    const colLat = find(['lat', 'широт']);
    const colLon = find(['lon', 'lng', 'долгот']);
    const colUrl2gis = find(['2gis', '2гис', 'ссылк']);

    const out: LeadResult[] = [];
    for (const r of records) {
      const name = (colName ? r[colName] : '')?.trim();
      if (!name) continue;

      const website = ((colSite ? r[colSite] : '') || '').trim();
      const lat = colLat ? parseFloat(r[colLat]) : NaN;
      const lon = colLon ? parseFloat(r[colLon]) : NaN;
      const rubrics = (colRubric ? r[colRubric] : '') || '';

      out.push({
        name,
        category: rubrics.split(/[;,]/)[0]?.trim() || '',
        categories: rubrics,
        address: ((colAddress ? r[colAddress] : '') || '').trim(),
        phone: ((colPhone ? r[colPhone] : '') || '').trim(),
        website,
        hasWebsite: Boolean(website),
        latitude: Number.isFinite(lat) ? lat : null,
        longitude: Number.isFinite(lon) ? lon : null,
        yandexUrl: ((colUrl2gis ? r[colUrl2gis] : '') || '').trim(),
        hours: '',
        niche: params.niche || '',
        region: params.region || '',
        source: '2gis',
        rawData: r,
      });
    }
    return out;
  }
}
