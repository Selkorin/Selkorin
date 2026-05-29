# Техническое задание — WAI Маркетинг (лид-ген + контент)

Документ для продолжения работы с **Claude Code в терминале**. Здесь зафиксированы
текущее состояние, архитектура, договорённости и backlog. Ветка разработки:
`claude/happy-brown-1d64e`.

---

## 1. Что это за проект

WAI — внутренний инструмент маркетингового агентства:
- **Лид-генерация**: сбор компаний/сообществ из Яндекс.Карт, 2ГИС, ВКонтакте и
  Telegram в единую таблицу, фильтр «у кого нет сайта», ведение по воронке,
  экспорт в CSV.
- **Контент/SMM** (досталось от прежней версии): контент-планы, генерация постов,
  публикация, анализ конкурентов, интеграция Google Drive.

Фокус сейчас — на лид-гене.

## 2. Стек и архитектура

- **Бэкенд**: Node.js 20, TypeScript, Express, TypeORM. БД: SQLite (локально) /
  PostgreSQL (прод) — переключение через `USE_SQLITE`.
- **Фронтенд**: React 18 + Vite + Tailwind + react-router (папка `web/`).
- **Один origin**: в проде/локально бэкенд отдаёт собранный `web/dist` как статику
  + SPA-fallback, поэтому UI и API живут на одном адресе. API-база на фронте
  относительная (`/api`).

```
src/
  index.ts                 # роуты Express + раздача SPA
  config/database.ts       # выбор SQLite/PG, entities по __dirname + {ts,js}
  config/database-sqlite.ts# отдельный SQLite-datasource (entities перечислены явно)
  entities/                # TypeORM-сущности (в т.ч. Lead.ts)
  services/                # бизнес-логика
    LeadStorage.ts         # общий тип LeadResult + saveLeads() + dedupeLeads()
    YandexMapsService.ts    # Yandex Places API (Geosearch)
    TwoGisService.ts        # 2GIS Catalog/Places API
    TwoGisScraperService.ts # адаптер к внешнему parser-2gis (браузерный скрапер)
    VkService.ts            # VK API (groups.search + groups.getById)
    TelegramParserService.ts# TGStat API ИЛИ парсинг публичных t.me-страниц
  controllers/
    LeadGenController.ts    # /api/leads/* (поиск, список, статистика, CRUD, CSV)
web/
  src/pages/LeadGeneration.tsx   # страница «Лиды»
  src/services/api.ts            # клиент API (объект `leads`)
  src/components/layout/Sidebar.tsx
```

## 3. Модель данных — сущность `Lead`

Файл `src/entities/Lead.ts`. Ключевые поля: `name, category, categories,
address, phone, website, hasWebsite, latitude, longitude, yandexUrl, hours,
niche, region, source, status, notes, rawData, createdAt, updatedAt`.

- `source`: `yandex_maps | 2gis | vk | telegram`.
- `status` (воронка): `new | contacted | qualified | rejected | client`.
- `hasWebsite=false` → фильтр «у кого нет сайта».
- Дедуп при сохранении — по паре `name+address` (см. `LeadStorage.saveLeads`).

## 4. API лид-гена (`/api/leads`)

| Метод | Путь | Назначение |
|------|------|-----------|
| POST | `/api/leads/search` | Сбор лидов из источника |
| GET  | `/api/leads` | Список с фильтрами (`niche, region, status, hasWebsite, search, page, limit`) |
| GET  | `/api/leads/stats` | Агрегаты (всего/без сайта/по статусам) |
| GET  | `/api/leads/export/csv` | Выгрузка CSV (с BOM для Excel) |
| PUT  | `/api/leads/:id` | Обновить `status`/`notes` |
| DELETE | `/api/leads/:id` | Удалить лид |

`POST /api/leads/search` body:
```jsonc
{
  "niche": "кофейня",          // обязательно (кроме telegram c usernames / scraper c url)
  "region": "Москва",
  "noWebsiteOnly": true,
  "limit": 200,
  "save": true,
  "source": "both",            // yandex | 2gis | vk | telegram | both | 2gis_scraper
  "url": "https://2gis.ru/...",// только для 2gis_scraper
  "usernames": "@a, t.me/b"    // только для telegram без ключа TGStat
}
```
Ответ: `{ success, found, saved, bySource, errors?, leads }`.
`both` запускает Яндекс+2ГИС+ВК через `Promise.allSettled` — сбой одного
источника не валит остальные (его текст падает в `errors`).

## 5. Переменные окружения (`.env`)

