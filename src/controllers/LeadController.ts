import { Request, Response } from 'express';
import { LeadResearchService } from '../services/LeadResearchService';

export class LeadController {
  private service = new LeadResearchService();

  async getProviders(req: Request, res: Response) {
    try {
      const providers = await this.service.availableProviders();
      res.json({ success: true, providers });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async searchLeads(req: Request, res: Response) {
    try {
      const { query, location, count, provider } = req.body || {};
      if (!query || String(query).trim().length === 0) {
        return res.status(400).json({ error: 'Missing required field: query' });
      }

      const result = await this.service.findLeads({ query, location, count, provider });
      res.json({ success: true, ...result });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  async deepResearch(req: Request, res: Response) {
    try {
      const { topic, profession, depth } = req.body || {};
      if (!topic || String(topic).trim().length === 0) {
        return res.status(400).json({ error: 'Missing required field: topic' });
      }

      const result = await this.service.deepResearch({ topic, profession, depth });
      res.json({ success: true, research: result });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }
}
