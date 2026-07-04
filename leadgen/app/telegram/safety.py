"""
Защита аккаунта от блокировки.

Массовые действия в Telegram (рассылки, реакции, кружки) — прямой путь к бану,
если делать их быстро и без пауз. Здесь — человекоподобные задержки и суточные
лимиты. Значения по умолчанию сознательно консервативные.

⚠️  Автоматизация пользовательских аккаунтов нарушает ToS Telegram и может
    привести к блокировке номера. Используйте на свой риск и на «прогретых»
    аккаунтах, начиная с малых объёмов.
"""
from __future__ import annotations

import asyncio
import random
import time
from collections import defaultdict

from ..config import settings

# счётчики действий по (account_id, action, YYYY-MM-DD)
_counters: dict[tuple[str, str, str], int] = defaultdict(int)


def _day() -> str:
    return time.strftime("%Y-%m-%d")


def limit_for(action: str) -> int:
    return {
        "message": settings.tg_daily_message_limit,
        "reaction": settings.tg_daily_reaction_limit,
        "like": settings.tg_daily_reaction_limit,
        "circle": settings.tg_daily_message_limit,
        "views": 10_000,
        "forward": settings.tg_daily_message_limit,
    }.get(action, 50)


def remaining(account_id: str, action: str) -> int:
    used = _counters[(account_id, action, _day())]
    return max(0, limit_for(action) - used)


def can_do(account_id: str, action: str) -> bool:
    return remaining(account_id, action) > 0


def record(account_id: str, action: str) -> None:
    _counters[(account_id, action, _day())] += 1


async def human_delay(fast: bool = False) -> None:
    """Случайная пауза, имитирующая живого пользователя."""
    lo, hi = settings.tg_min_delay_sec, settings.tg_max_delay_sec
    if fast:
        lo, hi = max(1.0, lo / 2), max(2.0, hi / 2)
    await asyncio.sleep(random.uniform(lo, hi))


def usage_snapshot(account_id: str) -> dict[str, dict[str, int]]:
    day = _day()
    out: dict[str, dict[str, int]] = {}
    for action in ("message", "reaction", "like", "circle"):
        out[action] = {
            "used": _counters[(account_id, action, day)],
            "limit": limit_for(action),
        }
    return out
