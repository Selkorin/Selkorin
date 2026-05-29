#!/usr/bin/env bash
#
# Локальный запуск WAI (бэкенд + интерфейс) одним адресом http://localhost:3000
# Использование:  ./start-local.sh
#
set -e
cd "$(dirname "$0")"

echo "==============================================="
echo "  WAI — локальный запуск (Mac/Linux)"
echo "==============================================="

# 1) Проверка Node.js
if ! command -v node >/dev/null 2>&1; then
  echo "❌ Node.js не найден. Установи LTS-версию с https://nodejs.org (нужна 20+),"
  echo "   затем запусти скрипт снова."
  exit 1
fi
NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "❌ Нужен Node.js 18+ (а лучше 20). Сейчас: $(node -v)"
  exit 1
fi
echo "✅ Node.js $(node -v)"

# 2) Файл окружения
if [ ! -f .env ]; then
  cp .env.development .env
  echo "📝 Создан .env из .env.development."
  echo "   Открой его и впиши YANDEX_MAPS_API_KEY (и при желании ключи 2ГИС/VK)."
fi

# 3) Зависимости и сборка бэкенда (postinstall соберёт TypeScript)
echo "📦 Устанавливаю зависимости бэкенда..."
npm install

# 4) Зависимости и сборка интерфейса
echo "🎨 Собираю веб-интерфейс..."
( cd web && npm install && npm run build )

# 5) Папка для локальной базы SQLite
mkdir -p data

# 6) Автооткрытие браузера через несколько секунд
(
  sleep 5
  if command -v open >/dev/null 2>&1; then open http://localhost:3000        # macOS
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open http://localhost:3000 # Linux
  fi
) >/dev/null 2>&1 &

echo ""
echo "🚀 Запускаю сервер на http://localhost:3000"
echo "   Дашборд и страница «Лиды» откроются в браузере автоматически."
echo "   Остановить: Ctrl + C"
echo ""

npm start
