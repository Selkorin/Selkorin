import { Request, Response } from 'express';
import { AppDataSource } from '../config/database';
import { Lead } from '../entities/Lead';
import { YandexMapsService } from '../services/YandexMapsService';
import { TwoGisService } from '../services/TwoGisService';
import { TwoGisScraperService } from '../services/TwoGisScraperService';
import { VkService } from '../services/VkService';
import { TelegramParserService } from '../services/TelegramParserService';
import { LeadResult, saveLeads, dedupeLeads } from '../services/LeadStorage';

export class LeadGenController {
  private yandex = new YandexMapsService();
  private twoGis = new TwoGisService();
  private twoGisScraper = new TwoGisScraperService();
  private vk = new VkService();
  private telegram = new TelegramParserService();

  /**
   * POST /api/leads/search
   * Собирает компании из выбранного источника (Яндекс / 2ГИС API /
   * 2ГИС скрапер / все сразу) и сохраняет в БД.
   *
   * body.source: 'yandex' | '2gis' | '2gis_scraper' | 'both' (по умолчанию 'yandex')
   */
  async search(req: Request, res: Response) {
    try {
      const {
        niche,
        region,
        ll,
        spn,
        url, // прямой URL поиска 2gis.ru (для скрапера)
        usernames, // список каналов для Telegram-парсера
        noWebsiteOnly = false,
        limit,
        save = true,
        source = 'yandex',
      } = req.body;

      if (!niche && !url && !usernames) {
        return res.status(400).json({
          success: false,
          error: 'Укажите нишу (niche), либо url (2ГИС-скрапер), либо usernames (Telegram)',
        });
      }

      const baseParams = {
        niche,
        region,
        ll,
        spn,
        noWebsiteOnly: Boolean(noWebsiteOnly),
        limit: limit ? Number(limit) : undefined,
        // при объединении источников сохраняем один раз в контроллере
        save: false,
      };

      const perSource: Record<string, number> = {};
      const errors: Record<string, string> = {};
      let leads: LeadResult[] = [];

      const runYandex = async () => {
        const r = await this.yandex.search(baseParams);
        perSource.yandex = r.total;
        leads.push(...r.leads);
      };
      const runTwoGis = async () => {
        const r = await this.twoGis.search(baseParams);
        perSource['2gis'] = r.total;
        leads.push(...r.leads);
      };
      const runScraper = async () => {
        const r = await this.twoGisScraper.search({ ...baseParams, url });
        perSource['2gis_scraper'] = r.total;
        leads.push(...r.leads);
      };
      const runVk = async () => {
        const r = await this.vk.search(baseParams);
        perSource.vk = r.total;
        leads.push(...r.leads);
      };
      const runTelegram = async () => {
        const r = await this.telegram.search({ ...baseParams, usernames });
        perSource.telegram = r.total;
        leads.push(...r.leads);
      };

      if (source === 'yandex') {
        await runYandex();
      } else if (source === '2gis') {
        await runTwoGis();
      } else if (source === '2gis_scraper') {
        await runScraper();
      } else if (source === 'vk') {
        await runVk();
      } else if (source === 'telegram') {
        await runTelegram();
      } else if (source === 'both') {
        // Все API-источники параллельно; сбой одного не валит остальные
        const tasks: Array<[string, () => Promise<void>]> = [
          ['yandex', runYandex],
          ['2gis', runTwoGis],
          ['vk', runVk],
        ];
        const settled = await Promise.allSettled(tasks.map(([, fn]) => fn()));
        settled.forEach((r, i) => {
          if (r.status === 'rejected') {
            errors[tasks[i][0]] = r.reason?.message || String(r.reason);
          }
        });
      } else {
        return res.status(400).json({
          success: false,
          error: `Неизвестный источник: ${source}`,
        });
      }

      // Дедупликация между источниками
      leads = dedupeLeads(leads);

      let saved = 0;
      if (save) {
        saved = await saveLeads(leads);
      }

      res.json({
        success: true,
        found: leads.length,
        saved,
        bySource: perSource,
        errors: Object.keys(errors).length ? errors : undefined,
        leads,
      });
    } catch (error: any) {
      console.error('Lead search error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  }

  /**
   * GET /api/leads
   * Список собранных лидов с фильтрами и пагинацией.
   */
  async list(req: Request, res: Response) {
    try {
      const {
        niche,
        region,
        status,
        hasWebsite,
        search,
        page = 1,
        limit = 50,
      } = req.query;

      const repo = AppDataSource.getRepository(Lead);
      let query = repo.createQueryBuilder('lead');

      if (niche) query = query.andWhere('lead.niche = :niche', { niche });
      if (region) query = query.andWhere('lead.region = :region', { region });
      if (status) query = query.andWhere('lead.status = :status', { status });
      if (hasWebsite !== undefined) {
        query = query.andWhere('lead.hasWebsite = :hasWebsite', {
          hasWebsite: hasWebsite === 'true',
        });
      }
      if (search) {
        query = query.andWhere(
          '(lead.name LIKE :s OR lead.address LIKE :s OR lead.phone LIKE :s)',
          { s: `%${search}%` }
        );
      }

      const total = await query.getCount();
      const skip = ((Number(page) || 1) - 1) * Number(limit);

      const items = await query
        .orderBy('lead.createdAt', 'DESC')
        .skip(skip)
        .take(Number(limit))
        .getMany();

      res.json({
        success: true,
        total,
        page: Number(page),
        limit: Number(limit),
        items,
      });
    } catch (error: any) {
      res.status(500).json({ success: false, error: error.message });
    }
  }

  /**
   * GET /api/leads/stats — агрегаты для дашборда.
   */
  async stats(req: Request, res: Response) {
    try {
      const repo = AppDataSource.getRepository(Lead);
      const total = await repo.count();
      const withoutWebsite = await repo.count({ where: { hasWebsite: false } });
      const newLeads = await repo.count({ where: { status: 'new' } });
      const contacted = await repo.count({ where: { status: 'contacted' } });
      const clients = await repo.count({ where: { status: 'client' } });

      res.json({
        success: true,
        stats: { total, withoutWebsite, newLeads, contacted, clients },
      });
    } catch (error: any) {
      res.status(500).json({ success: false, error: error.message });
    }
  }

  /**
   * PUT /api/leads/:id — обновление статуса/заметок.
   */
  async update(req: Request, res: Response) {
    try {
      const { id } = req.params;
      const { status, notes } = req.body;
      const repo = AppDataSource.getRepository(Lead);

      const lead = await repo.findOneBy({ id });
      if (!lead) {
        return res.status(404).json({ success: false, error: 'Лид не найден' });
      }

      if (status) lead.status = status;
      if (notes !== undefined) lead.notes = notes;
      await repo.save(lead);

      res.json({ success: true, lead });
    } catch (error: any) {
      res.status(500).json({ success: false, error: error.message });
    }
  }

  /**
   * DELETE /api/leads/:id
   */
  async remove(req: Request, res: Response) {
    try {
      const { id } = req.params;
      const repo = AppDataSource.getRepository(Lead);
      await repo.delete({ id });
      res.json({ success: true });
    } catch (error: any) {
      res.status(500).json({ success: false, error: error.message });
    }
  }

  /**
   * GET /api/leads/export/csv — выгрузка таблицы лидов в CSV.
   */
  async exportCsv(req: Request, res: Response) {
    try {
      const { niche, region, status, hasWebsite } = req.query;
      const repo = AppDataSource.getRepository(Lead);
      let query = repo.createQueryBuilder('lead');

      if (niche) query = query.andWhere('lead.niche = :niche', { niche });
      if (region) query = query.andWhere('lead.region = :region', { region });
      if (status) query = query.andWhere('lead.status = :status', { status });
      if (hasWebsite !== undefined) {
        query = query.andWhere('lead.hasWebsite = :hasWebsite', {
          hasWebsite: hasWebsite === 'true',
        });
      }

      const leads = await query.orderBy('lead.createdAt', 'DESC').getMany();

      const headers = [
        'Название',
        'Категория',
        'Адрес',
        'Телефон',
        'Сайт',
        'Есть сайт',
        'Часы работы',
        'Ниша',
        'Регион',
        'Статус',
        'Яндекс',
        'Заметки',
      ];

      const escape = (v: any) => {
        const s = v === null || v === undefined ? '' : String(v);
        return `"${s.replace(/"/g, '""')}"`;
      };

      const rows = leads.map((l) =>
        [
          l.name,
          l.category,
          l.address,
          l.phone,
          l.website,
          l.hasWebsite ? 'да' : 'нет',
          l.hours,
          l.niche,
          l.region,
          l.status,
          l.yandexUrl,
          l.notes,
        ]
          .map(escape)
          .join(',')
      );

      // BOM, чтобы Excel корректно открывал кириллицу в UTF-8
      const csv = '﻿' + [headers.map(escape).join(','), ...rows].join('\n');

      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="leads-${Date.now()}.csv"`
      );
      res.send(csv);
    } catch (error: any) {
      res.status(500).json({ success: false, error: error.message });
    }
  }
}
