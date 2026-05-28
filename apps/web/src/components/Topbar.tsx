import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { QrCode, Moon, Sun } from 'lucide-react'
import { useSessionStore } from '../stores/sessionStore'

export default function Topbar() {
  const [isDark, setIsDark] = useState(true)
  const navigate = useNavigate()
  const createSession = useSessionStore((s) => s.createSession)

  const handleCreateQR = async () => {
    const session = await createSession()
    if (session) {
      navigate('/')
    }
  }

  const toggleTheme = () => {
    setIsDark(!isDark)
    document.documentElement.classList.toggle('dark')
  }

  return (
    <header className="h-16 bg-white dark:bg-slate-900 border-b border-slate-200 dark:border-slate-800 flex items-center justify-between px-6">
      <div className="flex items-center gap-4">
        <div className="text-sm text-slate-600 dark:text-slate-400">
          LAN-режим активен
        </div>
      </div>

      <div className="flex items-center gap-4">
        <button
          onClick={handleCreateQR}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
        >
          <QrCode size={18} />
          <span>Создать QR</span>
        </button>

        <button
          onClick={toggleTheme}
          className="p-2 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-lg transition-colors"
        >
          {isDark ? <Sun size={18} /> : <Moon size={18} />}
        </button>

        <div className="h-8 w-px bg-slate-200 dark:bg-slate-700" />

        <div className="text-sm text-slate-600 dark:text-slate-400">
          Оператор
        </div>
      </div>
    </header>
  )
}
