import { Entity, PrimaryColumn, Column, UpdateDateColumn } from 'typeorm';

/**
 * Simple key/value store for application settings and secrets.
 * Secret values (API keys, tokens) are stored encrypted; see APIController.
 */
@Entity('app_settings')
export class AppSetting {
  @PrimaryColumn()
  key: string;

  @Column({ type: 'text', nullable: true })
  value: string;

  @Column({ default: false })
  isSecret: boolean;

  @UpdateDateColumn()
  updatedAt: Date;
}
