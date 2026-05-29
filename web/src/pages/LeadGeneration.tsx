import { useState, useEffect } from 'react';
import { Target, Search, Download, Globe, Phone, MapPin, Trash2 } from 'lucide-react';
import { leads } from '../services/api';

interface Lead {
  id: string;
  name: string;
  category: string;
  address: string;
  phone: string;
  website: string;
  hasWebsite: boolean;
  yandexUrl: string;
  niche: string;
  region: string;
  status: string;
  notes: string;
}

interface Stats {
  total: number;
  withoutWebsite: number;
  newLeads: number;
  contacted: number;
  clients: number;
}

const STATUS_OPTIONS = ['new', 'contacted', 'qualified', 'rejected', 'client'];
const STATUS_LABELS: Record<string, string> = {
  new: 'Новый',
  contacted: 'Связались',
  qualified: 'Квалифицирован',
  rejected: 'Отказ',
  client: 'Клиент',
};
const STATUS_COLORS: Record<string, string> = {
  new: 'bg-blue-100 text-blue-800',
  contacted: 'bg-yellow-100 text-yellow-800',
  qualified: 'bg-purple-100 text-purple-800',
  rejected: 'bg-gray-100 text-gray-600',
  client: 'bg-green-100 text-green-800',
};

export default function LeadGeneration() {
  const [items, setItems] = useState<Lead[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(false);
  const [searching, setSearching] = useState(false);
  const [message, setMessage] = useState<string>('');

  // Форма поиска
  const [niche, setNiche] = useState('');
  const [region, setRegion] = useState('');
  const [noWebsiteOnly, setNoWebsiteOnly] = useState(false);
  const [limit, setLimit] = useState(50);
  const [source, setSource] = useState<
    'yandex' | '2gis' | '2gis_scraper' | 'both'
  >('yandex');

  // Фильтры таблицы
  const [filterNoWebsite, setFilterNoWebsite] = useState(false);
  const [filterStatus, setFilterStatus] = useState('');

  const loadData = async () => {
    try {
      setLoading(true);
      const params: any = {};
      if (filterNoWebsite) params.hasWebsite = false;
      if (filterStatus) params.status = filterStatus;
      const [listRes, statsRes] = await Promise.all([
        leads.list(params),
        leads.stats(),
      ]);
      setItems(listRes.data.items || []);
      setStats(statsRes.data.stats || null);
    } catch (e: any) {
      console.error(e);
      setMessage('Не удалось загрузить лиды. Проверьте, что бэкенд запущен.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filterNoWebsite, filterStatus]);

  const handleSearch = async () => {
    if (!niche.trim()) {
      setMessage('Укажите нишу, например "кофейня"');
      return;
    }
    try {
      setSearching(true);
      setMessage('');
      const res = await leads.search({
        niche,
        region: region || undefined,
        noWebsiteOnly,
        limit: Number(limit),
        save: true,
        source,
      });
      const by = res.data.bySource
        ? ` (${Object.entries(res.data.bySource)
            .map(([k, v]) => `${k}: ${v}`)
            .join(', ')})`
        : '';
      setMessage(
        `Найдено ${res.data.found}, сохранено новых: ${res.data.saved}.${by}`
      );
      await loadData();
    } catch (e: any) {
      setMessage(
        e.response?.data?.error || 'Ошибка поиска. Проверьте YANDEX_MAPS_API_KEY.'
      );
    } finally {
      setSearching(false);
    }
  };

  const handleStatusChange = async (id: string, status: string) => {
    try {
      await leads.update(id, { status });
      setItems((prev) =>
        prev.map((l) => (l.id === id ? { ...l, status } : l))
      );
    } catch (e) {
      console.error(e);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Удалить лид?')) return;
    await leads.remove(id);
    setItems((prev) => prev.filter((l) => l.id !== id));
  };

  const exportCsv = () => {
    const params: any = {};
    if (filterNoWebsite) params.hasWebsite = false;
    if (filterStatus) params.status = filterStatus;
    window.open(leads.exportCsvUrl(params), '_blank');
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-gray-900 flex items-center gap-2">
            <Target className="text-blue-600" /> Лид-генерация
          </h1>
          <p className="text-gray-500 mt-1">
            Сбор компаний с Яндекс.Карт по нише и региону
          </p>
        </div>
        <button
          onClick={exportCsv}
          className="flex items-center gap-2 bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700"
        >
          <Download size={18} /> Экспорт CSV
        </button>
      </div>

      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
          {[
            { label: 'Всего лидов', value: stats.total },
            { label: 'Без сайта', value: stats.withoutWebsite },
            { label: 'Новые', value: stats.newLeads },
            { label: 'Связались', value: stats.contacted },
            { label: 'Клиенты', value: stats.clients },
          ].map((s) => (
            <div key={s.label} className="bg-white rounded-xl shadow-sm p-4">
              <p className="text-2xl font-bold text-gray-900">{s.value}</p>
              <p className="text-sm text-gray-500">{s.label}</p>
            </div>
          ))}
        </div>
      )}

      {/* Search form */}
      <div className="bg-white rounded-xl shadow-sm p-6">
        <h2 className="font-semibold text-lg mb-4 flex items-center gap-2">
          <Search size={20} /> Новый сбор
        </h2>
        <div className="mb-4">
          <label className="block text-sm text-gray-600 mb-1">Источник</label>
          <select
            value={source}
            onChange={(e) => setSource(e.target.value as any)}
            className="border rounded-lg px-3 py-2 w-full md:w-72"
          >
            <option value="yandex">Яндекс.Карты (API)</option>
            <option value="2gis">2ГИС (API)</option>
            <option value="both">Яндекс + 2ГИС (оба API)</option>
            <option value="2gis_scraper">
              2ГИС скрапер (parser-2gis, без ключа)
            </option>
          </select>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <input
            type="text"
            placeholder="Ниша (напр. кофейня)"
            value={niche}
            onChange={(e) => setNiche(e.target.value)}
            className="border rounded-lg px-3 py-2"
          />
          <input
            type="text"
            placeholder="Город (напр. Москва)"
            value={region}
            onChange={(e) => setRegion(e.target.value)}
            className="border rounded-lg px-3 py-2"
          />
          <select
            value={limit}
            onChange={(e) => setLimit(Number(e.target.value))}
            className="border rounded-lg px-3 py-2"
          >
            {[50, 100, 200, 500].map((n) => (
              <option key={n} value={n}>
                до {n} компаний
              </option>
            ))}
          </select>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={noWebsiteOnly}
              onChange={(e) => setNoWebsiteOnly(e.target.checked)}
            />
            Только без сайта
          </label>
        </div>
        <button
          onClick={handleSearch}
          disabled={searching}
          className="mt-4 bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 disabled:opacity-50"
        >
          {searching ? 'Собираю…' : 'Собрать компании'}
        </button>
        {message && (
          <p className="mt-3 text-sm text-gray-700">{message}</p>
        )}
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4">
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={filterNoWebsite}
            onChange={(e) => setFilterNoWebsite(e.target.checked)}
          />
          Показать только без сайта
        </label>
        <select
          value={filterStatus}
          onChange={(e) => setFilterStatus(e.target.value)}
          className="border rounded-lg px-3 py-1.5 text-sm"
        >
          <option value="">Все статусы</option>
          {STATUS_OPTIONS.map((s) => (
            <option key={s} value={s}>
              {STATUS_LABELS[s]}
            </option>
          ))}
        </select>
      </div>

      {/* Table */}
      <div className="bg-white rounded-xl shadow-sm overflow-hidden">
        {loading ? (
          <p className="p-6 text-gray-500">Загрузка…</p>
        ) : items.length === 0 ? (
          <p className="p-6 text-gray-500">
            Пока нет лидов. Запустите сбор выше.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-left text-gray-600">
                <tr>
                  <th className="px-4 py-3">Компания</th>
                  <th className="px-4 py-3">Контакты</th>
                  <th className="px-4 py-3">Сайт</th>
                  <th className="px-4 py-3">Статус</th>
                  <th className="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {items.map((l) => (
                  <tr key={l.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="font-medium text-gray-900">{l.name}</div>
                      <div className="text-gray-500 text-xs">{l.category}</div>
                      {l.address && (
                        <div className="text-gray-400 text-xs flex items-center gap-1">
                          <MapPin size={12} /> {l.address}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {l.phone ? (
                        <span className="flex items-center gap-1 text-gray-700">
                          <Phone size={12} /> {l.phone}
                        </span>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {l.hasWebsite ? (
                        <a
                          href={l.website}
                          target="_blank"
                          rel="noreferrer"
                          className="flex items-center gap-1 text-blue-600 hover:underline"
                        >
                          <Globe size={12} /> есть
                        </a>
                      ) : (
                        <span className="px-2 py-0.5 rounded bg-red-100 text-red-700 text-xs">
                          нет сайта
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <select
                        value={l.status}
                        onChange={(e) =>
                          handleStatusChange(l.id, e.target.value)
                        }
                        className={`text-xs rounded px-2 py-1 ${
                          STATUS_COLORS[l.status] || ''
                        }`}
                      >
                        {STATUS_OPTIONS.map((s) => (
                          <option key={s} value={s}>
                            {STATUS_LABELS[s]}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button
                        onClick={() => handleDelete(l.id)}
                        className="text-gray-400 hover:text-red-600"
                      >
                        <Trash2 size={16} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
