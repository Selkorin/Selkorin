import { useEffect } from 'react'
import { Smartphone, Monitor, Wifi } from 'lucide-react'
import { useDeviceStore } from '../stores/deviceStore'

export default function Devices() {
  const devices = useDeviceStore((s) => s.devices)
  const fetchDevices = useDeviceStore((s) => s.fetchDevices)
  const selectedDevice = useDeviceStore((s) => s.selectedDevice)

  useEffect(() => {
    fetchDevices()
  }, [fetchDevices])

  if (!selectedDevice) {
    return (
      <div className="p-8">
        <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-8">
          Устройства
        </h1>

        {devices.length === 0 ? (
          <div className="text-center py-16">
            <Smartphone size={48} className="text-slate-300 dark:text-slate-700 mx-auto mb-4" />
            <p className="text-slate-500 dark:text-slate-400">
              Нет подключенных устройств
            </p>
          </div>
        ) : (
          <div className="space-y-4">
            {devices.map((device) => (
              <div
                key={device.id}
                className="bg-white dark:bg-slate-900 rounded-lg p-6 border border-slate-200 dark:border-slate-800 hover:border-slate-300 dark:hover:border-slate-700 transition-colors cursor-pointer"
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-3 mb-2">
                      <Smartphone size={20} className="text-slate-400" />
                      <h3 className="font-semibold text-slate-900 dark:text-white text-lg">
                        {device.displayName}
                      </h3>
                      <span
                        className={`text-xs px-2 py-1 rounded font-medium ${
                          device.status === 'online'
                            ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400'
                            : 'bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-400'
                        }`}
                      >
                        {device.status}
                      </span>
                    </div>

                    <div className="grid grid-cols-2 gap-4 mt-4 text-sm">
                      <div>
                        <p className="text-slate-500 dark:text-slate-400">Модель</p>
                        <p className="text-slate-900 dark:text-white font-medium">
                          {device.model || 'N/A'}
                        </p>
                      </div>
                      <div>
                        <p className="text-slate-500 dark:text-slate-400">ОС</p>
                        <p className="text-slate-900 dark:text-white font-medium">
                          {device.osName} {device.osVersion}
                        </p>
                      </div>
                      <div>
                        <p className="text-slate-500 dark:text-slate-400">Браузер</p>
                        <p className="text-slate-900 dark:text-white font-medium">
                          {device.browserName} {device.browserVersion}
                        </p>
                      </div>
                      <div>
                        <p className="text-slate-500 dark:text-slate-400">Экран</p>
                        <p className="text-slate-900 dark:text-white font-medium">
                          {device.screenWidth}x{device.screenHeight}
                        </p>
                      </div>
                    </div>
                  </div>

                  <button
                    className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors"
                  >
                    Открыть
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="p-8">
      <div className="max-w-3xl">
        <button
          onClick={() => useDeviceStore.setState({ selectedDevice: null })}
          className="text-blue-600 dark:text-blue-400 hover:underline mb-6"
        >
          ← Назад к списку
        </button>

        <div className="bg-white dark:bg-slate-900 rounded-2xl p-8 border border-slate-200 dark:border-slate-800">
          <div className="flex items-start justify-between mb-8">
            <div>
              <h1 className="text-3xl font-bold text-slate-900 dark:text-white">
                {selectedDevice.displayName}
              </h1>
              <p className="text-slate-500 dark:text-slate-400 mt-1">
                {selectedDevice.model}
              </p>
            </div>
            <div
              className={`text-sm px-3 py-1 rounded-full font-medium ${
                selectedDevice.status === 'online'
                  ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400'
                  : 'bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-400'
              }`}
            >
              {selectedDevice.status}
            </div>
          </div>

          {/* Информация об устройстве */}
          <div className="mb-8">
            <h2 className="font-semibold text-slate-900 dark:text-white mb-4">
              Информация об устройстве
            </h2>
            <div className="grid grid-cols-2 gap-4">
              <div className="p-4 bg-slate-50 dark:bg-slate-800 rounded-lg">
                <p className="text-xs text-slate-500 dark:text-slate-400 mb-1">Операционная система</p>
                <p className="font-medium text-slate-900 dark:text-white">
                  {selectedDevice.osName} {selectedDevice.osVersion}
                </p>
              </div>
              <div className="p-4 bg-slate-50 dark:bg-slate-800 rounded-lg">
                <p className="text-xs text-slate-500 dark:text-slate-400 mb-1">Браузер</p>
                <p className="font-medium text-slate-900 dark:text-white">
                  {selectedDevice.browserName} {selectedDevice.browserVersion}
                </p>
              </div>
              <div className="p-4 bg-slate-50 dark:bg-slate-800 rounded-lg">
                <p className="text-xs text-slate-500 dark:text-slate-400 mb-1">Разрешение</p>
                <p className="font-medium text-slate-900 dark:text-white">
                  {selectedDevice.screenWidth}x{selectedDevice.screenHeight}
                </p>
              </div>
              <div className="p-4 bg-slate-50 dark:bg-slate-800 rounded-lg">
                <p className="text-xs text-slate-500 dark:text-slate-400 mb-1">Язык</p>
                <p className="font-medium text-slate-900 dark:text-white">
                  {selectedDevice.language || 'N/A'}
                </p>
              </div>
            </div>
          </div>

          {/* Разрешения */}
          {selectedDevice.permissions && (
            <div className="mb-8">
              <h2 className="font-semibold text-slate-900 dark:text-white mb-4">
                Разрешения
              </h2>
              <div className="space-y-2">
                {[
                  { label: 'Камера', value: selectedDevice.permissions.camera },
                  { label: 'Микрофон', value: selectedDevice.permissions.microphone },
                  { label: 'Демонстрация экрана', value: selectedDevice.permissions.screenShare },
                  { label: 'Удаленное управление', value: selectedDevice.permissions.remoteControlNativeAgent },
                ].map((perm) => (
                  <div key={perm.label} className="flex items-center gap-3 p-3 bg-slate-50 dark:bg-slate-800 rounded-lg">
                    <div className={`w-2 h-2 rounded-full ${perm.value ? 'bg-green-500' : 'bg-slate-400'}`} />
                    <span className="text-slate-900 dark:text-white">{perm.label}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Действия */}
          <div className="flex gap-3">
            <button className="flex-1 px-4 py-3 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors">
              Запустить экран телефона
            </button>
            <button className="px-4 py-3 bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700 font-medium rounded-lg transition-colors">
              <Wifi size={20} />
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
