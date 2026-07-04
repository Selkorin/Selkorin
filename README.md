# 🎯 Selkorin Lead Engine

> **Основной продукт этой ветки — приложение для лидогенерации, парсинга и рассылок.**
> Опишите словами, кого искать («Найди мне клиентов, кому нужен сайт»), и движок
> соберёт свежие заявки из Telegram-чатов, Яндекс-поиска и Яндекс.Карт (бизнесы
> без сайта), оценит каждый лид и предложит первое сообщение. Плюс модуль
> Telegram-рассылок: массовые сообщения, реакции, лайки, кружки, просмотры.
>
> 👉 **Код и инструкция:** [`leadgen/`](./leadgen/) · запуск: `cd leadgen && ./run.sh` → http://localhost:8000
>
> Стек: Python + FastAPI + Telethon + Claude + SQLite, фронтенд — SPA без сборки.
> Работает «из коробки» в demo-режиме без ключей.

---

<sub>Ниже — документация к прежнему проекту репозитория (AI SMM система на Node/TS), оставлена для истории.</sub>

# 🧠 WAI Social Brain - Complete AI SMM System

**AI-powered Social Media Management System** with intelligent content creation, scheduling, analytics, and competitor analysis.

![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![Node](https://img.shields.io/badge/node-20.x-green.svg)
![License](https://img.shields.io/badge/license-MIT-orange.svg)

---

## ✨ Key Features

### 📝 Content Management
- ✅ Create, edit, schedule, and publish posts across multiple platforms
- ✅ Rich content editor with image/video support
- ✅ Content calendar with month view
- ✅ Draft and approval workflows
- ✅ Bulk import from CSV/JSON with date-based scheduling

### 🤖 AI-Powered Generation
- ✅ Claude AI for intelligent content creation
- ✅ Support for multiple AI providers (OpenAI, Gemini)
- ✅ Brand-aware content generation
- ✅ Tone and style customization
- ✅ Image prompt generation

### 📊 Analytics & Insights
- ✅ Real-time dashboard with engagement metrics
- ✅ Performance tracking by platform
- ✅ Content performance analytics
- ✅ Engagement trends and patterns
- ✅ Comparative insights

### 👁️ Competitor Analysis
- ✅ Analyze competitor accounts and strategies
- ✅ Extract metrics and engagement patterns
- ✅ AI-powered competitive recommendations
- ✅ Content strategy insights
- ✅ Send recommendations to your AI agents

### 🌐 Multi-Platform Support
- ✅ Instagram (posts, reels, stories, carousels)
- ✅ Telegram (text, images, videos)
- ✅ VK (posts, stories)
- ✅ YouTube (videos)
- ✅ TikTok (short videos)
- ✅ Extensible architecture for new platforms

### ☁️ Google Drive Integration
- ✅ Store content in Google Drive
- ✅ Sync entire content plans
- ✅ Share content with team members
- ✅ Backup and version control

### ⚡ Automation
- ✅ Auto-publish at scheduled times
- ✅ Recurring content schedules
- ✅ Webhook integration with external systems
- ✅ Smart scheduler with timezone support

---

## 🚀 Quick Start

### Prerequisites
- Node.js 20.x or higher
- npm or pnpm
- Docker & Docker Compose (optional, but recommended)

### Option 1: Docker Compose (Recommended - 5 minutes)

```bash
# Clone and enter directory
git clone <repo> && cd Selkorin

# Start everything
docker-compose up

# Wait for "Database initialized" message
# Open browser: http://localhost:3001
```

### Option 2: Local Development

```bash
# Install dependencies
npm install

# Create .env file
cp .env.development .env.local

# Initialize database with demo data
npm run seed

# Terminal 1: Start backend
npm run dev

# Terminal 2: Start frontend
cd web && npm install && npm run dev
```

Then open:
- 🔗 Backend: http://localhost:3000
- 🎨 Frontend: http://localhost:3001

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| [SETUP.md](./SETUP.md) | Installation and configuration |
| [DEVELOPMENT.md](./DEVELOPMENT.md) | Architecture and development guide |
| [API.md](./API.md) | Complete API reference |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Production deployment |
| [GOOGLE_DRIVE.md](./GOOGLE_DRIVE.md) | Google Drive integration |
| [BULK_SCHEDULING.md](./BULK_SCHEDULING.md) | Bulk upload and scheduling |

---

## 🏗️ Architecture

```
WAI Social Brain
│
├─ Frontend (React + Tailwind CSS)
│  ├─ Dashboard (stats, calendar, activity)
│  ├─ Content Management (CRUD, filtering)
│  ├─ Competitor Analysis (metrics, reports)
│  ├─ Analytics (trends, performance)
│  └─ Settings (accounts, preferences)
│
├─ Backend (Express + TypeORM)
│  ├─ REST API (/api/*)
│  ├─ Services (Business logic)
│  ├─ Controllers (Request handling)
│  ├─ Entities (Database models)
│  ├─ Adapters (Platform integrations)
│  └─ Scheduler (Auto-publishing)
│
└─ Database (SQLite / PostgreSQL)
   ├─ Content items
   ├─ Social accounts
   ├─ Schedules
   ├─ Analytics
   └─ Competitor data
```

---

## 💻 Tech Stack

### Frontend
- **React 18** - UI library
- **Tailwind CSS** - Styling
- **React Router** - Navigation
- **Axios** - HTTP client
- **Vite** - Build tool

### Backend
- **Express** - Web framework
- **TypeORM** - ORM
- **TypeScript** - Type safety
- **SQLite/PostgreSQL** - Database
- **Anthropic SDK** - Claude API

### DevOps
- **Docker** - Containerization
- **Docker Compose** - Local development

---

## 📊 Demo Data

System comes with pre-loaded demo data:

✅ **3 Social Accounts** (Instagram, Telegram, TikTok)
✅ **2 Content Plans** (Current week + Next week)
✅ **7 Sample Posts** (Various statuses)
✅ **2 AI Agents** (Content generators)
✅ **1 Competitor Analysis** (With full report)

Reset demo data anytime:
```bash
npm run seed:reset
```

---

## 🔌 API Endpoints

### Dashboard
```
GET /api/dashboard/stats         Stats and KPIs
GET /api/dashboard/activity      Recent activity
GET /api/dashboard/calendar      Content calendar
GET /api/dashboard/analytics     Analytics data
```

### Content CRUD
```
GET    /api/content              List posts
POST   /api/content              Create post
GET    /api/content/:id          Get post
PUT    /api/content/:id          Update post
DELETE /api/content/:id          Delete post
```

### Social Accounts
```
GET /api/socials                 List accounts
POST /api/socials                Connect account
GET /api/socials/:id             Get account
```

### Competitor Analysis
```
POST /analyze/competitor         Start analysis
GET  /analysis/:id               Get analysis
POST /analysis/:id/send-to-agents Send to agents
```

### Google Drive
```
GET  /auth/google/url            Get auth URL
POST /drive/upload               Upload to Drive
POST /drive/sync-plan            Sync entire plan
GET  /drive/files                List Drive files
```

Full API docs: [API.md](./API.md)

---

## 🛠️ Configuration

### Environment Variables

```env
# Database
USE_SQLITE=true
DB_PATH=./data/wai.db

# API Keys
ANTHROPIC_API_KEY=sk-ant-your-key
OPENAI_API_KEY=sk-your-key

# Google Drive
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-secret

# JWT
JWT_SECRET=your-secret-key

# Features
SEED_DATA_ENABLED=true
```

Detailed config: [SETUP.md](./SETUP.md)

---

## 🚀 Deployment

### Quick Deploy to Railway

```bash
# 1. Push to GitHub
git push origin main

# 2. Connect to Railway
# - Go to railway.app
# - Create new project
# - Connect GitHub repo
# - Add environment variables
# - Deploy!
```

### Self-Hosted (Docker)

```bash
docker build -t wai-social-brain .
docker run -p 3000:3000 -e NODE_ENV=production wai-social-brain
```

Full deployment guide: [DEPLOYMENT.md](./DEPLOYMENT.md)

---

## 📦 Project Structure

```
Selkorin/
├── src/                    Backend (Node.js)
│   ├── config/            Configuration
│   ├── controllers/       HTTP handlers
│   ├── services/          Business logic
│   ├── entities/          Database models
│   ├── adapters/          Platform integrations
│   ├── scripts/           CLI tools
│   └── index.ts          Entry point
│
├── web/                    Frontend (React)
│   ├── src/
│   │   ├── pages/        Pages
│   │   ├── components/   React components
│   │   ├── services/     API client
│   │   └── App.tsx       Router
│   └── public/           Static files
│
├── data/                   Database (SQLite)
├── docker-compose.yml      Local development
├── SETUP.md               Setup guide
├── DEVELOPMENT.md         Dev guide
├── API.md                 API reference
└── README.md             This file
```

---

## 🎯 Next Steps

After setup:

1. **Connect your social accounts** → Settings → Add Account
2. **Create a content plan** → Dashboard → New Plan
3. **Add some posts** → Content Management → Create Post
4. **Schedule for publishing** → Approve and schedule
5. **Watch analytics** → Analytics dashboard
6. **Analyze competitors** → Competitor Analysis

---

## 🔑 Key Endpoints for Integration

### For External Systems

```
POST /webhook/task           Receive tasks from WAI admin
GET  /webhook/status         Check task status
GET  /health                 Health check
```

### For Frontend

```
GET  /api/health             Backend status
GET  /api/dashboard/*        All dashboard data
GET  /api/content            List/search posts
POST /api/content            Create post
GET  /api/socials            Connected accounts
GET  /api/plans              Content plans
```

---

## 🤝 Contributing

Contributions welcome! See [DEVELOPMENT.md](./DEVELOPMENT.md) for:
- Architecture overview
- How to add new features
- Code style guidelines
- Testing procedures

---

## 📝 License

MIT License - see LICENSE file for details

---

## 💬 Support

- 📖 Documentation: See `*.md` files
- 🐛 Issues: GitHub Issues
- 💡 Discussions: GitHub Discussions
- 📧 Email: Contact maintainers

---

## ✅ Checklist for First Use

- [ ] Clone repository
- [ ] Install dependencies (`npm install`)
- [ ] Run `npm run seed` to initialize database
- [ ] Start backend (`npm run dev`)
- [ ] Start frontend (`cd web && npm run dev`)
- [ ] Open http://localhost:3001
- [ ] Explore demo data
- [ ] Connect your first social account
- [ ] Create a test post

---

## 🎉 Ready to Go!

Your complete AI-powered SMM system is ready. Start creating amazing content! 🚀

**Next:** Read [SETUP.md](./SETUP.md) for detailed configuration options.
