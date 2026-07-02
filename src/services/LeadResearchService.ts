import { AIProviderFactory } from './ai/AIProviderFactory';
import { IAIProvider } from './ai/IAIProvider';
import { ISearchProvider, SearchResult } from './search/ISearchProvider';
import { GoogleSearchProvider } from './search/GoogleSearchProvider';
import { YandexSearchProvider } from './search/YandexSearchProvider';

export interface LeadContact {
  emails: string[];
  phones: string[];
  socials: string[];
}

export interface Lead {
  businessName: string;
  website: string;
  description: string;
  contacts: LeadContact;
  relevanceScore: number;
  outreachAngle: string;
  source: string;
}

export interface LeadSearchInput {
  query: string;
  location?: string;
  count?: number;
  provider?: 'google' | 'yandex' | 'auto';
}

export interface LeadSearchResult {
  query: string;
  provider: string | null;
  liveSearch: boolean;
  leads: Lead[];
  suggestedQueries: string[];
  note?: string;
}

export interface DeepResearchInput {
  topic: string;
  profession?: string;
  depth?: 'overview' | 'graduate' | 'phd';
}

export class LeadResearchService {
  private ai: IAIProvider;

  constructor() {
    this.ai = AIProviderFactory.getProvider('claude');
  }

  private providers(): ISearchProvider[] {
    return [new GoogleSearchProvider(), new YandexSearchProvider()];
  }

  async availableProviders(): Promise<{ name: string; configured: boolean }[]> {
    const out: { name: string; configured: boolean }[] = [];
    for (const p of this.providers()) {
      out.push({ name: p.name, configured: await p.isConfigured() });
    }
    return out;
  }

  private async pickProvider(
    preferred?: 'google' | 'yandex' | 'auto'
  ): Promise<ISearchProvider | null> {
    const all = this.providers();
    if (preferred && preferred !== 'auto') {
      const chosen = all.find((p) => p.name === preferred);
      if (chosen && (await chosen.isConfigured())) return chosen;
      return null;
    }
    for (const p of all) {
      if (await p.isConfigured()) return p;
    }
    return null;
  }

  async findLeads(input: LeadSearchInput): Promise<LeadSearchResult> {
    const count = Math.min(Math.max(input.count || 10, 1), 25);
    const location = input.location?.trim();
    const baseQuery = input.query.trim();
    const query = location ? `${baseQuery} ${location}` : baseQuery;

    const provider = await this.pickProvider(input.provider);

    if (!provider) {
      // No live search configured — still be useful: propose a search strategy.
      const strategy = await this.suggestStrategy(baseQuery, location);
      return {
        query,
        provider: null,
        liveSearch: false,
        leads: [],
        suggestedQueries: strategy.queries,
        note:
          'Живой поиск не настроен. Добавьте ключи Google Custom Search или Yandex XML в Настройках → Разрешения и доступы, чтобы собирать реальные лиды. Ниже — готовые поисковые запросы.',
      };
    }

    let raw: SearchResult[] = [];
    try {
      raw = await provider.search(query, count);
    } catch (err: any) {
      const strategy = await this.suggestStrategy(baseQuery, location);
      return {
        query,
        provider: provider.name,
        liveSearch: false,
        leads: [],
        suggestedQueries: strategy.queries,
        note: `Ошибка поиска (${provider.name}): ${err.message}. Проверьте ключи API.`,
      };
    }

    const leads = await this.extractLeads(baseQuery, location, raw, count);
    return {
      query,
      provider: provider.name,
      liveSearch: true,
      leads,
      suggestedQueries: [],
    };
  }

  private async extractLeads(
    niche: string,
    location: string | undefined,
    results: SearchResult[],
    count: number
  ): Promise<Lead[]> {
    if (results.length === 0) return [];

    const resultsBlock = results
      .map(
        (r, i) =>
          `[${i + 1}] title: ${r.title}\nurl: ${r.url}\nsnippet: ${r.snippet}`
      )
      .join('\n\n');

    const prompt = `You are a B2B lead-research assistant. From the web search results below, extract up to ${count} business leads relevant to the niche "${niche}"${
      location ? ` in "${location}"` : ''
    }.

Rules:
- Only use information present in the results. Do NOT invent emails or phone numbers.
- Include a contact only if it plausibly appears in the snippet/url; otherwise leave the array empty.
- "relevanceScore" is 0-100 for how well the business matches the niche.
- "outreachAngle" is one concise sentence on how to approach them.
- Prefer official business/company contacts (public), not personal data.

Search results:
${resultsBlock}

Return ONLY valid JSON of this exact shape:
{
  "leads": [
    {
      "businessName": "string",
      "website": "string (url)",
      "description": "string",
      "contacts": { "emails": [], "phones": [], "socials": [] },
      "relevanceScore": 0,
      "outreachAngle": "string"
    }
  ]
}`;

    const text = await this.ai.generateText(prompt);
    const parsed = this.parseJson(text);
    const leadsArr: any[] = Array.isArray(parsed?.leads) ? parsed.leads : [];

    return leadsArr.map((l) => this.normalizeLead(l, results));
  }

