# Remote Support Application - macOS Setup Guide

Полное руководство для запуска приложения на macOS.

## 📋 Требования

- **macOS** 10.15 или новее
- **Node.js** 20.x или новее
- **npm** 10.x или новее
- **Git** (опционально, для клонирования)

## 🚀 Быстрый старт (2 минуты)

### 1. Установка Node.js

Если у вас еще не установлен Node.js:

```bash
# Используя Homebrew
brew install node@20

# Или скачайте с https://nodejs.org/
```

Проверьте версию:
```bash
node --version  # должно быть v20.x.x или выше
npm --version   # должно быть 10.x.x или выше
```

### 2. Установка зависимостей

```bash
cd /path/to/Selkorin
npm install --legacy-peer-deps
```

### 3. Инициализация базы данных

```bash
npm run db:push --workspace=apps/server
```

### 4. Запуск приложения

#### Вариант A: Использование скрипта (рекомендуется)

```bash
./start-macos.sh
```

Скрипт автоматически:
- ✅ Закроет старые процессы на портах 3000 и 5173
- ✅ Запустит backend и frontend
- ✅ Откроет приложение в браузере
- ✅ Покажет ссылки для подключения

#### Вариант B: Ручной запуск

**Терминал 1 - Backend:**
```bash
npm run dev --workspace=apps/server
```

**Терминал 2 - Frontend:**
```bash
npm run dev --workspace=apps/web
```

Затем откройте браузер:
```bash
open http://localhost:5173
```

## 🎯 Использование

### Для оператора (на компьютере)

1. Откройте http://localhost:5173 в браузере
2. Нажмите кнопку "Создать QR"
3. На мобильном устройстве отсканируйте QR-код
4. Устройство появится в списке "Подключенные устройства"
5. Нажмите "Открыть профиль" для управления

### Для пользователя (на мобильном)

1. На компьютере создайте QR-код
2. На мобильном откройте камеру и отсканируйте QR
3. Подтвердите подключение на экране телефона
4. Видите активную сессию и кнопку отключения
5. Оператор может запросить экран или камеру

## 🔧 Полезные команды

```bash
# Запуск в режиме разработки (оба сервера)
npm run dev

# Запуск только backend
npm run dev --workspace=apps/server

# Запуск только frontend
npm run dev --workspace=apps/web

# Проверка типов TypeScript
npm run typecheck

# Сборка для production
npm run build

# Просмотр базы данных
npm run db:studio --workspace=apps/server

# Очистка node_modules
rm -rf node_modules && npm install --legacy-peer-deps
```

## 🔗 Адреса

| Сервис | Адрес | Порт |
|--------|-------|------|
| Frontend | http://localhost:5173 | 5173 |
| Backend | http://localhost:3000 | 3000 |
| Database | `./apps/server/dev.db` | - |
| WebSocket | ws://localhost:3000 | 3000 |

## 📝 Переменные окружения

Основной файл: `.env.development`

```env
NODE_ENV=development
PORT=3000
APP_URL=http://localhost:5173
DATABASE_URL=file:./dev.db
CORS_ORIGIN=http://localhost:5173
LAN_ONLY=true
LOCAL_SERVER_URL=http://localhost:3000
```

## 🐛 Решение проблем

### Ошибка: "Port 3000 is already in use"

```bash
# Найдите процесс на порту 3000
lsof -i :3000

# Убейте процесс
kill -9 <PID>

# Или используйте скрипт start-macos.sh, он автоматически очищает порты
```

### Ошибка: "Cannot find module"

```bash
# Переустановите зависимости
rm -rf node_modules
npm install --legacy-peer-deps
```

### Ошибка базы данных

```bash
# Пересоздайте базу данных
rm -f apps/server/dev.db
npm run db:push --workspace=apps/server
```

### Frontend не открывается в браузере

Откройте вручную:
```bash
open http://localhost:5173
```

### WebSocket не подключается

1. Убедитесь, что backend запущен (http://localhost:3000 должен быть доступен)
2. Проверьте консоль браузера (F12 → Console) на ошибки
3. Убедитесь, что CORS включен и правильно настроен

## 📱 Тестирование на мобильном (в одной сети Wi-Fi)

### На macOS (ваш компьютер):

1. Узнайте локальный IP адрес:
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

Вы должны увидеть что-то вроде: `192.168.x.x` или `10.0.x.x`

2. Измените `APP_URL` в `.env`:
```env
APP_URL=http://192.168.x.x:5173
```

3. Перезапустите приложение

### На мобильном (iOS/Android):

1. Убедитесь, что телефон в той же Wi-Fi сети
2. Отсканируйте QR-код, сгенерированный на компьютере
3. Подтвердите подключение

## 🏗️ Структура проекта

```
Selkorin/
├── apps/
│   ├── server/           # Backend (Express + Socket.IO)
│   │   ├── src/
│   │   ├── prisma/       # Database schema
│   │   ├── .env
│   │   └── package.json
│   └── web/              # Frontend (React + Vite)
│       ├── src/
│       ├── public/
│       └── package.json
├── packages/
│   └── shared/           # Shared TypeScript types
├── start-macos.sh        # Скрипт для запуска на macOS
├── package.json          # Root monorepo
└── .env.development      # Dev переменные окружения
```

## 🔐 Безопасность в dev режиме

Приложение в dev режиме:
- ✅ Использует HTTP (не HTTPS)
- ✅ CORS включен для localhost
- ✅ Database — SQLite в памяти
- ✅ Rate limiting отключен (для тестирования)

**Для production:**
- ✅ Используйте HTTPS
- ✅ Установите правильный CORS_ORIGIN
- ✅ Используйте PostgreSQL или другую production БД
- ✅ Включите rate limiting
- ✅ Установите strongsecret для сессий

## 📚 Документация

- [README.md](./README_REMOTE_SUPPORT.md) - Основная документация
- [API документация](./API.md) - Описание API endpoints
- [Дизайн приложения](./DESIGN.html) - UI/UX концепция

## 💬 Поддержка

Если у вас есть вопросы:
1. Проверьте консоль браузера (F12)
2. Проверьте консоль backend сервера
3. Используйте `npm run db:studio` для просмотра базы данных

## ✅ Checklist запуска

- [ ] Node.js 20.x установлен
- [ ] npm install --legacy-peer-deps выполнен
- [ ] npm run db:push выполнен
- [ ] start-macos.sh запущен или оба сервера запущены вручную
- [ ] Frontend открывается на http://localhost:5173
- [ ] Backend запущен на http://localhost:3000
- [ ] WebSocket подключение работает
- [ ] QR-код генерируется успешно

Готово! 🚀 Приложение полностью настроено и готово к работе на macOS.
