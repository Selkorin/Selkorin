# Remote Support Application

Локальное веб-приложение для удаленной помощи мобильным устройствам через Wi-Fi сеть с явным согласием пользователя.

## Особенности

✅ **Безопасность**
- Только добровольное подключение через QR-код
- Явное подтверждение на мобильном устройстве
- Видимая активная сессия с кнопкой отключения
- Аудит всех событий
- Без скрытого доступа или обхода разрешений

✅ **Функции**
- Создание QR-кода для паирования
- WebRTC трансляция экрана/камеры
- Управление устройством через подсказки
- Просмотр информации об устройстве (модель, ОС, браузер)
- История сессий и журнал событий
- Настройки сети (STUN/TURN, LAN mode)

## Архитектура

```
├── apps/
│   ├── server/          # Backend (Node.js + Express + Socket.IO)
│   └── web/             # Frontend (React + TypeScript + Vite)
└── packages/
    └── shared/          # Общие типы и схемы
```

## Требования

- Node.js 20.x
- npm 10.x

## Установка и запуск

### 1. Клонирование и установка зависимостей

```bash
npm install
```

### 2. Настройка переменных окружения

```bash
cp .env.example .env
```

Отредактируйте `.env` если необходимо:
```env
NODE_ENV=development
PORT=3000
APP_URL=http://localhost:5173
DATABASE_URL=file:./dev.db
CORS_ORIGIN=http://localhost:5173
```

### 3. Инициализация базы данных

```bash
npm run db:push --workspace=apps/server
```

### 4. Запуск в режиме разработки

```bash
npm run dev
```

Это запустит оба приложения одновременно:
- Frontend: http://localhost:5173
- Backend: http://localhost:3000

### 5. Сборка для production

```bash
npm run build
```

### 6. Запуск в production

```bash
npm start
```

## API Endpoints

### Sessions
- `POST /api/sessions` - Создать сессию с QR-кодом
- `GET /api/sessions/:id` - Получить статус сессии

### Devices
- `GET /api/devices` - Список всех устройств
- `GET /api/devices/:id` - Информация об устройстве

### Audit
- `GET /api/audit` - Журнал событий

## Socket.IO Events

### Device to Server
- `device:join-by-token` - Устройство присоединяется по QR токену
- `device:approve-session` - Устройство подтверждает подключение
- `device:approve-screen` - Устройство разрешает трансляцию экрана
- `device:disconnect` - Устройство отключается

### Operator to Server
- `operator:request-screen` - Запрос трансляции экрана
- `operator:request-camera` - Запрос камеры
- `operator:send-guidance` - Отправка подсказки

### WebRTC Signaling
- `webrtc:offer` - WebRTC offer
- `webrtc:answer` - WebRTC answer
- `webrtc:ice-candidate` - ICE candidate

## UI Структура

### Оператор (Web)
1. **Dashboard** - Главная страница с QR и активными устройствами
2. **Devices** - Список подключенных устройств и профили
3. **Sessions** - История сессий
4. **Network** - Сетевые настройки (LAN, STUN/TURN)
5. **Audit** - Журнал событий
6. **Settings** - Общие настройки

### Пользователь (Mobile)
- Страница присоединения `/join/:token`
- Запрос разрешения на подключение
- Активная сессия с кнопкой отключения
- Запросы разрешений (экран, камера)

## Безопасность

### Механизмы защиты
- QR токены имеют TTL 5 минут
- Pairing keys одноразовые
- Все действия логируются
- CORS защита
- Helmet для HTTP безопасности
- Rate limiting на API endpoints
- Явное подтверждение каждого действия на устройстве

### Что НЕ делает приложение
- ❌ Не подменяет fingerprint устройства
- ❌ Не обходит системные разрешения
- ❌ Не имеет скрытого доступа
- ❌ Не использует прокси для подмены идентификаторов
- ❌ Не записывает экран без разрешения

## Разработка

### Структура backend

```typescript
// Основные сущности
DeviceSession  // Сессия паирования
Device         // Мобильное устройство
AuditLog       // Журнал событий
NetworkSettings // Настройки сети
```

### Структура frontend

```
src/
├── components/    # UI компоненты
├── pages/         # Страницы приложения
├── stores/        # Zustand хранилище
├── services/      # API и Socket.IO сервисы
└── types/         # TypeScript типы
```

## Следующие шаги для разработки

- [ ] Интеграция Android native-agent модуля (опционально)
- [ ] Реализация полного WebRTC streaming
- [ ] Улучшение UI для больших устройств
- [ ] Поддержка множественных операторов
- [ ] Шифрование WebRTC потока
- [ ] Метрики и аналитика

## Лицензия

MIT

## Контрибьютинг

Вклады приветствуются! Пожалуйста, создавайте PR с описанием изменений.
