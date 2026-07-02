import { useState, useEffect } from 'react';
import {
  Radar,
  Search,
  GraduationCap,
  Mail,
  Phone,
  Globe,
  ExternalLink,
  AlertCircle,
  Sparkles,
} from 'lucide-react';
import { leads as leadsApi } from '../services/api';

interface Lead {
  businessName: string;
  website: string;
  description: string;
  contacts: { emails: string[]; phones: string[]; socials: string[] };
  relevanceScore: number;
  outreachAngle: string;
  source: string;
}

interface LeadResponse {
  query: string;
  provider: string | null;
  liveSearch: boolean;
  leads: Lead[];
  suggestedQueries: string[];
  note?: string;
}

export default function Leads() {
  const [tab, setTab] = useState<'leads' | 'research'>('leads');
  const [providers, setProviders] = useState<{ name: string; configured: boolean }[]>([]);

  useEffect(() => {
    leadsApi
      .providers()
      .then((r) => setProviders(r.data.providers || []))
      .catch(() => setProviders([]));
  }, []);

  const anyConfigured = providers.some((p) => p.configured);

  return (
    <div className="space-y-6 pb-16">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-3xl font-bold text-gray-900 flex items-center gap-2">
            <Radar className="text-blue-600" /> Лиды и Исследования
          </h1>
          <p className="text-gray-500 mt-2">
            Умный парсер контактов из Google/Yandex и ИИ-исследование уровня аспирантуры
          </p>
        </div>
      </div>

      {/* Provider status */}
      <div className="flex flex-wrap gap-2">
        {providers.map((p) => (
          <span
            key={p.name}
            className={`inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-medium ${
              p.configured ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-500'
            }`}
          >
            <Globe size={13} /> {p.name}: {p.configured ? 'подключён' : 'не настроен'}
          </span>
        ))}
      </div>

      {/* Tabs */}
      <div className="flex gap-2 border-b border-gray-200">
        <button
          onClick={() => setTab('leads')}
          className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
            tab === 'leads'
              ? 'border-blue-600 text-blue-600'
              : 'border-transparent text-gray-500 hover:text-gray-700'
          }`}
        >
          <span className="flex items-center gap-2">
            <Search size={16} /> Поиск лидов
          </span>
        </button>
        <button
          onClick={() => setTab('research')}
          className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
            tab === 'research'
              ? 'border-blue-600 text-blue-600'
              : 'border-transparent text-gray-500 hover:text-gray-700'
          }`}
        >
          <span className="flex items-center gap-2">
            <GraduationCap size={16} /> Глубокое исследование
          </span>
        </button>
      </div>

      {tab === 'leads' ? <LeadFinder anyConfigured={anyConfigured} /> : <DeepResearch />}
    </div>
  );
}

