"""Системные эндпоинты: здоровье, статистика, лента событий, настройки, промты."""
from __future__ import annotations

from fastapi import APIRouter

from .. import db, prompts
from ..config import settings
from ..schemas import SettingsRequest

router = APIRouter(prefix="/api", tags=["system"])


@router.get("/health")
def health():
    return {
        "status": "ok",
        "service": "Selkorin Lead Engine",
        "mode": settings.mode,
        "ai_enabled": settings.ai_enabled,
    }


@router.get("/stats")
def stats():
    total = db.count("leads")
    hot = db.count("leads", "intent='hot'")
    new = db.count("leads", "status='new'")
    contacted = db.count("leads", "status='contacted'")
    won = db.count("leads", "status='won'")
    by_source = {
        row["source"]: row["c"]
        for row in db.query("SELECT source, COUNT(*) c FROM leads GROUP BY source")
    }
    return {
        "leads_total": total,
        "leads_hot": hot,
        "leads_new": new,
        "leads_contacted": contacted,
        "leads_won": won,
        "monitors": db.count("monitors"),
        "monitors_active": db.count("monitors", "enabled=1 AND schedule_minutes>0"),
        "accounts": db.count("telegram_accounts"),
        "accounts_connected": db.count("telegram_accounts", "status='connected'"),
        "campaigns": db.count("campaigns"),
        "by_source": by_source,
        "mode": settings.mode,
        "ai_enabled": settings.ai_enabled,
    }


@router.get("/events")
def events(limit: int = 40):
    return db.query("SELECT * FROM events ORDER BY created_at DESC LIMIT ?", (limit,))


@router.get("/prompts")
def get_prompts():
    """Отдаём тексты промтов «мозга» — их видно и можно изучить в интерфейсе."""
    return {
        "search_plan": prompts.SEARCH_PLAN_PROMPT,
        "lead_classifier": prompts.LEAD_CLASSIFIER_PROMPT,
        "outreach": prompts.OUTREACH_PROMPT,
        "default_brief": prompts.DEFAULT_MONITORING_BRIEF,
    }


@router.get("/settings")
def get_settings():
    def mask(v: str) -> str:
        return (v[:4] + "•••" + v[-2:]) if v and len(v) > 8 else ("••••" if v else "")

    return {
        "mode": settings.mode,
        "anthropic_model": settings.anthropic_model,
        "anthropic_api_key_set": bool(settings.anthropic_api_key),
        "anthropic_api_key_masked": mask(settings.anthropic_api_key),
        "yandex_search_api_key_set": bool(settings.yandex_search_api_key),
        "yandex_maps_api_key_set": bool(settings.yandex_maps_api_key),
        "tg_min_delay_sec": settings.tg_min_delay_sec,
        "tg_max_delay_sec": settings.tg_max_delay_sec,
        "tg_daily_message_limit": settings.tg_daily_message_limit,
        "tg_daily_reaction_limit": settings.tg_daily_reaction_limit,
    }


@router.post("/settings")
def update_settings(req: SettingsRequest):
    """Обновляем ключи/режим на лету (в памяти процесса + в таблице settings)."""
    if req.anthropic_api_key is not None:
        settings.anthropic_api_key = req.anthropic_api_key
        db.set_setting("anthropic_api_key", req.anthropic_api_key)
    if req.anthropic_model:
        settings.anthropic_model = req.anthropic_model
        db.set_setting("anthropic_model", req.anthropic_model)
    if req.yandex_search_api_key is not None:
        settings.yandex_search_api_key = req.yandex_search_api_key
        db.set_setting("yandex_search_api_key", req.yandex_search_api_key)
    if req.yandex_maps_api_key is not None:
        settings.yandex_maps_api_key = req.yandex_maps_api_key
        db.set_setting("yandex_maps_api_key", req.yandex_maps_api_key)
    if req.mode:
        settings.mode = req.mode
        db.set_setting("mode", req.mode)
    db.log_event("Настройки обновлены", "info", "settings")
    return {"ok": True}
