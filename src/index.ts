import express from 'express';
import dotenv from 'dotenv';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { AppDataSource } from './config/database';
import { WebhookController } from './controllers/WebhookController';
import { DemoController } from './controllers/DemoController';
import { AuthController } from './controllers/AuthController';
import { PublishingController } from './controllers/PublishingController';
import { ContentController } from './controllers/ContentController';
import { ImportController } from './controllers/ImportController';
import { CompetitorAnalysisController } from './controllers/CompetitorAnalysisController';
import { GoogleDriveController } from './controllers/GoogleDriveController';
import { DashboardController } from './controllers/DashboardController';
import { APIController } from './controllers/APIController';
import { LeadGenController } from './controllers/LeadGenController';
import { SchedulerService } from './services/SchedulerService';
import { SeedDataService } from './services/SeedDataService';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Multer setup for file uploads
const upload = multer({ storage: multer.memoryStorage() });

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Services
const schedulerService = new SchedulerService();

// Initialize database
AppDataSource.initialize()
  .then(async () => {
    console.log('✅ Database connection established');

    // Seed data if enabled and database is empty
    if (process.env.SEED_DATA_ENABLED === 'true') {
      const seedService = new SeedDataService();
      try {
        await seedService.seedAll();
      } catch (error: any) {
        console.log('⚠️ Seeding warning:', error.message);
      }
    }

    // Start scheduler
    schedulerService.start();
  })
  .catch(error => console.log('⚠️ Database initialization warning:', error.message));

// Controllers
const webhookController = new WebhookController();
const demoController = new DemoController();
const authController = new AuthController();
const publishingController = new PublishingController();
const contentController = new ContentController();
const importController = new ImportController();
const competitorController = new CompetitorAnalysisController();
const googleDriveController = new GoogleDriveController();
const dashboardController = new DashboardController();
const apiController = new APIController();
const leadGenController = new LeadGenController();

// Health & Demo
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'WAI Social Agent', version: '0.1.0' });
});

app.get('/demo', (req, res) => demoController.getDashboard(req, res));
app.get('/', (req, res, next) => {
  // Если собран React-интерфейс — отдаём его (через express.static ниже),
  // иначе показываем демо-дашборд.
  if (fs.existsSync(path.join(__dirname, '../web/dist/index.html'))) {
    return next();
  }
  res.redirect('/demo');
});

// Webhook
app.post('/webhook/task', (req, res) => webhookController.handleTask(req, res));
app.get('/webhook/status', (req, res) => webhookController.getStatus(req, res));

// OAuth Authentication Routes
app.get('/auth/instagram/url', (req, res) => authController.getInstagramOAuthUrl(req, res));
app.get('/auth/instagram/callback', (req, res) => authController.instagramCallback(req, res));

app.get('/auth/vk/url', (req, res) => authController.getVkOAuthUrl(req, res));
app.get('/auth/vk/callback', (req, res) => authController.vkCallback(req, res));

app.post('/auth/telegram/connect', (req, res) => authController.telegramConnect(req, res));

// Publishing Routes
app.post('/publish/:contentItemId', (req, res) =>
  publishingController.publishNow(req, res)
);

app.post('/content/:contentItemId/approve', (req, res) =>
  publishingController.approveContent(req, res)
);

app.post('/content/:contentItemId/schedule', (req, res) =>
  publishingController.scheduleContent(req, res)
);

app.get('/content/:contentItemId/status', (req, res) =>
  publishingController.getContentStatus(req, res)
);

// Content Generation Routes
app.post('/content/generate/plan', (req, res) =>
  contentController.generateForPlan(req, res)
);

app.post('/content/generate/single', (req, res) =>
  contentController.generateSingle(req, res)
);

app.post('/content/:contentItemId/regenerate', (req, res) =>
  contentController.regenerate(req, res)
);

// Calendar & Analytics Routes
app.get('/calendar', (req, res) =>
  contentController.getCalendar(req, res)
);

app.get('/history', (req, res) =>
  contentController.getHistory(req, res)
);

app.get('/analytics', (req, res) =>
  contentController.getAnalytics(req, res)
);

app.get('/scheduled', (req, res) =>
  contentController.getScheduled(req, res)
);

// Import/Export Routes
app.post('/import/:contentPlanId/csv', upload.single('file'), (req, res) =>
  importController.importCSV(req, res)
);

app.post('/import/:contentPlanId/json', upload.single('file'), (req, res) =>
  importController.importJSON(req, res)
);

app.post('/schedules/bulk-update', (req, res) =>
  importController.updateSchedules(req, res)
);

app.get('/export/:contentPlanId/csv', (req, res) =>
  importController.exportCSV(req, res)
);