function LeadFinder({ anyConfigured }: { anyConfigured: boolean }) {
  const [query, setQuery] = useState('');
  const [location, setLocation] = useState('');
  const [count, setCount] = useState(10);
  const [provider, setProvider] = useState<'auto' | 'google' | 'yandex'>('auto');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState<LeadResponse | null>(null);

  const run = async () => {
    if (!query.trim()) return;
    setLoading(true);
    setError('');
    setResult(null);
    try {
      const res = await leadsApi.search({ query: query.trim(), location: location.trim(), count, provider });
      setResult(res.data as LeadResponse);
    } catch (e: any) {
      setError(e?.response?.data?.error || e?.message || 'Ошибка запроса');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="md:col-span-2">
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Ниша / профессия
            </label>
            <input
              type="text"
              placeholder="например: стоматологические клиники"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && run()}
              className="input"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Город / регион</label>
            <input
              type="text"
              placeholder="Москва"
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              className="input"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Источник</label>
            <select
              value={provider}
              onChange={(e) => setProvider(e.target.value as any)}
              className="input"
            >
              <option value="auto">Авто</option>
              <option value="google">Google</option>
              <option value="yandex">Yandex</option>
            </select>
          </div>
        </div>

        <div className="flex items-center gap-4 mt-4">
          <div className="flex items-center gap-2">
            <label className="text-sm text-gray-600">Кол-во:</label>
            <input
              type="number"
              min={1}
              max={25}
              value={count}
              onChange={(e) => setCount(Number(e.target.value))}
              className="input w-20 py-1"
            />
          </div>
          <button
            onClick={run}
            disabled={loading || !query.trim()}
            className="btn-primary flex items-center gap-2 disabled:opacity-50"
          >
            <Search size={18} />
            {loading ? 'Поиск…' : 'Найти лиды'}
          </button>
        </div>

        {!anyConfigured && (
          <p className="text-xs text-yellow-700 bg-yellow-50 border border-yellow-200 rounded-lg px-3 py-2 mt-4">
            Живой поиск не подключён. Добавьте ключи Google/Yandex в Настройках → Разрешения и доступы.
            Пока система предложит готовые поисковые запросы.
          </p>
        )}
      </div>

      {error && (
        <div className="flex items-center gap-2 text-red-700 bg-red-50 border border-red-200 px-4 py-3 rounded-lg">
          <AlertCircle size={18} />
          <span className="text-sm">{error}</span>
        </div>
      )}

      {result && (
        <div className="space-y-4">
          {result.note && (
            <div className="text-sm text-gray-700 bg-blue-50 border border-blue-200 rounded-lg px-4 py-3">
              {result.note}
            </div>
          )}

          {result.suggestedQueries?.length > 0 && (
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="font-semibold text-gray-900 mb-3 flex items-center gap-2">
                <Sparkles size={18} className="text-blue-600" /> Рекомендованные поисковые запросы
              </h3>
              <ul className="space-y-2">
                {result.suggestedQueries.map((q, i) => (
                  <li key={i} className="text-sm text-gray-700 bg-gray-50 rounded px-3 py-2 font-mono">
                    {q}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {result.leads.map((lead, i) => (
            <div key={i} className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="text-lg font-semibold text-gray-900">{lead.businessName}</p>
                  {lead.website && (
                    <a
                      href={lead.website.startsWith('http') ? lead.website : `https://${lead.website}`}
                      target="_blank"
                      rel="noreferrer"
                      className="text-sm text-blue-600 hover:underline inline-flex items-center gap-1 break-all"
                    >
                      {lead.website} <ExternalLink size={13} />
                    </a>
                  )}
                  <p className="text-sm text-gray-600 mt-2">{lead.description}</p>
                </div>
                <span
                  className={`shrink-0 px-3 py-1 rounded-full text-xs font-semibold ${
                    lead.relevanceScore >= 70
                      ? 'bg-green-100 text-green-800'
                      : lead.relevanceScore >= 40
                      ? 'bg-yellow-100 text-yellow-800'
                      : 'bg-gray-100 text-gray-600'
                  }`}
                >
                  {lead.relevanceScore}%
                </span>
              </div>

              {(lead.contacts.emails.length > 0 ||
                lead.contacts.phones.length > 0 ||
                lead.contacts.socials.length > 0) && (
                <div className="flex flex-wrap gap-2 mt-4">
                  {lead.contacts.emails.map((em) => (
                    <span key={em} className="inline-flex items-center gap-1 text-xs bg-gray-100 rounded px-2 py-1">
                      <Mail size={12} /> {em}
                    </span>
                  ))}
                  {lead.contacts.phones.map((ph) => (
                    <span key={ph} className="inline-flex items-center gap-1 text-xs bg-gray-100 rounded px-2 py-1">
                      <Phone size={12} /> {ph}
                    </span>
                  ))}
                  {lead.contacts.socials.map((sc) => (
                    <span key={sc} className="inline-flex items-center gap-1 text-xs bg-gray-100 rounded px-2 py-1">
                      <Globe size={12} /> {sc}
                    </span>
                  ))}
                </div>
              )}

              {lead.outreachAngle && (
                <p className="text-sm text-gray-500 mt-3 italic">💬 {lead.outreachAngle}</p>
              )}
            </div>
          ))}

          {result.liveSearch && result.leads.length === 0 && (
            <div className="text-center py-10 text-gray-500 bg-white rounded-lg border border-gray-200">
              Ничего не найдено по запросу «{result.query}».
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function DeepResearch() {
  const [topic, setTopic] = useState('');
  const [profession, setProfession] = useState('');
  const [depth, setDepth] = useState<'overview' | 'graduate' | 'phd'>('graduate');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [research, setResearch] = useState<any | null>(null);

  const run = async () => {
    if (!topic.trim()) return;
    setLoading(true);
    setError('');
    setResearch(null);
    try {
      const res = await leadsApi.deepResearch({ topic: topic.trim(), profession: profession.trim(), depth });
      setResearch(res.data.research);
    } catch (e: any) {
      setError(e?.response?.data?.error || e?.message || 'Ошибка запроса');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="md:col-span-2">
            <label className="block text-sm font-medium text-gray-700 mb-1">Тема</label>
            <input
              type="text"
              placeholder="например: применение CRISPR в онкологии"
              value={topic}
              onChange={(e) => setTopic(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && run()}
              className="input"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Профессия / область</label>
            <input
              type="text"
              placeholder="молекулярная биология"
              value={profession}
              onChange={(e) => setProfession(e.target.value)}
              className="input"
            />
          </div>
        </div>
        <div className="flex items-center gap-4 mt-4">
          <div className="flex items-center gap-2">
            <label className="text-sm text-gray-600">Глубина:</label>
            <select value={depth} onChange={(e) => setDepth(e.target.value as any)} className="input py-1">
              <option value="overview">Обзор</option>
              <option value="graduate">Магистратура</option>
              <option value="phd">Аспирантура / PhD</option>
            </select>
          </div>
          <button
            onClick={run}
            disabled={loading || !topic.trim()}
            className="btn-primary flex items-center gap-2 disabled:opacity-50"
          >
            <GraduationCap size={18} />
            {loading ? 'Исследую…' : 'Исследовать'}
          </button>
        </div>
      </div>

      {error && (
        <div className="flex items-center gap-2 text-red-700 bg-red-50 border border-red-200 px-4 py-3 rounded-lg">
          <AlertCircle size={18} />
          <span className="text-sm">{error}</span>
        </div>
      )}

      {research && (
        <div className="space-y-4">
          {research.summary && (
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="font-semibold text-gray-900 mb-2">Резюме</h3>
              <p className="text-sm text-gray-700 whitespace-pre-line">{research.summary}</p>
            </div>
          )}

          {Array.isArray(research.keyConcepts) && research.keyConcepts.length > 0 && (
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="font-semibold text-gray-900 mb-3">Ключевые понятия</h3>
              <div className="flex flex-wrap gap-2">
                {research.keyConcepts.map((c: string, i: number) => (
                  <span key={i} className="text-xs bg-blue-50 text-blue-800 rounded-full px-3 py-1">
                    {c}
                  </span>
                ))}
              </div>
            </div>
          )}

          {Array.isArray(research.sections) &&
            research.sections.map((s: any, i: number) => (
              <div key={i} className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
                <h3 className="font-semibold text-gray-900 mb-2">{s.title}</h3>
                <p className="text-sm text-gray-700 whitespace-pre-line">{s.content}</p>
              </div>
            ))}

          {Array.isArray(research.authoritativeSources) && research.authoritativeSources.length > 0 && (
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="font-semibold text-gray-900 mb-3">Авторитетные источники</h3>
              <ul className="space-y-2">
                {research.authoritativeSources.map((src: any, i: number) => (
                  <li key={i} className="text-sm text-gray-700">
                    <span className="font-medium">{src.name}</span>
                    {src.type && <span className="text-gray-400"> · {src.type}</span>}
                    {src.whereToFind && <span className="text-gray-500"> — {src.whereToFind}</span>}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {Array.isArray(research.searchQueries) && research.searchQueries.length > 0 && (
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="font-semibold text-gray-900 mb-3">Поисковые запросы</h3>
              <ul className="space-y-2">
                {research.searchQueries.map((q: string, i: number) => (
                  <li key={i} className="text-sm text-gray-700 bg-gray-50 rounded px-3 py-2 font-mono">
                    {q}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {Array.isArray(research.openQuestions) && research.openQuestions.length > 0 && (
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="font-semibold text-gray-900 mb-3">Открытые вопросы</h3>
              <ul className="list-disc list-inside space-y-1">
                {research.openQuestions.map((q: string, i: number) => (
                  <li key={i} className="text-sm text-gray-700">
                    {q}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
