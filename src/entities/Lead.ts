import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

/**
 * Lead — компания, собранная для лид-генерации (например, через Yandex Places API).
 * Источник по умолчанию — поиск по организациям Яндекс.Карт.
 */
@Entity('leads')
@Index(['niche', 'region'])
export class Lead {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Название компании
  @Column()
  name: string;

  // Основная категория/рубрика (например, "Кофейня")
  @Column({ nullable: true })
  category: string;

  // Все рубрики через запятую
  @Column({ nullable: true })
  categories: string;

  @Column({ nullable: true })
  address: string;

  @Column({ nullable: true })
  phone: string;

  // Сайт компании. Пусто => "у кого нет сайта"
  @Column({ nullable: true })
  website: string;

  // Удобный флаг для фильтрации "нет сайта"
  @Column({ default: false })
  hasWebsite: boolean;

  @Column({ type: 'float', nullable: true })
  latitude: number;

  @Column({ type: 'float', nullable: true })
  longitude: number;

  // Ссылка на карточку организации в Яндексе
  @Column({ nullable: true })
  yandexUrl: string;

  // Часы работы (как отдаёт API, текстом)
  @Column({ type: 'text', nullable: true })
  hours: string;

  // Поисковый запрос (ниша), по которому найден лид
  @Column({ nullable: true })
  niche: string;

  // Регион/город поиска
  @Column({ nullable: true })
  region: string;

  // Источник данных
  @Column({ default: 'yandex_maps' })
  source: string;

  // Воронка работы с лидом
  @Column({ default: 'new' })
  status: 'new' | 'contacted' | 'qualified' | 'rejected' | 'client';

  @Column({ type: 'text', nullable: true })
  notes: string;

  // Сырой ответ API на случай, если понадобятся доп. поля
  @Column({ type: 'simple-json', nullable: true })
  rawData: any;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
