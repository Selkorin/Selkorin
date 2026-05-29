import axios from 'axios';

// Относительный путь по умолчанию: фронт берёт API с того же origin,
// что и сам сайт (работает и локально, и на любом домене).
const API_URL = import.meta.env.VITE_API_URL || '/api';

const apiClient = axios.create({
  baseURL: API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Dashboard endpoints
export const dashboard = {
  getStats: () => apiClient.get('/dashboard/stats'),
  getActivity: () => apiClient.get('/dashboard/activity'),
  getCalendar: (month?: number, year?: number) =>
    apiClient.get('/dashboard/calendar', {
      params: { month, year },
    }),
  getAnalytics: (days: number = 7) =>
    apiClient.get('/dashboard/analytics', { params: { days } }),
};

// Content endpoints
export const content = {
  list: (status?: string, platform?: string, planId?: string, page = 1, limit = 20) =>
    apiClient.get('/content', {
      params: { status, platform, planId, page, limit },
    }),
  get: (id: string) => apiClient.get(`/content/${id}`),
  create: (data: any) => apiClient.post('/content', data),
  update: (id: string, data: any) => apiClient.put(`/content/${id}`, data),
  delete: (id: string) => apiClient.delete(`/content/${id}`),
};

// Social accounts endpoints
export const socialAccounts = {
  list: () => apiClient.get('/socials'),
  get: (id: string) => apiClient.get(`/socials/${id}`),
};

// Content plans endpoints
export const contentPlans = {
  list: () => apiClient.get('/plans'),
  get: (id: string) => apiClient.get(`/plans/${id}`),
  create: (data: any) => apiClient.post('/plans', data),
};

// Competitor analysis endpoints
export const competitorAnalysis = {
  analyze: (data: any) => apiClient.post('/analyze/competitor', data),
  get: (id: string) => apiClient.get(`/analysis/${id}`),
  sendToAgents: (id: string, agentIds: string[]) =>
    apiClient.post(`/analysis/${id}/send-to-agents`, { agentIds }),
};

// Lead generation (Yandex Maps parser) endpoints
export const leads = {
  search: (data: {
    niche: string;
    region?: string;
    noWebsiteOnly?: boolean;
    limit?: number;
    save?: boolean;
    source?: 'yandex' | '2gis' | '2gis_scraper' | 'vk' | 'telegram' | 'both';
    url?: string;
    usernames?: string;
  }) => apiClient.post('/leads/search', data),
  list: (params?: {
    niche?: string;
    region?: string;
    status?: string;
    hasWebsite?: boolean;
    search?: string;
    page?: number;
    limit?: number;
  }) => apiClient.get('/leads', { params }),
  stats: () => apiClient.get('/leads/stats'),
  update: (id: string, data: { status?: string; notes?: string }) =>
    apiClient.put(`/leads/${id}`, data),
  remove: (id: string) => apiClient.delete(`/leads/${id}`),
  exportCsvUrl: (params?: Record<string, any>) => {
    const qs = new URLSearchParams(params || {}).toString();
    return `${API_URL}/leads/export/csv${qs ? `?${qs}` : ''}`;
  },
};

// Health check
export const health = () => apiClient.get('/health');

export default apiClient;
