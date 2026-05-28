import { useState } from 'react'
import { Lock } from 'lucide-react'

export default function NetworkSettings() {
  const [lanOnly, setLanOnly] = useState(true)
  const [showAdvanced, setShowAdvanced] = useState(false)

  return (
    <div className="p-8">
      <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-8">
        Сетевые настройки
      </h1>

      <div className="max-w-2xl space-y-6">
        {/* Основные настройки */}
        <div className="bg-white dark:bg-slate-900 rounded-lg p-6 border border-slate-200 dark:border-slate-800">
          <h2 className="font-semibold text-slate-900 dark:text-white mb-4">
            Основные
          </h2>

          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-slate-900 dark:text-white">LAN-режим</p>
                <p className="text-sm text-slate-500 dark:text-slate-400">
                  Подключение только в локальной сети
                </p>
              </div>
              <button
                onClick={() => setLanOnly(!lanOnly)}
                className={`relative w-12 h-6 rounded-full transition-colors ${
                  lanOnly
                    ? 'bg-green-600'
                    : 'bg-slate-300 dark:bg-slate-600'
                }`}
              >
                <div
                  className={`absolute top-1 left-1 w-4 h-4 bg-white rounded-full transition-transform ${
                    lanOnly ? 'translate-x-6' : ''
                  }`}
                />
              </button>
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-900 dark:text-white mb-2">
                Адрес локального сервера
              </label>
              <input
                type="text"
                placeholder="http://192.168.1.100:3000"
                defaultValue="http://localhost:3000"
                className="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-800 text-slate-900 dark:text-white text-sm"
              />
            </div>
          </div>
        </div>

        {/* Расширенные настройки */}
        <div className="bg-white dark:bg-slate-900 rounded-lg p-6 border border-slate-200 dark:border-slate-800">
          <button
            onClick={() => setShowAdvanced(!showAdvanced)}
            className="w-full text-left flex items-center justify-between"
          >
            <h2 className="font-semibold text-slate-900 dark:text-white">
              Расширенные настройки
            </h2>
            <span className={`text-slate-500 transition-transform ${showAdvanced ? 'rotate-180' : ''}`}>
              ▼
            </span>
          </button>

          {showAdvanced && (
            <div className="mt-6 space-y-4 border-t border-slate-200 dark:border-slate-700 pt-6">
              <div>
                <label className="block text-sm font-medium text-slate-900 dark:text-white mb-2">
                  STUN серверы (через запятую)
                </label>
                <input
                  type="text"
                  placeholder="stun.l.google.com:19302"
                  className="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-800 text-slate-900 dark:text-white text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-900 dark:text-white mb-2">
                  TURN сервер
                </label>
                <input
                  type="text"
                  placeholder="turn.example.com:3478"
                  className="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-800 text-slate-900 dark:text-white text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-900 dark:text-white mb-2">
                  Диагностический прокси URL
                </label>
                <input
                  type="text"
                  placeholder="http://localhost:8080"
                  className="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-800 text-slate-900 dark:text-white text-sm"
                />
                <p className="text-xs text-slate-500 dark:text-slate-400 mt-2 flex items-center gap-2">
                  <Lock size={14} />
                  Используется только для отладки и логирования API
                </p>
              </div>
            </div>
          )}
        </div>

        {/* Диагностика */}
        <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-900/50 rounded-lg p-6">
          <h3 className="font-semibold text-blue-900 dark:text-blue-100 mb-2">
            Информация о сети
          </h3>
          <p className="text-sm text-blue-800 dark:text-blue-200 mb-3">
            Локальный IP: 192.168.1.100
          </p>
          <p className="text-xs text-blue-700 dark:text-blue-300">
            Все подключения происходят внутри одной Wi-Fi сети. Приложение не использует скрытый доступ или обход разрешений.
          </p>
        </div>
      </div>
    </div>
  )
}
