import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { Plus, Smartphone } from 'lucide-react'
import QRCode from 'qrcode.react'
import { useSessionStore } from '../stores/sessionStore'
import { useDeviceStore } from '../stores/deviceStore'

export default function Dashboard() {
  const navigate = useNavigate()
  const currentSession = useSessionStore((s) => s.currentSession)
  const createSession = useSessionStore((s) => s.createSession)
  const devices = useDeviceStore((s) => s.devices)
  const fetchDevices = useDeviceStore((s) => s.fetchDevices)
  const setSelectedDevice = useDeviceStore((s) => s.setSelectedDevice)

  useEffect(() => {
    fetchDevices()
  }, [fetchDevices])

  const handleCreateQR = async () => {
    const session = await createSession()
    if (session) {
      // Stay on dashboard to show QR
    }
  }

  const handleOpenDevice = (device: typeof devices[0]) => {
    setSelectedDevice(device)
    navigate('/devices')
  }

  return (
    <div className="p-8">
      {!currentSession ? (
        <div className="max-w-2xl">
          <div className="text-center py-16">
            <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-100 dark:bg-blue-900/30 mb-4">
              <Smartphone className="text-blue-600 dark:text-blue-400" size={32} />
            </div>
            <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-2">
              Подключите телефон
            </h1>
            <p className="text-slate-600 dark:text-slate-400 mb-8">
              Создайте QR-код, отсканируйте его телефоном и подтвердите подключение.
            </p>
            <button
              onClick={handleCreateQR}
              className="inline-flex items-center gap-2 px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors"
            >
              <Plus size={20} />
              Создать QR
            </button>
          </div>
        </div>
      ) : (
        <div className="max-w-2xl">
          <div className="bg-white dark:bg-slate-900 rounded-2xl shadow-sm p-8 border border-slate-200 dark:border-slate-800">
            <h2 className="text-xl font-semibold text-slate-900 dark:text-white mb-6">
              Подключение
            </h2>

            <div className="flex gap-8">
              <div className="flex-1">
                <div className="bg-white dark:bg-slate-950 p-4 rounded-lg border border-slate-200 dark:border-slate-800 inline-block">
                  <QRCode
                    value={currentSession.joinUrl}
                    size={200}
                    level="H"
                    includeMargin={true}
                  />
                </div>
              </div>

              <div className="flex-1">
                <h3 className="font-semibold text-slate-900 dark:text-white mb-4">
                  Инструкция:
                </h3>
                <ol className="space-y-3 text-sm text-slate-600 dark:text-slate-400">
                  <li className="flex gap-3">
                    <span className="font-semibold text-blue-600 dark:text-blue-400">1</span>
                    <span>Откройте камеру на телефоне</span>
                  </li>
                  <li className="flex gap-3">
                    <span className="font-semibold text-blue-600 dark:text-blue-400">2</span>
                    <span>Отсканируйте этот QR-код</span>
                  </li>
                  <li className="flex gap-3">
                    <span className="font-semibold text-blue-600 dark:text-blue-400">3</span>
                    <span>Подтвердите подключение</span>
                  </li>
                </ol>

                <div className="mt-6 p-4 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-900/50 rounded-lg">
                  <p className="text-xs text-amber-800 dark:text-amber-200">
                    <span className="font-semibold">Статус:</span> Ожидаем сканирование
                  </p>
                </div>
              </div>
            </div>

            <div className="mt-6 flex gap-3">
              <button
                onClick={() => useSessionStore.setState({ currentSession: null })}
                className="px-4 py-2 text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-lg transition-colors"
              >
                Отменить
              </button>
              <button
                onClick={() => {
                  const text = currentSession.joinUrl
                  navigator.clipboard.writeText(text)
                }}
                className="px-4 py-2 bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700 rounded-lg transition-colors"
              >
                Скопировать ссылку
              </button>
            </div>
          </div>
        </div>
      )}

      {devices.length > 0 && (
        <div className="mt-12">
          <h2 className="text-2xl font-bold text-slate-900 dark:text-white mb-6">
            Подключенные устройства
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {devices.map((device) => (
              <div
                key={device.id}
                className="bg-white dark:bg-slate-900 rounded-lg p-4 border border-slate-200 dark:border-slate-800 hover:border-slate-300 dark:hover:border-slate-700 transition-colors"
              >
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <Smartphone size={20} className="text-slate-400" />
                    <div>
                      <h3 className="font-semibold text-slate-900 dark:text-white">
                        {device.displayName}
                      </h3>
                      <p className="text-xs text-slate-500 dark:text-slate-400">
                        {device.model}
                      </p>
                    </div>
                  </div>
                  <div
                    className={`text-xs px-2 py-1 rounded font-medium ${
                      device.status === 'online'
                        ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400'
                        : 'bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-400'
                    }`}
                  >
                    {device.status === 'online' ? 'Online' : 'Offline'}
                  </div>
                </div>

                <p className="text-xs text-slate-500 dark:text-slate-400 mb-4">
                  {device.osName} {device.osVersion}
                </p>

                <button
                  onClick={() => handleOpenDevice(device)}
                  className="w-full px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium rounded-lg transition-colors"
                >
                  Открыть профиль
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
