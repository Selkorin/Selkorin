import { Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard,
  FileText,
  TrendingUp,
  BarChart3,
  Settings,
  Eye,
  Target,
} from 'lucide-react';

export default function Sidebar() {
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path;

  const navItems = [
    { path: '/', icon: LayoutDashboard, label: 'Dashboard' },
    { path: '/content', icon: FileText, label: 'Content' },
    { path: '/competitors', icon: Eye, label: 'Competitors' },
    { path: '/leads', icon: Target, label: 'Лиды' },
    { path: '/analytics', icon: BarChart3, label: 'Analytics' },
    { path: '/settings', icon: Settings, label: 'Settings' },
  ];

  return (
    <aside className="w-64 bg-slate-900 text-white">
      <div className="p-6 border-b border-slate-700">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center font-bold">
            W
          </div>
          <div>
            <h1 className="font-bold text-lg">WAI Social</h1>
            <p className="text-xs text-slate-400">Brain</p>
          </div>
        </div>
      </div>

      <nav className="mt-6">
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

      <div className="absolute bottom-0 left-0 right-0 p-6 border-t border-slate-700 w-64">
        <div className="bg-slate-800 rounded-lg p-4">
          <p className="text-sm font-medium text-white mb-2">💡 Quick Tip</p>
          <p className="text-xs text-slate-300">
            Use keyboard shortcuts to navigate faster. Press <kbd>?</kbd> for help.
          </p>
        </div>
      </div>
    </aside>
  );
}
