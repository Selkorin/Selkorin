"""
Источник: поиск Яндекса — свежие публичные заявки «нужен сайт».

Live-режим использует официальный Yandex Search API (XML), если задан
YANDEX_SEARCH_API_KEY (в формате 'user:key'). Скрейпинг выдачи напрямую
Яндекс блокирует, поэтому честный live-путь — именно официальный API.
Без ключа — демо-данные.
"""
from __future__ import annotations

from ..config import settings
from .base import Candidate

XML_URL = "https://yandex.ru/search/xml"


def search(queries: list[str], limit: int = 15) -> list[Candidate]:
    if settings.is_live and settings.yandex_search_api_key and ":" in settings.yandex_search_api_key:
        try:
            return _live_search(queries, limit)
        except Exception:  # noqa: BLE001
            pass
    return _demo(queries, limit)


def _live_search(queries: list[str], limit: int) -> list[Candidate]:
    import xml.etree.ElementTree as ET

    import httpx

    user, key = settings.yandex_search_api_key.split(":", 1)
    out: list[Candidate] = []
    with httpx.Client(timeout=15) as client:
        for q in queries[:5]:
            params = {"user": user, "key": key, "query": q, "l10n": "ru", "sortby": "tm"}
            r = client.get(XML_URL, params=params)
            r.raise_for_status()
            root = ET.fromstring(r.text)
            for doc in root.iter("doc"):
                url = (doc.findtext("url") or "").strip()
                title = "".join(doc.find("title").itertext()) if doc.find("title") is not None else ""
                passage = ""
                for p in doc.iter("passage"):
                    passage += "".join(p.itertext()) + " "
                out.append(
                    Candidate(
                        source="yandex_search",
                        title=title.strip() or q,
                        snippet=passage.strip()[:400] or q,
                        url=url,
                        contact=url,
                        raw={"query": q},
                    )
                )
                if len(out) >= limit:
                    return out
    return out


def _demo(queries: list[str], limit: int) -> list[Candidate]:
    base = [
        (
            "«Ищу того, кто сделает сайт для доставки еды»",
            "Форум предпринимателей: открываю доставку, срочно нужен сайт с корзиной и оплатой. "
            "Бюджет обсуждаем, важна скорость. Пишите в личку.",
            "https://forum.example.ru/topic/2481",
        ),
        (
            "Нужен лендинг для стоматологии — кто возьмётся?",
            "Владелец клиники ищет исполнителя на одностраничник с записью онлайн. "
            "Готов оплатить сразу, нужен портфель работ.",
            "https://vc.ru/ask/website-dentist",
        ),
        (
            "Посоветуйте веб-студию под интернет-магазин",
            "Расширяем офлайн-магазин, хотим сайт-каталог с корзиной. "
            "Ищем адекватного подрядчика в Москве или удалённо.",
            "https://pikabu.ru/story/nuzhen_sayt",
        ),
        (
            "Сделаю сайт сам или заказать? Помогите определиться",
            "Малый бизнес, кофейня. Нет времени вникать в конструкторы, "
            "проще заказать. Куда обратиться?",
            "https://otvet.example.ru/q/coffee-site",
        ),
        (
            "Требуется разработчик лендинга для запуска курса",
            "Онлайн-школа, запуск через 3 недели. Нужен продающий лендинг + интеграция с оплатой.",
            "https://freelance.example.ru/project/9921",
        ),
    ]
    out: list[Candidate] = []
    for title, snippet, url in base:
        out.append(
            Candidate(
                source="yandex_search",
                title=title,
                snippet=snippet,
                url=url,
                contact=url,
                raw={"queries": queries},
            )
        )
        if len(out) >= limit:
            break
    return out
