import { useState, useEffect } from 'react';
import {
  Settings as SettingsIcon,
  Key,
  Link as LinkIcon,
  Save,
  ShieldCheck,
  Plus,
  Trash2,
  CheckCircle2,
  AlertCircle,
} from 'lucide-react';
import { socialAccounts, settings as settingsApi } from '../services/api';

interface SocialAccount {
  id: string;
  platform: string;
  accountName: string;
  status: string;
}

interface Prefs {
  contentLanguage: string;
  timezone: string;
  aiProvider: string;
  contentTone: string;
  brandValues: string;
  notifyScheduled: boolean;
  notifyThreshold: boolean;
  autoRespond: boolean;
}

const DEFAULT_PREFS: Prefs = {
  contentLanguage: 'Russian',
  timezone: 'UTC+3 (MSK)',
  aiProvider: 'claude',
  contentTone: '',
  brandValues: '',
  notifyScheduled: true,
  notifyThreshold: true,
  autoRespond: false,
};

const SECRET_FIELDS: { key: string; label: string; placeholder: string; hint: string }[] = [
  { key: 'anthropicApiKey', label: 'Anthropic API Key (Claude)', placeholder: 'sk-ant-...', hint: 'Нужен для ИИ-генерации и исследований.' },
  { key: 'googleSearchApiKey', label: 'Google Search API Key', placeholder: 'AIza...', hint: 'Google Programmable Search — для парсера лидов.' },
  { key: 'googleSearchCx', label: 'Google Search Engine ID (cx)', placeholder: 'xxxxxxx:yyyy', hint: 'Идентификатор поисковой системы Google.' },
  { key: 'yandexApiKey', label: 'Yandex XML API Key', placeholder: 'ключ Yandex XML', hint: 'Yandex XML Search — для парсера лидов.' },
  { key: 'yandexUser', label: 'Yandex User (login)', placeholder: 'ваш-логин', hint: 'Логин аккаунта Yandex XML.' },
];