```env
USE_SQLITE=true
DB_PATH=./data/wai.db
NODE_ENV=development
PORT=3000

YANDEX_MAPS_API_KEY=     # https://developer.tech.yandex.ru/ (Geosearch)
TWOGIS_API_KEY=          # https://dev.2gis.com/ (Places/Catalog)
VK_SERVICE_TOKEN=        # https://dev.vk.com/ (сервисный ключ)
TGSTAT_API_KEY=          # https://api.tgstat.ru (поиск каналов по нише, опц.)
# PARSER_2GIS_BIN=parser-2gis   # для браузерного скрапера 2ГИС
```
Подробности по получению ключей — в `LEADGEN.md`.

## 6. Как запускать

**Локально (Mac):** двойной клик `WAI-Local.command` или `./start-local.sh`
→ ставит зависимости, собирает фронт, поднимает на http://localhost:3000.
Подробно — `RUN_LOCAL.md`.

**Сборка/проверка вручную:**
```bash
npm install            # backend (postinstall = tsc)
cd web && npm install && npm run build && cd ..
npm run build          # должно быть exit 0
npm start              # node dist/index.js
```

**Деплой:** Railway/Render из репозитория, builder = Dockerfile. Шаги — `DEPLOYMENT.md`.

## 7. Договорённости (важно соблюдать)

- **Только парсеры/официальные API.** НЕ добавлять накрутку, автолайки,
  авто-действия от имени пользователя, массовую выгрузку участников групп для
  холодных рассылок, обход капчи. Причины — в `LEADGEN.md` §7.
- Новый источник лидов = новый сервис в `src/services/*`, возвращающий
  `LeadResult[]` и использующий `saveLeads`/`dedupeLeads` из `LeadStorage.ts`.
  Подключение — через `source` в `LeadGenController.search`.
- Строгий TypeScript включён; сборка должна оставаться **exit 0**
  (`npm run build`). Декораторы TypeORM настроены в `tsconfig.json`.
- Все собранные данные идут в одну таблицу `leads`, дедуп обязателен.

## 8. Backlog (приоритет сверху вниз)

> Для каждой задачи: ветка от `claude/happy-brown-1d64e`, зелёная сборка,
> ручная проверка эндпойнта/страницы, осмысленный коммит.

### 8.1. Автонарезка города на сетку (макс. охват по Яндексу/2ГИС)
Яндекс отдаёт ≤500 объектов на запрос. Нужно: по `region`/bounding box
разбивать территорию на сетку квадратов (`ll`+`spn`) и обходить ячейки,
объединяя и дедуплицируя результат.
- Где: `YandexMapsService` (+ опц. 2ГИС), новый параметр `grid: true` и размер
  ячейки.
- Готово, когда: по крупному городу собирается заметно >500 уникальных лидов.

### 8.2. Режим разработки фронта (hot reload)
Скрипт/`npm run`-команда: vite-dev на 3001 + бэкенд на 3000 с CORS (или
vite-proxy `/api` → 3000). Цель: править UI без пересборки.
- Файлы: `web/vite.config.ts` (proxy), возможно `cors` в `src/index.ts`
  (только для dev).

### 8.3. Обогащение лидов «без сайта»
Для лидов с `hasWebsite=false` дотягивать контакты (соцсети, e-mail, второй
телефон) из публичных источников/выдачи и сохранять в `Lead` (новые поля или
`rawData`).
- Готово, когда: на странице у таких лидов видны доп. контакты.

### 8.4. Модуль легального аутрича
Очередь персональных сообщений по собранным лидам через **официальные**
Telegram Bot API / VK API сообществ: шаблоны офферов с подстановкой
(`niche/region/«нет сайта»`), лимиты и паузы, статусы (`отправлено/ответил/
отказ`) в таблице. Без накрутки и спама.
- Новые: `entities/Outreach*.ts`, `services/OutreachService.ts`,
  `controllers/OutreachController.ts`, страница в `web/`.

### 8.5. Авторизация
Сейчас API открыт. Добавить простой вход (JWT уже в зависимостях,
`utils/encryption.ts` есть) и защиту `/api/*`.

### 8.6. Экспорт в Google Sheets
Использовать существующую интеграцию (`GoogleDriveService`, `googleapis`) для
выгрузки таблицы лидов в Google Таблицу (помимо CSV).

### 8.7. Тесты и CI
Добавить минимальные тесты для мапперов источников (вход = фикстура ответа API,
выход = `LeadResult`) и для дедупа. Прогон в GitHub Actions.

## 9. Сделанные фиксы (контекст, не повторять)

Проект изначально не собирался; уже исправлено: битые зависимости в
`package.json` (`anthropic`→`@anthropic-ai/sdk`, `jsonwebtoken` версия,
добавлены `@types`), настройки декораторов в `tsconfig.json`, пути entities в
`config/database.ts` (`__dirname`+`{ts,js}`), рабочий `Dockerfile`, корневой
`web/index.html` для Vite, ~30 строгих type-ошибок в старом коде. Эти места
трогать не нужно, если задача их не касается.
