import axios from 'axios';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000/api';

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
  create: (data: { platform: string; accountName: string; token?: string }) =>
    apiClient.post('/socials', data),
  disconnect: (id: string) => apiClient.delete(`/socials/${id}`),
};

// Settings endpoints (preferences + API keys / permissions)
export const settings = {
  get: () => apiClient.get('/settings'),
  update: (data: { settings?: Record<string, any>; secrets?: Record<string, string> }) =>
    apiClient.put('/settings', data),
};

// Leads & Research (parser)
export const leads = {
  providers: () => apiClient.get('/leads/providers'),
  search: (data: {
    query: string;
    location?: string;
    count?: number;
    provider?: 'google' | 'yandex' | 'auto';
  }) => apiClient.post('/leads/search', data),
  deepResearch: (data: {
    topic: string;
    profession?: string;
    depth?: 'overview' | 'graduate' | 'phd';
  }) => apiClient.post('/research/deep', data),
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

// Health check
export const health = () => apiClient.get('/health');

export default apiClient;