export default function Settings() {
  const [accounts, setAccounts] = useState<SocialAccount[]>([]);
  const [prefs, setPrefs] = useState<Prefs>(DEFAULT_PREFS);
  const [secretStatus, setSecretStatus] = useState<Record<string, boolean>>({});
  const [secretInputs, setSecretInputs] = useState<Record<string, string>>({});

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState('');

  const [newAccount, setNewAccount] = useState({ platform: 'instagram', accountName: '', token: '' });
  const [addingAccount, setAddingAccount] = useState(false);

  useEffect(() => {
    loadAll();
  }, []);

  const loadAll = async () => {
    setLoading(true);
    setError('');
    try {
      const [accRes, setRes] = await Promise.all([
        socialAccounts.list(),
        settingsApi.get(),
      ]);
      setAccounts(accRes.data.accounts || []);
      const loaded = setRes.data.settings || {};
      setPrefs({
        ...DEFAULT_PREFS,
        ...Object.fromEntries(
          Object.entries(loaded).filter(([, v]) => v !== null && v !== undefined)
        ),
      });
      setSecretStatus(setRes.data.secrets || {});
    } catch (e: any) {
      setError('Не удалось загрузить настройки. Проверьте, что бэкенд запущен.');
      console.error('Error loading settings:', e);
    } finally {
      setLoading(false);
    }
  };

  const handleSaveAll = async () => {
    setSaving(true);
    setSaved(false);
    setError('');
    try {
      const secretsPayload: Record<string, string> = {};
      for (const [k, v] of Object.entries(secretInputs)) {
        if (v && v.trim().length > 0) secretsPayload[k] = v.trim();
      }
      const res = await settingsApi.update({ settings: prefs, secrets: secretsPayload });
      setSecretStatus(res.data.secrets || {});
      setSecretInputs({});
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (e: any) {
      setError('Не удалось сохранить настройки: ' + (e?.message || 'ошибка сети'));
    } finally {
      setSaving(false);
    }
  };

  const handleAddAccount = async () => {
    if (!newAccount.accountName.trim()) return;
    setAddingAccount(true);
    setError('');
    try {
      await socialAccounts.create({
        platform: newAccount.platform,
        accountName: newAccount.accountName.trim(),
        token: newAccount.token.trim() || undefined,
      });
      setNewAccount({ platform: 'instagram', accountName: '', token: '' });
      const accRes = await socialAccounts.list();
      setAccounts(accRes.data.accounts || []);
    } catch (e: any) {
      setError('Не удалось добавить аккаунт: ' + (e?.message || 'ошибка'));
    } finally {
      setAddingAccount(false);
    }
  };

  const handleDisconnect = async (id: string) => {
    setError('');
    try {
      await socialAccounts.disconnect(id);
      setAccounts((prev) => prev.filter((a) => a.id !== id));
    } catch (e: any) {
      setError('Не удалось отключить аккаунт: ' + (e?.message || 'ошибка'));
    }
  };

  const configuredSearch =
    (secretStatus.googleSearchApiKey && secretStatus.googleSearchCx) ||
    (secretStatus.yandexApiKey && secretStatus.yandexUser);

  return (
    <div className="space-y-6 pb-16">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900">Настройки</h1>
        <p className="text-gray-500 mt-2">Аккаунты, доступы и параметры системы</p>
      </div>

      {error && (
        <div className="flex items-center gap-2 text-red-700 bg-red-50 border border-red-200 px-4 py-3 rounded-lg">
          <AlertCircle size={18} />
          <span className="text-sm">{error}</span>
        </div>
      )}

      {loading ? (
        <p className="text-gray-500">Загрузка настроек…</p>
      ) : (
        <>
          {/* Permissions & API keys */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-1 flex items-center gap-2">
              <ShieldCheck size={20} className="text-emerald-600" />
              Разрешения и доступы
            </h2>
            <p className="text-sm text-gray-500 mb-6">
              Ключи сохраняются на сервере в зашифрованном виде. После сохранения повторно вводить их не нужно.
            </p>

            <div className="mb-5">
              <span
                className={`inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-medium ${
                  configuredSearch ? 'bg-green-100 text-green-800' : 'bg-yellow-100 text-yellow-800'
                }`}
              >
                {configuredSearch ? <CheckCircle2 size={14} /> : <AlertCircle size={14} />}
                {configuredSearch
                  ? 'Поиск лидов подключён'
                  : 'Поиск лидов не подключён — добавьте ключи Google или Yandex'}
              </span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
              {SECRET_FIELDS.map((f) => (
                <div key={f.key}>
                  <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-2">
                    {f.label}
                    {secretStatus[f.key] && (
                      <span className="inline-flex items-center gap-1 text-xs text-green-700">
                        <CheckCircle2 size={13} /> сохранён
                      </span>
                    )}
                  </label>
                  <input
                    type="password"
                    autoComplete="new-password"
                    placeholder={secretStatus[f.key] ? '•••••••• (оставьте пустым, чтобы не менять)' : f.placeholder}
                    value={secretInputs[f.key] || ''}
                    onChange={(e) =>
                      setSecretInputs((prev) => ({ ...prev, [f.key]: e.target.value }))
                    }
                    className="input"
                  />
                  <p className="text-xs text-gray-400 mt-1">{f.hint}</p>
                </div>
              ))}
            </div>
          </div>

          {/* Connected accounts */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-6 flex items-center gap-2">
              <LinkIcon size={20} className="text-blue-600" />
              Подключённые аккаунты
            </h2>

            {accounts.length === 0 ? (
              <p className="text-gray-500 mb-6">Нет подключённых аккаунтов</p>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
                {accounts.map((account) => (
                  <div key={account.id} className="p-4 border border-gray-200 rounded-lg">
                    <div className="flex items-center justify-between mb-3">
                      <div>
                        <p className="font-medium text-gray-900 capitalize">{account.platform}</p>
                        <p className="text-sm text-gray-600">{account.accountName}</p>
                      </div>
                      <span className="px-3 py-1 bg-green-100 text-green-800 rounded-full text-xs font-medium">
                        {account.status}
                      </span>
                    </div>
                    <button
                      onClick={() => handleDisconnect(account.id)}
                      className="flex items-center gap-2 px-3 py-2 bg-red-50 hover:bg-red-100 text-red-700 rounded-lg text-sm font-medium transition-colors"
                    >
                      <Trash2 size={15} /> Отключить
                    </button>
                  </div>
                ))}
              </div>
            )}

            <div className="pt-6 border-t border-gray-200">
              <p className="text-sm font-medium text-gray-700 mb-3 flex items-center gap-2">
                <Key size={16} /> Добавить аккаунт
              </p>
              <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                <select
                  value={newAccount.platform}
                  onChange={(e) => setNewAccount({ ...newAccount, platform: e.target.value })}
                  className="input"
                >
                  <option value="instagram">Instagram</option>
                  <option value="telegram">Telegram</option>
                  <option value="vk">VK</option>
                  <option value="youtube">YouTube</option>
                  <option value="tiktok">TikTok</option>
                </select>
                <input
                  type="text"
                  placeholder="Имя аккаунта"
                  value={newAccount.accountName}
                  onChange={(e) => setNewAccount({ ...newAccount, accountName: e.target.value })}
                  className="input"
                />
                <input
                  type="password"
                  placeholder="Токен (необязательно)"
                  value={newAccount.token}
                  onChange={(e) => setNewAccount({ ...newAccount, token: e.target.value })}
                  className="input"
                />
                <button
                  onClick={handleAddAccount}
                  disabled={addingAccount || !newAccount.accountName.trim()}
                  className="btn-primary flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Plus size={18} />
                  {addingAccount ? 'Добавление…' : 'Добавить'}
                </button>
              </div>
            </div>
          </div>

          {/* Preferences */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-6 flex items-center gap-2">
              <SettingsIcon size={20} className="text-purple-600" />
              Предпочтения
            </h2>

            <div className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Язык контента
                  </label>
                  <select
                    value={prefs.contentLanguage}
                    onChange={(e) => setPrefs({ ...prefs, contentLanguage: e.target.value })}
                    className="input"
                  >
                    <option>Russian</option>
                    <option>English</option>
                    <option>Spanish</option>
                    <option>French</option>
                    <option>German</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Часовой пояс
                  </label>
                  <select
                    value={prefs.timezone}
                    onChange={(e) => setPrefs({ ...prefs, timezone: e.target.value })}
                    className="input"
                  >
                    <option>UTC</option>
                    <option>UTC-5 (EST)</option>
                    <option>UTC+0 (GMT)</option>
                    <option>UTC+1 (CET)</option>
                    <option>UTC+3 (MSK)</option>
                  </select>
                </div>
              </div>

              <label className="flex items-center gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={prefs.notifyScheduled}
                  onChange={(e) => setPrefs({ ...prefs, notifyScheduled: e.target.checked })}
                  className="w-4 h-4"
                />
                <span className="text-sm text-gray-700">
                  Уведомлять по email о запланированных постах
                </span>
              </label>

              <label className="flex items-center gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={prefs.notifyThreshold}
                  onChange={(e) => setPrefs({ ...prefs, notifyThreshold: e.target.checked })}
                  className="w-4 h-4"
                />
                <span className="text-sm text-gray-700">
                  Уведомлять при превышении порога комментариев
                </span>
              </label>

              <label className="flex items-center gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={prefs.autoRespond}
                  onChange={(e) => setPrefs({ ...prefs, autoRespond: e.target.checked })}
                  className="w-4 h-4"
                />
                <span className="text-sm text-gray-700">
                  Разрешить ИИ автоматически отвечать на комментарии
                </span>
              </label>
            </div>
          </div>

          {/* AI configuration */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-6">Настройка ИИ-агента</h2>

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Провайдер ИИ</label>
                <select
                  value={prefs.aiProvider}
                  onChange={(e) => setPrefs({ ...prefs, aiProvider: e.target.value })}
                  className="input max-w-md"
                >
                  <option value="claude">Claude (рекомендуется)</option>
                  <option value="openai">OpenAI GPT</option>
                  <option value="gemini">Google Gemini</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Тон контента</label>
                <input
                  type="text"
                  placeholder="например: вовлекающий, профессиональный, дружелюбный"
                  value={prefs.contentTone}
                  onChange={(e) => setPrefs({ ...prefs, contentTone: e.target.value })}
                  className="input max-w-md"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Ценности бренда
                </label>
                <textarea
                  placeholder="Опишите ценности и правила вашего бренда…"
                  value={prefs.brandValues}
                  onChange={(e) => setPrefs({ ...prefs, brandValues: e.target.value })}
                  className="input max-w-md h-32"
                />
              </div>
            </div>
          </div>

          {/* Save bar */}
          <div className="flex items-center gap-4">
            <button
              onClick={handleSaveAll}
              disabled={saving}
              className="btn-primary flex items-center gap-2 disabled:opacity-50"
            >
              <Save size={18} />
              {saving ? 'Сохранение…' : 'Сохранить настройки'}
            </button>

            {saved && (
              <div className="flex items-center gap-2 text-green-700 bg-green-50 px-4 py-2 rounded-lg">
                <CheckCircle2 size={16} />
                <span className="text-sm font-medium">Настройки сохранены</span>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
