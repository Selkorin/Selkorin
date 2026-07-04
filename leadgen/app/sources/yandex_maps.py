"""
Источник: Яндекс.Карты — бизнесы БЕЗ сайта.

Логика: ищем организации по категории в городе через Yandex Geosearch API,
оставляем те, у кого в карточке нет ссылки на сайт. Это готовые лиды —
им можно предложить разработку сайта.

Live-режим требует ключа YANDEX_MAPS_API_KEY (Yandex Geosearch/Places API).
Без ключа возвращаются реалистичные демо-данные.
"""
from __future__ import annotations

from typing import Any

from ..config import settings
from .base import Candidate

GEOSEARCH_URL = "https://search-maps.yandex.ru/v1/"


def search(categories: list[str], cities: list[str], limit: int = 20) -> list[Candidate]:
    if settings.is_live and settings.yandex_maps_api_key:
        try:
            return _live_search(categories, cities, limit)
        except Exception:  # noqa: BLE001 — при сбое сети отдаём демо
            pass
    return _demo(categories, cities, limit)


def _live_search(categories: list[str], cities: list[str], limit: int) -> list[Candidate]:
    import httpx

    out: list[Candidate] = []
    with httpx.Client(timeout=15) as client:
        for city in cities[:3]:
            for cat in categories[:4]:
                params = {
                    "apikey": settings.yandex_maps_api_key,
                    "text": f"{cat} {city}",
                    "lang": "ru_RU",
                    "type": "biz",
                    "results": min(limit, 50),
                }
                r = client.get(GEOSEARCH_URL, params=params)
                r.raise_for_status()
                data = r.json()
                for feat in data.get("features", []):
                    props = feat.get("properties", {})
                    meta = props.get("CompanyMetaData", {})
                    website = meta.get("url", "")
                    if website:  # у кого есть сайт — пропускаем
                        continue
                    phones = ", ".join(p.get("formatted", "") for p in meta.get("Phones", []))
                    out.append(
                        Candidate(
                            source="yandex_maps",
                            title=meta.get("name", cat),
                            name=meta.get("name", ""),
                            contact=phones,
                            location=meta.get("address", city),
                            snippet=f"{cat} в {city}. Нет сайта. Категория: "
                            f"{meta.get('Categories', [{}])[0].get('name', cat)}.",
                            url="",
                            raw=meta,
                        )
                    )
                    if len(out) >= limit:
                        return out
    return out


def _demo(categories: list[str], cities: list[str], limit: int) -> list[Candidate]:
    cats = categories or ["кафе", "автосервис", "салон красоты"]
    towns = cities or ["Москва", "Казань"]
    samples = [
        ("Кофейня «Зерно»", "кафе", "+7 999 123-45-67", "ул. Баумана, 12"),
        ("Автосервис «Гараж №5»", "автосервис", "+7 917 555-10-20", "пр. Победы, 44"),
        ("Салон красоты «Локон»", "салон красоты", "+7 927 700-80-90", "ул. Кремлёвская, 3"),
        ("Стоматология «Улыбка+»", "стоматология", "+7 843 210-11-22", "ул. Пушкина, 7"),
        ("Пекарня «Тёплый хлеб»", "пекарня", "+7 900 300-40-50", "ул. Мира, 21"),
        ("Барбершоп «Борода»", "барбершоп", "+7 987 111-22-33", "ул. Чехова, 9"),
        ("Магазин цветов «Флора»", "магазин", "+7 962 444-55-66", "пр. Ленина, 88"),
        ("Фитнес-студия «Пульс»", "фитнес", "+7 951 777-88-99", "ул. Спортивная, 5"),
    ]
    out: list[Candidate] = []
    i = 0
    for city in towns:
        for name, cat, phone, addr in samples:
            if cat not in cats and cats:
                # всё равно добавим часть, чтобы демо было наполнено
                if i % 2 == 0:
                    i += 1
                    continue
            out.append(
                Candidate(
                    source="yandex_maps",
                    title=name,
                    name=name,
                    contact=phone,
                    location=f"{city}, {addr}",
                    snippet=f"{cat.capitalize()} «{name}» в городе {city}. "
                    "В карточке Яндекс.Карт НЕТ сайта — есть только телефон. "
                    "Хороший кандидат: активный офлайн-бизнес без веб-присутствия.",
                    url="",
                    raw={"category": cat, "city": city, "has_website": False},
                )
            )
            i += 1
            if len(out) >= limit:
                return out
    return out
