"""
Источник: Telegram-чаты — парсинг сообщений с признаками заявки.

Live-режим требует подключённого аккаунта (Telethon-сессия) и списка чатов.
Парсинг идёт через app.telegram.actions.parse_chats. Без аккаунта / в demo —
возвращаются реалистичные примеры сообщений.
"""
from __future__ import annotations

from typing import Any, Optional

from ..config import settings
from .base import Candidate


def search(
    chats: list[str],
    keywords: list[str],
    negative: Optional[list[str]] = None,
    account_id: str = "",
    limit: int = 30,
) -> list[Candidate]:
    if settings.is_live and account_id and chats:
        try:
            return _live(chats, keywords, negative or [], account_id, limit)
        except Exception:  # noqa: BLE001
            pass
    return _demo(limit)


def _live(
    chats: list[str], keywords: list[str], negative: list[str], account_id: str, limit: int
) -> list[Candidate]:
    from ..telegram import actions
    from ..telegram.client import run_coro

    rows = run_coro(actions.parse_chats(account_id, chats, keywords, negative, per_chat_limit=80))
    out = [Candidate(**{k: v for k, v in r.items() if k in Candidate.__dataclass_fields__}) for r in rows]
    return out[:limit]


def _demo(limit: int) -> list[Candidate]:
    samples = [
        (
            "Чат «Предприниматели Москвы»",
            "Иван",
            "@ivan_biz",
            "Ребят, кто делает сайты? Открываю барбершоп, нужен нормальный сайт с онлайн-записью. "
            "Посоветуйте адекватного, бюджет есть.",
        ),
        (
            "Чат «Стартапы и IT»",
            "Марина",
            "@marina_startup",
            "Ищу веб-разработчика под MVP. Нужен лендинг + личный кабинет. "
            "Кто свободен на этой неделе?",
        ),
        (
            "Чат «Бизнес Казань»",
            "Тимур",
            "@timur_kzn",
            "У нас кофейня, сайта нет вообще, только инстаграм. Хотим сайт с меню и доставкой. "
            "Куда обращаться?",
        ),
        (
            "Чат «Мамы в декрете»",
            "Ольга",
            "@olga_handmade",
            "Делаю торты на заказ, нужен простой сайт-визитка с формой заказа. "
            "Сколько это примерно стоит и кто возьмётся?",
        ),
        (
            "Чат «Фриланс-биржа»",
            "Заказчик",
            "@client_9021",
            "Требуется сайт для автосервиса: услуги, цены, запись. Срочно, оплата сразу.",
        ),
    ]
    out: list[Candidate] = []
    for chat, name, username, text in samples:
        out.append(
            Candidate(
                source="telegram",
                title=f"Сообщение в «{chat}»",
                name=name,
                contact=username,
                snippet=text,
                url=f"https://t.me/{username.lstrip('@')}",
                raw={"chat": chat, "demo": True},
            )
        )
        if len(out) >= limit:
            break
    return out
