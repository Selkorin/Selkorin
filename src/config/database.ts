import { DataSource } from 'typeorm';
import dotenv from 'dotenv';
import { SocialAccount } from '../entities/SocialAccount';
import { ContentPlan } from '../entities/ContentPlan';
import { ContentItem } from '../entities/ContentItem';
import { SocialAgent } from '../entities/SocialAgent';
import { KnowledgeFile } from '../entities/KnowledgeFile';
import { PublishingHistory } from '../entities/PublishingHistory';
import { CompetitorAnalysis } from '../entities/CompetitorAnalysis';
import { AppSetting } from '../entities/AppSetting';

dotenv.config();

const useSQLite = process.env.USE_SQLITE === 'true';

// Import entity classes directly so registration works under both ts-node (dev)
// and compiled output (node dist/index.js). A glob of "src/entities/**/*.ts"
// breaks in production because the compiled runtime cannot parse .ts files.
const entities = [
  SocialAccount,
  ContentPlan,
  ContentItem,
  SocialAgent,
  KnowledgeFile,
  PublishingHistory,
  CompetitorAnalysis,
  AppSetting,
];

let AppDataSourceConfig: any;

if (useSQLite) {
  AppDataSourceConfig = {
    type: 'sqlite',
    database: process.env.DB_PATH || './data/wai.db',
    synchronize: process.env.NODE_ENV !== 'production',
    logging: process.env.NODE_ENV === 'development',
    entities,
    migrations: [],
  };
} else {
  AppDataSourceConfig = {
    type: 'postgres',
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    username: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'postgres',
    database: process.env.DB_NAME || 'wai_social_agent',
    synchronize: process.env.NODE_ENV !== 'production',
    logging: process.env.NODE_ENV === 'development',
    entities,
    migrations: [],
  };
}

export const AppDataSource = new DataSource(AppDataSourceConfig);
