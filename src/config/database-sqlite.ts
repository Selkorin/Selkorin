import { DataSource } from 'typeorm';
import { SocialAccount } from '../entities/SocialAccount';
import { ContentPlan } from '../entities/ContentPlan';
import { ContentItem } from '../entities/ContentItem';
import { SocialAgent } from '../entities/SocialAgent';
import { KnowledgeFile } from '../entities/KnowledgeFile';
import { PublishingHistory } from '../entities/PublishingHistory';
import { CompetitorAnalysis } from '../entities/CompetitorAnalysis';
import { Lead } from '../entities/Lead';

export const AppDataSourceSQLite = new DataSource({
  type: 'sqlite',
  database: process.env.DB_PATH || './data/wai.db',
  synchronize: process.env.NODE_ENV === 'development',
  logging: false,
  entities: [
    SocialAccount,
    ContentPlan,
    ContentItem,
    SocialAgent,
    KnowledgeFile,
    PublishingHistory,
    CompetitorAnalysis,
    Lead,
  ],
  migrations: [],
});
