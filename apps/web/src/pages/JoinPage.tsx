import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { AlertTriangle, CheckCircle, X } from 'lucide-react'

export default function JoinPage() {
  const { token } = useParams<{ token: string }>()
  const navigate = useNavigate()
  const [status, setStatus] = useState<'waiting' | 'approved' | 'active'>('waiting')
  const [sessionActive, setSessionActive] = useState(false)

  const handleApprove = async () => {
    // Отправить подтверждение на сервер
    setStatus('approved')
    setTimeout(() => {
      setStatus('active')
      setSessionActive(true)
    }, 1000)
  }

  const handleDisconnect = () => {
    setSessionActive(false)
    navigate('/')
  }

  if (!sessionActive) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-50 to-slate-100 dark:from-slate-900 dark:to-slate-950 flex items-center justify-center p-4">
        <div className="w-full max-w-sm bg-white dark:bg-slate-900 rounded-2xl shadow-lg p-6 border border-slate-200 dark:border-slate-800">
          <div className="flex justify-center mb-6">
            <div className="w-12 h-12 bg-blue-100 dark:bg-blue-900/30 rounded-full flex items-center justify-center">
              <AlertTriangle className="text-blue-600 dark:text-blue-400" size={24} />
            </div>
          </div>

          <h1 className="text-2xl font-bold text-center text-slate-900 dark:text-white mb-2">
            Запрос подключения
          </h1>
          <p className="text-center text-slate-600 dark:text-slate-400 mb-6 text-sm">
            К вашему устройству хочет подключиться оператор поддержки.
          </p>

          <div className="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-900/50 rounded-lg p-4 mb-6">
            <h3 className="font-semibold text-amber-900 dark:text-amber-100 mb-2 text-sm">
              Будут видны:
            </h3>
            <ul className="text-xs text-amber-800 dark:text-amber-200 space-y-1">
              <li>• Экран вашего устройства</li>
              <li>• Камера (при разрешении)</li>
              <li>• Информация об устройстве</li>
            </ul>
          </div>

          <div className="space-y-3">
            <button
              onClick={handleApprove}
              className="w-full px-4 py-3 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors"
            >
              Разрешить подключение
            </button>
            <button
              onClick={() => navigate('/')}
              className="w-full px-4 py-3 bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700 font-medium rounded-lg transition-colors"
            >
              Отклонить
            </button>
          </div>

          <p className="text-center text-xs text-slate-500 dark:text-slate-400 mt-4">
            Вы можете отключиться в любой момент
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-green-50 to-slate-100 dark:from-slate-900 dark:to-slate-950">
      {/* Active Session Banner */}
      <div className="bg-green-600 text-white py-3 px-4">
        <p className="text-center text-sm font-medium">
          Сессия активна • Оператор подключен
        </p>
      </div>

      <div className="flex items-center justify-center min-h-screen p-4">
        <div className="w-full max-w-sm bg-white dark:bg-slate-900 rounded-2xl shadow-lg p-6 border border-slate-200 dark:border-slate-800">
          <div className="flex justify-center mb-6">
            <div className="w-12 h-12 bg-green-100 dark:bg-green-900/30 rounded-full flex items-center justify-center">
              <CheckCircle className="text-green-600 dark:text-green-400" size={24} />
            </div>
          </div>

          <h1 className="text-2xl font-bold text-center text-slate-900 dark:text-white mb-6">
            Подключение установлено
          </h1>

          <div className="space-y-4 mb-6">
            <div className="p-4 bg-slate-50 dark:bg-slate-800 rounded-lg">
              <p className="text-xs text-slate-500 dark:text-slate-400 mb-1">Статус</p>
              <p className="font-semibold text-slate-900 dark:text-white">
                Готово к трансляции
              </p>
            </div>

            <div className="p-4 bg-slate-50 dark:bg-slate-800 rounded-lg">
              <p className="text-xs text-slate-500 dark:text-slate-400 mb-1">Оператор</p>
              <p className="font-semibold text-slate-900 dark:text-white">
                Подключен
              </p>
            </div>
          </div>

          <div className="space-y-3">
            <button
              disabled
              className="w-full px-4 py-3 bg-slate-200 dark:bg-slate-700 text-slate-500 dark:text-slate-400 font-medium rounded-lg opacity-50 cursor-not-allowed"
            >
              Показать экран (активно)
            </button>

            <button
              onClick={handleDisconnect}
              className="w-full px-4 py-3 bg-red-600 hover:bg-red-700 text-white font-medium rounded-lg transition-colors flex items-center justify-center gap-2"
            >
              <X size={18} />
              Отключиться
            </button>
          </div>

          <p className="text-center text-xs text-slate-500 dark:text-slate-400 mt-4">
            Оператор не может записывать экран без вашего согласия
          </p>
        </div>
      </div>
    </div>
  )
}