  private normalizeLead(l: any, results: SearchResult[]): Lead {
    const website = typeof l?.website === 'string' ? l.website : '';
    const matched = results.find((r) => website && r.url.includes(this.host(website)));
    return {
      businessName: String(l?.businessName || 'Unknown'),
      website,
      description: String(l?.description || ''),
      contacts: {
        emails: this.asStringArray(l?.contacts?.emails),
        phones: this.asStringArray(l?.contacts?.phones),
        socials: this.asStringArray(l?.contacts?.socials),
      },
      relevanceScore: this.clampScore(l?.relevanceScore),
      outreachAngle: String(l?.outreachAngle || ''),
      source: matched ? matched.url : website,
    };
  }

  async deepResearch(input: DeepResearchInput): Promise<any> {
    const depth = input.depth || 'graduate';
    const depthGuidance: Record<string, string> = {
      overview: 'an accessible but accurate overview',
      graduate:
        "a rigorous graduate-level synthesis with precise terminology and open questions",
      phd:
        'a PhD/postgraduate-level analysis: state of the art, competing schools of thought, methodological trade-offs, and unresolved research gaps',
    };

    const prompt = `You are a research librarian and domain expert. Produce ${depthGuidance[depth]} for the topic below${
      input.profession ? `, framed for the profession/field: "${input.profession}"` : ''
    }.

Topic: ${input.topic}

Be precise and cite the KINDS of authoritative sources a researcher should consult (journals, standards bodies, seminal authors, databases) — do not fabricate specific citations or DOIs. Include concrete search queries the user can run.

Return ONLY valid JSON of this exact shape:
{
  "summary": "string",
  "keyConcepts": ["string"],
  "sections": [{ "title": "string", "content": "string" }],
  "methodologies": ["string"],
  "authoritativeSources": [{ "name": "string", "type": "journal|book|standard|database|author", "whereToFind": "string" }],
  "searchQueries": ["string"],
  "openQuestions": ["string"]
}`;

    const text = await this.ai.generateText(prompt);
    const parsed = this.parseJson(text);
    if (parsed) return parsed;
    return { summary: text, keyConcepts: [], sections: [], methodologies: [], authoritativeSources: [], searchQueries: [], openQuestions: [] };
  }

  private async suggestStrategy(
    niche: string,
    location?: string
  ): Promise<{ queries: string[] }> {
    const prompt = `Give 8 effective web-search queries to find B2B leads/contacts for the niche "${niche}"${
      location ? ` in "${location}"` : ''
    } on Google and Yandex. Include operators (site:, intitle:, "quotes") where useful.
Return ONLY JSON: { "queries": ["string"] }`;
    try {
      const parsed = this.parseJson(await this.ai.generateText(prompt));
      const queries = this.asStringArray(parsed?.queries);
      return { queries: queries.length ? queries : this.fallbackQueries(niche, location) };
    } catch {
      return { queries: this.fallbackQueries(niche, location) };
    }
  }

  private fallbackQueries(niche: string, location?: string): string[] {
    const loc = location ? ` ${location}` : '';
    return [
      `${niche}${loc} контакты email`,
      `${niche}${loc} "телефон" OR "phone"`,
      `${niche}${loc} site:vk.com`,
      `${niche}${loc} site:instagram.com`,
      `intitle:${niche}${loc}`,
      `${niche}${loc} каталог компаний`,
    ];
  }

  // --- helpers ---

  private parseJson(text: string): any | null {
    if (!text) return null;
    let cleaned = text.trim();
    // Strip markdown code fences if present.
    cleaned = cleaned.replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
    try {
      return JSON.parse(cleaned);
    } catch {
      const start = cleaned.indexOf('{');
      const end = cleaned.lastIndexOf('}');
      if (start !== -1 && end !== -1 && end > start) {
        try {
          return JSON.parse(cleaned.slice(start, end + 1));
        } catch {
          return null;
        }
      }
      return null;
    }
  }

  private asStringArray(v: any): string[] {
    if (!Array.isArray(v)) return [];
    return v.filter((x) => typeof x === 'string' && x.trim().length > 0).map((x) => x.trim());
  }

  private clampScore(v: any): number {
    const n = Number(v);
    if (Number.isNaN(n)) return 0;
    return Math.min(Math.max(Math.round(n), 0), 100);
  }

  private host(url: string): string {
    try {
      return new URL(url.startsWith('http') ? url : `https://${url}`).host;
    } catch {
      return url;
    }
  }
}
