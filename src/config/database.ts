import { DataSource } from 'typeorm';
import dotenv from 'dotenv';

dotenv.config();

const useSQLite = process.env.USE_SQLITE === 'true';

let AppDataSourceConfig: any;

if (useSQLite) {
  AppDataSourceConfig = {
    type: 'sqlite',
    database: process.env.DB_PATH || './data/wai.db',
    synchronize: process.env.NODE_ENV !== 'production',
    logging: process.env.NODE_ENV === 'development',
    entities: [__dirname + '/../entities/**/*.{ts,js}'],
    migrations: [__dirname + '/../migrations/**/*.{ts,js}'],
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
    entities: [__dirname + '/../entities/**/*.{ts,js}'],
    migrations: [__dirname + '/../migrations/**/*.{ts,js}'],
  };
}

export const AppDataSource = new DataSource(AppDataSourceConfig);