app.get('/export/:contentPlanId/json', (req, res) =>
  importController.exportJSON(req, res)
);

app.get('/import/template/csv', (req, res) =>
  importController.getCSVTemplate(req, res)
);

app.get('/import/template/json', (req, res) =>
  importController.getJSONTemplate(req, res)
);

// Competitor Analysis Routes
app.post('/analyze/competitor', (req, res) =>
  competitorController.analyzeCompetitor(req, res)
);

app.get('/analysis/:analysisId', (req, res) =>
  competitorController.getAnalysis(req, res)
);

app.get('/analyses', (req, res) =>
  competitorController.getAnalysesByProject(req, res)
);

app.post('/analysis/:analysisId/send-to-agents', (req, res) =>
  competitorController.sendRecommendationsToAgents(req, res)
);

// Google Drive Integration Routes
app.get('/auth/google/url', (req, res) =>
  googleDriveController.getGoogleDriveAuthUrl(req, res)
);

app.get('/auth/google/callback', (req, res) =>
  googleDriveController.googleDriveCallback(req, res)
);

app.post('/drive/upload', (req, res) =>
  googleDriveController.uploadToGoogleDrive(req, res)
);

app.post('/drive/download', (req, res) =>
  googleDriveController.downloadFromGoogleDrive(req, res)
);

app.post('/drive/sync-plan', (req, res) =>
  googleDriveController.syncContentPlan(req, res)
);

app.get('/drive/files', (req, res) =>
  googleDriveController.listGoogleDriveFiles(req, res)
);

app.post('/drive/delete', (req, res) =>
  googleDriveController.deleteFromGoogleDrive(req, res)
);

app.post('/drive/share', (req, res) =>
  googleDriveController.shareWithUser(req, res)
);

// REST API Endpoints (for Frontend)
app.get('/api/health', (req, res) => apiController.health(req, res));

// Dashboard endpoints
app.get('/api/dashboard/stats', (req, res) =>
  dashboardController.getStats(req, res)
);

app.get('/api/dashboard/activity', (req, res) =>
  dashboardController.getRecentActivity(req, res)
);

app.get('/api/dashboard/calendar', (req, res) =>
  dashboardController.getCalendar(req, res)
);

app.get('/api/dashboard/analytics', (req, res) =>
  dashboardController.getAnalytics(req, res)
);

// Content API
app.get('/api/content', (req, res) => apiController.listContent(req, res));
app.post('/api/content', (req, res) => apiController.createContent(req, res));
app.get('/api/content/:id', (req, res) => apiController.getContent(req, res));
app.put('/api/content/:id', (req, res) =>
  apiController.updateContent(req, res)
);
app.delete('/api/content/:id', (req, res) =>
  apiController.deleteContent(req, res)
);

// Social Accounts API
app.get('/api/socials', (req, res) =>
  apiController.listSocialAccounts(req, res)
);
app.get('/api/socials/:id', (req, res) =>
  apiController.getSocialAccount(req, res)
);

// Content Plans API
app.get('/api/plans', (req, res) => apiController.listContentPlans(req, res));
app.post('/api/plans', (req, res) =>
  apiController.createContentPlan(req, res)
);
app.get('/api/plans/:id', (req, res) =>
  apiController.getContentPlan(req, res)
);

// Lead Generation API (Yandex Maps parser)
app.post('/api/leads/search', (req, res) =>
  leadGenController.search(req, res)
);
app.get('/api/leads/stats', (req, res) =>
  leadGenController.stats(req, res)
);
app.get('/api/leads/export/csv', (req, res) =>
  leadGenController.exportCsv(req, res)
);
app.get('/api/leads', (req, res) => leadGenController.list(req, res));
app.put('/api/leads/:id', (req, res) => leadGenController.update(req, res));
app.delete('/api/leads/:id', (req, res) =>
  leadGenController.remove(req, res)
);

// Serve the built React frontend (web/dist) from the same origin, if present.
// Then the full UI (including the "Лиды" page) is available at the API origin.
const webDist = path.join(__dirname, '../web/dist');
if (fs.existsSync(path.join(webDist, 'index.html'))) {
  app.use(express.static(webDist));

  // SPA fallback for client-side routes (skip API/service prefixes)
  const apiPrefixes = [
    '/api', '/auth', '/webhook', '/publish', '/content', '/calendar',
    '/history', '/analytics', '/scheduled', '/import', '/export',
    '/schedules', '/analyze', '/analysis', '/analyses', '/drive',
    '/health', '/demo',
  ];
  app.get('*', (req, res, next) => {
    if (apiPrefixes.some(p => req.path === p || req.path.startsWith(p + '/'))) {
      return next();
    }
    res.sendFile(path.join(webDist, 'index.html'));
  });
  console.log('🖥️  Serving React UI from web/dist');
} else {
  console.log('ℹ️  web/dist not found — UI not bundled (run the local script to build it)');
}

