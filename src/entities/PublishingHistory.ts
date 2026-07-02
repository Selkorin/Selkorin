import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn } from 'typeorm';

@Entity('publishing_history')
export class PublishingHistory {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  contentItemId: string;

  @Column()
  socialAccountId: string;

  @Column()
  platform: 'instagram' | 'telegram' | 'vk' | 'youtube' | 'tiktok';

  @Column()
  platformPostId: string;

  @Column()
  postUrl: string;

  @Column()
  status: 'success' | 'failed';

  @Column({ nullable: true })
  errorMessage: string;

  @Column({ type: 'json', nullable: true })
  metrics: {
    likes?: number;
    comments?: number;
    shares?: number;
    views?: number;
    reach?: number;
    saves?: number;
    impressions?: number;
    engagementRate?: number;
  };

  @Column({ type: 'json' })
  contentSnapshot: {
    title: string;
    caption: string;
    hashtags: string[];
    imageUrl?: string;
    videoUrl?: string;
  };

  @CreateDateColumn()
  publishedAt: Date;

  @Column({ nullable: true })
  metricsUpdatedAt: Date;
}
