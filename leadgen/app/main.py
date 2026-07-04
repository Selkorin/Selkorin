"""
Точка входа FastAPI: инициализация БД, загрузка настроек, планировщик,
подключение роутеров и раздача фронтенда (SPA).
"""
from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from . import db, seed
from .config import settings
from .routers import campaigns, leads, monitors, search, system, telegram
from .services import monitoring

WEB_DIR = Path(__file__).resolve().parent.parent / "web"

app = FastAPI(title="Selkorin Lead Engine", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _load_persisted_settings() -> None:
    """Настройки, сохранённые через UI, имеют приоритет над .env."""
    for key in (
        "anthropic_api_key",
        "anthropic_model",
        "yandex_search_api_key",
        "yandex_maps_api_key",
        "mode",
    ):
        val = db.get_setting(key, "")
        if val:
            setattr(settings, key, val)


@app.on_event("startup")
def startup() -> None:
    db.init_db()
    _load_persisted_settings()
    seed.seed_if_empty()
    monitoring.start_scheduler()
    print(f"\n✅ Selkorin Lead Engine — режим: {settings.mode}, AI: {'вкл' if settings.ai_enabled else 'выкл (эвристика)'}")
    print(f"🌐 Интерфейс: http://localhost:{settings.port}\n")


# API-роутеры
app.include_router(system.router)
app.include_router(search.router)
app.include_router(leads.router)
app.include_router(monitors.router)
app.include_router(telegram.router)
app.include_router(campaigns.router)


# Статика фронтенда
if (WEB_DIR / "assets").exists():
    app.mount("/assets", StaticFiles(directory=WEB_DIR / "assets"), name="assets")


@app.get("/")
def index():
    return FileResponse(WEB_DIR / "index.html")


@app.get("/{path:path}")
def spa(path: str):
    """SPA-фолбэк: любые не-API пути отдают index.html (или файл, если существует)."""
    candidate = WEB_DIR / path
    if candidate.is_file():
        return FileResponse(candidate)
    return FileResponse(WEB_DIR / "index.html")
