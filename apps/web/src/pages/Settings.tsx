export default function Settings() {
  return (
    <div className="p-8">
      <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-8">
        Настройки
      </h1>

      <div className="max-w-2xl space-y-6">
        <div className="bg-white dark:bg-slate-900 rounded-lg p-6 border border-slate-200 dark:border-slate-800">
          <h2 className="font-semibold text-slate-900 dark:text-white mb-4">
            Интерфейс
          </h2>
          <div className="flex items-center justify-between">
            <p className="text-slate-600 dark:text-slate-400">Темная тема</p>
            <input type="checkbox" defaultChecked className="w-4 h-4" />
          </div>
        </div>

        <div className="bg-white dark:bg-slate-900 rounded-lg p-6 border border-slate-200 dark:border-slate-800">
          <h2 className="font-semibold text-slate-900 dark:text-white mb-4">
            Безопасность
          </h2>
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <p className="text-slate-600 dark:text-slate-400">TTL токена паирования (минуты)</p>
              <input type="number" defaultValue={5} min={1} max={60} className="w-24 px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-800 text-slate-900 dark:text-white" />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
