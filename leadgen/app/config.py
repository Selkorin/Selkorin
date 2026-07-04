"""Конфигурация приложения. Все значения читаются из окружения (.env)."""
from __future__ import annotations

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.getenv("LEADGEN_DATA_DIR", BASE_DIR / "data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

# Каталог для медиа (кружки/видео/картинки для рассылок)
MEDIA_DIR = DATA_DIR / "media"
MEDIA_DIR.mkdir(parents=True, exist_ok=True)

# Каталог для файлов Telethon-сессий
SESSIONS_DIR = DATA_DIR / "sessions"
SESSIONS_DIR.mkdir(parents=True, exist_ok=True)

DB_PATH = str(DATA_DIR / "leadgen.db")


class Settings:
    """Настройки окружения. Меняются через .env либо в разделе «Настройки» в UI."""

    # AI (классификация лидов и генерация сообщений)
    anthropic_api_key: str = os.getenv("ANTHROPIC_API_KEY", "")
    anthropic_model: str = os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5")

    # Yandex-поиск (опционально: официальный Yandex Search API или SerpAPI-совместимый)
    yandex_search_api_key: str = os.getenv("YANDEX_SEARCH_API_KEY", "")
    yandex_maps_api_key: str = os.getenv("YANDEX_MAPS_API_KEY", "")

    # Режим. demo — работает без ключей на сэмпл-данных. live — реальные источники.
    mode: str = os.getenv("LEADGEN_MODE", "demo")

    # Безопасные лимиты для Telegram-автоматизации (защита аккаунта от блокировки).
    tg_min_delay_sec: float = float(os.getenv("TG_MIN_DELAY_SEC", "8"))
    tg_max_delay_sec: float = float(os.getenv("TG_MAX_DELAY_SEC", "22"))
    tg_daily_message_limit: int = int(os.getenv("TG_DAILY_MESSAGE_LIMIT", "40"))
    tg_daily_reaction_limit: int = int(os.getenv("TG_DAILY_REACTION_LIMIT", "120"))

    host: str = os.getenv("HOST", "0.0.0.0")
    port: int = int(os.getenv("PORT", "8000"))

    @property
    def ai_enabled(self) -> bool:
        return bool(self.anthropic_api_key)

    @property
    def is_live(self) -> bool:
        return self.mode.lower() == "live"


settings = Settings()
