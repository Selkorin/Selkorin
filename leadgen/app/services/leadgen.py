"""
Оркестратор лидогенерации.

Превращает запрос («Найди клиентов, кому нужен сайт») в лиды:
план поиска → запуск источников → скоринг каждым кандидатом → дедуп → сохранение.
"""
from __future__ import annotations

from typing import Any, Optional

from .. import ai, db
from ..sources import telegram_chats, yandex_maps, yandex_search

DEFAULT_SOURCES = ["telegram", "yandex_search", "yandex_maps"]


def plan_for(query: str, city: str = "") -> dict[str, Any]:
    """Построить план поиска (через AI или эвристику)."""
    return ai.build_search_plan(query, city)


def _collect_candidates(
    plan: dict[str, Any], sources: list[str], account_id: str = ""
) -> list:
    candidates = []
    if "telegram" in sources:
        candidates += telegram_chats.search(
            chats=plan.get("telegram_chats", []),
            keywords=plan.get("keywords", []),
            negative=plan.get("negative_keywords", []),
            account_id=account_id,
            limit=30,
        )
    if "yandex_search" in sources:
        candidates += yandex_search.search(
            queries=plan.get("yandex_queries", []) or plan.get("keywords", []),
            limit=15,
        )
    if "yandex_maps" in sources:
        candidates += yandex_maps.search(
            categories=plan.get("maps_categories", []),
            cities=plan.get("cities", []),
            limit=20,
        )
    return candidates


def run_search(
    query: str,
    city: str = "",
    sources: Optional[list[str]] = None,
    monitor_id: str = "",
    account_id: str = "",
    min_score: int = 45,
    plan: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    """Полный проход: план → сбор → скоринг → сохранение новых лидов."""
    sources = sources or DEFAULT_SOURCES
    plan = plan or plan_for(query, city)
    niche = plan.get("niche", "услуги")
    ideal = plan.get("ideal_lead", "")

    candidates = _collect_candidates(plan, sources, account_id)

    # существующие лиды для дедупа (ключ → id)
    existing = {
        r["dedup_key"]: r["id"]
        for r in db.query("SELECT id, dedup_key FROM leads WHERE dedup_key IS NOT NULL")
    }

    saved = 0
    scored = 0
    top: list[dict[str, Any]] = []
    for cand in candidates:
        key = cand.dedup_key()
        if key in existing:
            # Уже находили раньше — показываем как «известный», не пересохраняем и не тратим AI.
            known = db.get("leads", existing[key])
            if known and known["score"] >= min_score:
                known["is_new"] = False
                top.append(known)
            continue
        verdict = ai.classify_lead(
            candidate=f"{cand.title}\n{cand.snippet}\nКонтакт: {cand.contact}",
            niche=niche,
            ideal_lead=ideal,
        )
        scored += 1
        score = int(verdict.get("score", 0))
        if score < min_score:
            continue
        lead = {
            "monitor_id": monitor_id,
            "source": cand.source,
            "title": cand.title,
            "name": cand.name,
            "contact": cand.contact,
            "location": cand.location,
            "snippet": cand.snippet,
            "url": cand.url,
            "score": score,
            "intent": verdict.get("intent", "warm"),
            "reason": verdict.get("reason", ""),
            "suggested_message": "",
            "status": "new",
            "tags": verdict.get("tags", []),
            "raw": cand.raw,
            "dedup_key": key,
        }
        lead_id = db.insert("leads", lead)
        lead["id"] = lead_id
        lead["is_new"] = True
        existing[key] = lead_id
        saved += 1
        top.append(lead)

    top.sort(key=lambda x: x["score"], reverse=True)
    db.log_event(
        f"Поиск «{query[:40]}»: проверено {scored}, новых лидов {saved}",
        "success" if saved else "info",
        "search",
    )
    return {
        "query": query,
        "plan": plan,
        "checked": scored,
        "saved": saved,
        "engine": plan.get("_engine", "heuristic"),
        "leads": top[:50],
    }
