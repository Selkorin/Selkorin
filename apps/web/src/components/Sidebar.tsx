import { Link, useLocation } from 'react-router-dom'
import {
  LayoutDashboard,
  Smartphone,
  Network,
  LogSquare,
  Settings,
  Clock
} from 'lucide-react'

const navItems = [
  { path: '/', label: 'Главная', icon: LayoutDashboard },
  { path: '/devices', label: 'Устройства', icon: Smartphone },
  { path: '/sessions', label: 'Сессии', icon: Clock },
  { path: '/network', label: 'Сеть', icon: Network },
  { path: '/audit', label: 'Журнал', icon: LogSquare },
  { path: '/settings', label: 'Настройки', icon: Settings },
]

export default function Sidebar() {
  const location = useLocation()

  return (
    <aside className="w-64 bg-white dark:bg-slate-900 border-r border-slate-200 dark:border-slate-800 flex flex-col">
      <div className="p-6 border-b border-slate-200 dark:border-slate-800">
        <h1 className="text-2xl font-bold text-slate-900 dark:text-white">
          Remote Support
        </h1>
      </div>

      <nav className="flex-1 p-4 space-y-2">
        {navItems.map((item) => {
          const Icon = item.icon
          const isActive = location.pathname === item.path

          return (
            <Link
              key={item.path}
              to={item.path}
              className={`flex items-center gap-3 px-4 py-2 rounded-lg transition-colors ${
                isActive
                  ? 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400'
                  : 'text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800'
              }`}
            >
              <Icon size={20} />
              <span>{item.label}</span>
            </Link>
          )
        })}
      </nav>

      <div className="p-4 border-t border-slate-200 dark:border-slate-800 text-xs text-slate-500 dark:text-slate-400">
        <p>v0.1.0</p>
      </div>
    </aside>
  )
}