app.listen(PORT, () => {
  console.log(`\n✅ WAI Social Agent running on port ${PORT}\n`);
  console.log(`🌐 Dashboard: http://localhost:${PORT}/demo`);
  console.log(`💚 Health check: http://localhost:${PORT}/health`);
  console.log(`🔗 Webhook endpoint: http://localhost:${PORT}/webhook/task`);

  console.log(`\n🔐 OAuth Endpoints:`);
  console.log(`   Instagram: GET /auth/instagram/url`);
  console.log(`   VK: GET /auth/vk/url`);
  console.log(`   Telegram: POST /auth/telegram/connect`);

  console.log(`\n📤 Publishing Endpoints:`);
  console.log(`   Publish: POST /publish/:contentItemId`);
  console.log(`   Approve: POST /content/:contentItemId/approve`);
  console.log(`   Schedule: POST /content/:contentItemId/schedule`);
  console.log(`   Status: GET /content/:contentItemId/status`);

  console.log(`\n🤖 Content Generation Endpoints:`);
  console.log(`   Generate Plan: POST /content/generate/plan`);
  console.log(`   Generate Single: POST /content/generate/single`);
  console.log(`   Regenerate: POST /content/:contentItemId/regenerate`);

  console.log(`\n📅 Calendar & Analytics Endpoints:`);
  console.log(`   Calendar: GET /calendar?socialAccountId=uuid&month=2024-12`);
  console.log(`   History: GET /history?socialAccountId=uuid&limit=50`);
  console.log(`   Analytics: GET /analytics?days=7&socialAccountId=uuid`);
  console.log(`   Scheduled: GET /scheduled`);

  console.log(`\n⏱️ Scheduler: Auto-publishes content at scheduled times (every minute)`);

  console.log(`\n📥 Import/Export Endpoints:`);
  console.log(`   Import CSV: POST /import/:contentPlanId/csv (with file)`);
  console.log(`   Import JSON: POST /import/:contentPlanId/json (with file)`);
  console.log(`   Export CSV: GET /export/:contentPlanId/csv`);
  console.log(`   Export JSON: GET /export/:contentPlanId/json`);
  console.log(`   CSV Template: GET /import/template/csv`);
  console.log(`   JSON Template: GET /import/template/json`);
  console.log(`   Bulk Update Schedules: POST /schedules/bulk-update\n`);

  console.log(`\n🔍 Competitor Analysis Endpoints:`);
  console.log(`   Analyze Competitor: POST /analyze/competitor`);
  console.log(`   Get Analysis: GET /analysis/:analysisId`);
  console.log(`   List Analyses: GET /analyses?projectId=uuid`);
  console.log(`   Send to Agents: POST /analysis/:analysisId/send-to-agents`);

  console.log(`\n☁️ Google Drive Integration Endpoints:`);
  console.log(`   Auth URL: GET /auth/google/url`);
  console.log(`   Auth Callback: GET /auth/google/callback?code=...`);
  console.log(`   Upload Content: POST /drive/upload`);
  console.log(`   Download Content: POST /drive/download`);
  console.log(`   Sync Plan: POST /drive/sync-plan`);
  console.log(`   List Files: GET /drive/files?accessToken=...`);
  console.log(`   Delete Content: POST /drive/delete`);
  console.log(`   Share Content: POST /drive/share`);

  console.log(`\n🔌 REST API Endpoints (for Frontend):`);
  console.log(`   Health: GET /api/health`);
  console.log(`   Dashboard Stats: GET /api/dashboard/stats`);
  console.log(`   Dashboard Activity: GET /api/dashboard/activity`);
  console.log(`   Dashboard Calendar: GET /api/dashboard/calendar`);
  console.log(`   Dashboard Analytics: GET /api/dashboard/analytics`);
  console.log(`   Content List: GET /api/content`);
  console.log(`   Content CRUD: POST|GET|PUT|DELETE /api/content/:id`);
  console.log(`   Social Accounts: GET /api/socials`);
  console.log(`   Content Plans: GET|POST /api/plans\n`);

  console.log(`\n🎯 Lead Generation Endpoints (Yandex Maps):`);
  console.log(`   Search Leads: POST /api/leads/search`);
  console.log(`   List Leads: GET /api/leads?niche=...&hasWebsite=false`);
  console.log(`   Lead Stats: GET /api/leads/stats`);
  console.log(`   Export CSV: GET /api/leads/export/csv`);
  console.log(`   Update Lead: PUT /api/leads/:id`);
  console.log(`   Delete Lead: DELETE /api/leads/:id\n`);
});
