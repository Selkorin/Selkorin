"""
Обёртка над Claude для трёх задач: план поиска, скоринг лида, текст сообщения.

Если ключ ANTHROPIC_API_KEY не задан — работает эвристический фолбэк (без сети),
чтобы демо-режим был полностью функционален.
"""
from __future__ import annotations

import json
import re
from typing import Any

from .config import settings
from .prompts import LEAD_CLASSIFIER_PROMPT, OUTREACH_PROMPT, SEARCH_PLAN_PROMPT

# «Горячие» маркеры намерения для эвристики (когда AI выключен).
HOT_SIGNALS = [
    "ищу", "ищем", "нужен", "нужна", "нужен сайт", "посоветуйте", "порекомендуйте",
    "кто делает", "кто может сделать", "требуется", "ищу подрядчика", "ищу исполнителя",
    "сделать сайт", "нужен лендинг", "разработка сайта", "бюджет", "тз", "срочно",
    "хочу сайт", "нет сайта", "запускаю", "открываю", "стартап",
]
NEGATIVE_SIGNALS = [
    "вакансия", "резюме", "ищу работу", "куплю базу", "продам базу", "реклама",
    "販売", "casino", "ставки", "крипт", "инвест", "заработок", "пишите в лс всем",
]


def _extract_json(text: str) -> dict[str, Any]:
    """Достаём первый JSON-объект из ответа модели."""
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*", "", text).strip().rstrip("`").strip()
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1:
        try:
            return json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            pass
    return {}


def _client():
    try:
        import anthropic
    except ImportError:
        return None
    if not settings.anthropic_api_key:
        return None
    return anthropic.Anthropic(api_key=settings.anthropic_api_key)


def _ask(prompt: str, max_tokens: int = 1024) -> dict[str, Any]:
    client = _client()
    if client is None:
        return {}
    try:
        resp = client.messages.create(
            model=settings.anthropic_model,
            max_tokens=max_tokens,
            messages=[{"role": "user", "content": prompt}],
        )
        text = "".join(getattr(b, "text", "") for b in resp.content)
        return _extract_json(text)
    except Exception:  # noqa: BLE001 — не роняем пайплайн из-за сети/лимитов
        return {}


# ── 1. План поиска ───────────────────────────────────────────────────────────
def build_search_plan(query: str, city: str = "") -> dict[str, Any]:
    prompt = SEARCH_PLAN_PROMPT.replace("{query}", query).replace("{city}", city or "не указан")
    plan = _ask(prompt, max_tokens=1200)
    if plan:
        plan["_engine"] = "claude"
        return plan
    return _heuristic_plan(query, city)


def _heuristic_plan(query: str, city: str) -> dict[str, Any]:
    q = query.lower()
    niche = "разработка сайтов" if "сайт" in q or "лендинг" in q else "услуги"
    cities = [c.strip() for c in city.split(",") if c.strip()] or [
        "Москва", "Санкт-Петербург", "Екатеринбург", "Новосибирск", "Казань",
    ]
    return {
        "niche": niche,
        "keywords": [
            "нужен сайт", "ищу разработчика сайта", "сделать лендинг",
            "кто делает сайты", "нужен веб-разработчик", "разработка сайта под ключ",
        ],
        "intent_signals": ["ищу", "нужен", "посоветуйте", "кто делает", "бюджет", "срочно"],
        "negative_keywords": ["вакансия", "резюме", "куплю базу", "ищу работу"],
        "telegram_chats": [
            "чаты фрилансеров", "бизнес-чаты города", "чаты предпринимателей",
            "стартап-сообщества",
        ],
        "yandex_queries": [
            "нужен сайт срочно", "заказать разработку сайта", "ищу веб-студию",
        ],
        "maps_categories": ["кафе", "автосервис", "салон красоты", "стоматология", "магазин"],
        "cities": cities,
        "ideal_lead": "Малый бизнес или предприниматель без сайта, который прямо сейчас "
        "ищет исполнителя или активно развивается.",
        "_engine": "heuristic",
    }


# ── 2. Скоринг лида ──────────────────────────────────────────────────────────
def classify_lead(candidate: str, niche: str, ideal_lead: str) -> dict[str, Any]:
    prompt = (
        LEAD_CLASSIFIER_PROMPT.replace("{niche}", niche)
        .replace("{ideal_lead}", ideal_lead)
        .replace("{candidate}", candidate[:2000])
    )
    result = _ask(prompt, max_tokens=600)
    if result and "score" in result:
        result["_engine"] = "claude"
        return result
    return _heuristic_classify(candidate)


def _heuristic_classify(candidate: str) -> dict[str, Any]:
    text = candidate.lower()
    neg = sum(1 for s in NEGATIVE_SIGNALS if s in text)
    hot = sum(1 for s in HOT_SIGNALS if s in text)
    no_site = "нет сайта" in text or "без сайта" in text
    score = min(100, hot * 18 + (25 if no_site else 0))
    if neg:
        score = max(0, score - 40 * neg)
    if score >= 85:
        intent = "hot"
    elif score >= 55:
        intent = "warm"
    else:
        intent = "cold"
    tags = []
    if no_site:
        tags.append("нет сайта")
    if hot:
        tags.append("есть намерение")
    if neg:
        tags.append("возможен спам")
    return {
        "is_lead": score >= 45,
        "score": score,
        "intent": intent,
        "reason": "Оценка по ключевым маркерам намерения (эвристика без AI)."
        if not neg
        else "Похоже на спам/вакансию — оценка занижена.",
        "contact_hint": "Написать в личку и уточнить задачу.",
        "tags": tags or ["к прогреву"],
        "_engine": "heuristic",
    }


# ── 3. Персональное сообщение ────────────────────────────────────────────────
def write_outreach(lead: dict[str, Any], sender_bio: str, offer: str, tone: str = "дружелюбный") -> dict[str, Any]:
    lead_desc = json.dumps(
        {k: lead.get(k) for k in ("title", "name", "snippet", "location", "tags")},
        ensure_ascii=False,
    )
    prompt = (
        OUTREACH_PROMPT.replace("{sender_bio}", sender_bio or "веб-студия под ключ")
        .replace("{offer}", offer or "быстро сделаю современный сайт/лендинг")
        .replace("{lead}", lead_desc)
        .replace("{tone}", tone)
    )
    result = _ask(prompt, max_tokens=500)
    if result and result.get("message"):
        result["_engine"] = "claude"
        return result
    return _heuristic_outreach(lead)


def _heuristic_outreach(lead: dict[str, Any]) -> dict[str, Any]:
    name = lead.get("name") or ""
    hook = lead.get("title") or lead.get("snippet") or "ваш проект"
    greet = f"{name}, здравствуйте! " if name else "Здравствуйте! "
    return {
        "message": (
            f"{greet}Увидел, что вам актуален сайт ({hook[:80]}). "
            "Делаю современные сайты и лендинги под ключ, быстро и без воды. "
            "Подскажите, что именно нужно — соберу пару идей бесплатно?"
        ),
        "followup": "Напомню о себе — если актуально, покажу примеры под вашу нишу.",
        "_engine": "heuristic",
    }
