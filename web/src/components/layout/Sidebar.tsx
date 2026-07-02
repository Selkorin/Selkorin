import { Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard,
  FileText,
  TrendingUp,
  BarChart3,
  Settings,
  Eye,
  Radar,
} from 'lucide-react';

export default function Sidebar() {
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path;

  const navItems = [
    { path: '/', icon: LayoutDashboard, label: 'Dashboard' },
    { path: '/content', icon: FileText, label: 'Content' },
    { path: '/leads', icon: Radar, label: 'Leads & Research' },
    { path: '/competitors', icon: Eye, label: 'Competitors' },
    { path: '/analytics', icon: BarChart3, label: 'Analytics' },
    { path: '/settings', icon: Settings, label: 'Settings' },
  ];

  return (
    <aside className="w-64 shrink-0 bg-slate-900 text-white flex flex-col h-screen">
      <div className="p-6 border-b border-slate-700 shrink-0">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center font-bold">
            A
          </div>
          <div>
            <h1 className="font-bold text-lg">ALAKEYA</h1>
            <p className="text-xs text-slate-400">AI Social Brain</p>
          </div>
        </div>
      </div>

      <nav className="mt-4 flex-1 overflow-y-auto">
        {navItems.map(({ path, icon: Icon, label }) => (
          <Link
            key={path}
            to={path}
            className={`flex items-center gap-3 px-6 py-3 transition-colors ${
              isActive(path)
                ? 'bg-blue-600 text-white'
                : 'text-slate-300 hover:bg-slate-800'
            }`}
          >
            <Icon size={20} />
            <span>{label}</span>
          </Link>
        ))}
      </nav>

      <div className="p-4 border-t border-slate-700 shrink-0">
        <div className="bg-slate-800 rounded-lg p-4">
          <p className="text-sm font-medium text-white mb-2 flex items-center gap-2">
            <TrendingUp size={16} /> Быстрый старт
          </p>
          <p className="text-xs text-slate-300">
            Добавьте ключи поиска в Настройках → Разрешения, чтобы включить сбор лидов.
          </p>
        </div>
      </div>
    </aside>
  );
}
