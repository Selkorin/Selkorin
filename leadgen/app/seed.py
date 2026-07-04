"""Демо-данные, чтобы приложение сразу было наполнено и можно было всё пощупать."""
from __future__ import annotations

from . import db
from .services import leadgen


def seed_if_empty() -> None:
    if db.count("leads") > 0 or db.count("monitors") > 0:
        return

    # Монитор по умолчанию
    plan = leadgen.plan_for("Найди мне клиентов, кому нужен сайт", "Москва, Казань")
    db.insert(
        "monitors",
        {
            "name": "Клиенты на сайт — Москва/Казань",
            "query": "Найди мне клиентов, кому нужен сайт",
            "city": "Москва, Казань",
            "plan": plan,
            "sources": leadgen.DEFAULT_SOURCES,
            "schedule_minutes": 0,
            "enabled": 1,
            "stats": {"runs": 0, "total_leads": 0},
        },
    )

    # Демо-аккаунт (не подключён — нужен реальный вход)
    db.insert(
        "telegram_accounts",
        {
            "label": "Мой аккаунт (демо)",
            "phone": "+7 900 000-00-00",
            "api_id": "",
            "api_hash": "",
            "status": "disconnected",
            "note": "Демо-запись. Впишите api_id/api_hash с my.telegram.org и войдите.",
        },
    )

    # Наполняем лидами через реальный пайплайн (demo-источники + скоринг)
    leadgen.run_search(
        query="Найди мне клиентов, кому нужен сайт",
        city="Москва, Казань",
        min_score=40,
    )

    db.log_event("Демо-данные загружены. Добро пожаловать в Selkorin!", "success", "system")
