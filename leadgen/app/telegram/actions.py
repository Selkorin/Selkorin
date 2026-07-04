"""
Действия в Telegram через Telethon: парсинг чатов, рассылка, реакции, лайки,
кружки (видеосообщения), накрутка просмотров, пересылка.

Все функции — корутины, исполняются в фоновом цикле (см. client.py).
Каждая операция обёрнута в try/except, чтобы сбой на одной цели не рушил кампанию.
"""
from __future__ import annotations

import random
from typing import Any, Optional

from . import safety
from .client import get_ready_client


async def parse_chats(
    account_id: str,
    chats: list[str],
    keywords: list[str],
    negative: Optional[list[str]] = None,
    per_chat_limit: int = 60,
) -> list[dict[str, Any]]:
    """Пройтись по чатам и вернуть свежие сообщения, где встречаются ключевые слова."""
    negative = [n.lower() for n in (negative or [])]
    keys = [k.lower() for k in keywords]
    client = await get_ready_client(account_id)
    found: list[dict[str, Any]] = []

    for chat in chats:
        try:
            entity = await client.get_entity(chat)
        except Exception:  # noqa: BLE001 — чат недоступен / не найден
            continue
        try:
            async for msg in client.iter_messages(entity, limit=per_chat_limit):
                text = (msg.message or "").strip()
                if not text or len(text) < 12:
                    continue
                low = text.lower()
                if any(n in low for n in negative):
                    continue
                if keys and not any(k in low for k in keys):
                    continue
                sender = await _safe_sender(msg)
                username = getattr(sender, "username", None)
                name = _display_name(sender)
                chat_username = getattr(entity, "username", None)
                link = (
                    f"https://t.me/{chat_username}/{msg.id}" if chat_username else ""
                )
                found.append(
                    {
                        "source": "telegram",
                        "title": f"Сообщение в «{getattr(entity, 'title', chat)}»",
                        "name": name,
                        "contact": f"@{username}" if username else (link or "скрыт"),
                        "location": "",
                        "snippet": text[:500],
                        "url": link,
                        "raw": {
                            "chat": str(chat),
                            "message_id": msg.id,
                            "sender_id": getattr(sender, "id", None),
                            "date": str(msg.date),
                        },
                    }
                )
        except Exception:  # noqa: BLE001
            continue
    return found


async def _safe_sender(msg) -> Any:
    try:
        return await msg.get_sender()
    except Exception:  # noqa: BLE001
        return None


def _display_name(sender) -> str:
    if not sender:
        return ""
    first = getattr(sender, "first_name", "") or ""
    last = getattr(sender, "last_name", "") or ""
    title = getattr(sender, "title", "") or ""
    return (f"{first} {last}".strip() or title).strip()


async def send_message(account_id: str, target: str, text: str) -> dict[str, Any]:
    if not safety.can_do(account_id, "message"):
        return {"status": "skip", "detail": "достигнут суточный лимит сообщений"}
    client = await get_ready_client(account_id)
    try:
        await client.send_message(_target(target), text)
        safety.record(account_id, "message")
        return {"status": "ok", "detail": "отправлено"}
    except Exception as e:  # noqa: BLE001
        return {"status": "fail", "detail": str(e)}


async def send_reaction(
    account_id: str, target: str, message_id: int, emoji: str = "👍"
) -> dict[str, Any]:
    from telethon.tl.functions.messages import SendReactionRequest
    from telethon.tl.types import ReactionEmoji

    action = "like" if emoji in ("❤️", "❤", "♥️") else "reaction"
    if not safety.can_do(account_id, action):
        return {"status": "skip", "detail": "достигнут суточный лимит реакций"}
    client = await get_ready_client(account_id)
    try:
        await client(
            SendReactionRequest(
                peer=_target(target),
                msg_id=int(message_id),
                reaction=[ReactionEmoji(emoticon=emoji)],
            )
        )
        safety.record(account_id, action)
        return {"status": "ok", "detail": f"реакция {emoji}"}
    except Exception as e:  # noqa: BLE001
        return {"status": "fail", "detail": str(e)}


async def send_circle(account_id: str, target: str, video_path: str) -> dict[str, Any]:
    """Отправить видеосообщение-«кружок»."""
    if not safety.can_do(account_id, "circle"):
        return {"status": "skip", "detail": "достигнут суточный лимит"}
    client = await get_ready_client(account_id)
    try:
        await client.send_file(_target(target), video_path, video_note=True)
        safety.record(account_id, "circle")
        return {"status": "ok", "detail": "кружок отправлен"}
    except Exception as e:  # noqa: BLE001
        return {"status": "fail", "detail": str(e)}


async def boost_views(
    account_id: str, channel: str, message_ids: list[int]
) -> dict[str, Any]:
    from telethon.tl.functions.messages import GetMessagesViewsRequest

    client = await get_ready_client(account_id)
    try:
        await client(
            GetMessagesViewsRequest(
                peer=_target(channel), id=[int(m) for m in message_ids], increment=True
            )
        )
        return {"status": "ok", "detail": f"просмотры +{len(message_ids)}"}
    except Exception as e:  # noqa: BLE001
        return {"status": "fail", "detail": str(e)}


async def forward(
    account_id: str, target: str, from_chat: str, message_id: int
) -> dict[str, Any]:
    client = await get_ready_client(account_id)
    try:
        await client.forward_messages(_target(target), int(message_id), _target(from_chat))
        safety.record(account_id, "forward")
        return {"status": "ok", "detail": "переслано"}
    except Exception as e:  # noqa: BLE001
        return {"status": "fail", "detail": str(e)}


async def deliver_to_me(account_id: str, text: str) -> dict[str, Any]:
    """Прислать пользователю подборку в «Избранное» (Saved Messages)."""
    client = await get_ready_client(account_id)
    try:
        await client.send_message("me", text)
        return {"status": "ok"}
    except Exception as e:  # noqa: BLE001
        return {"status": "fail", "detail": str(e)}


def _target(target: str):
    """Нормализуем цель: @username, t.me/username, числовой id."""
    t = str(target).strip()
    if t.startswith("https://t.me/"):
        t = t.split("t.me/")[1].split("/")[0]
    if t.lstrip("-").isdigit():
        return int(t)
    return t.lstrip("@") and ("@" + t.lstrip("@"))


def apply_spintax(text: str) -> str:
    """{Привет|Здравствуйте} → случайный вариант. Делает рассылку менее шаблонной."""
    import re

    def repl(m):
        return random.choice(m.group(1).split("|"))

    while "{" in text and "}" in text:
        new = re.sub(r"\{([^{}]+)\}", repl, text)
        if new == text:
            break
        text = new
    return text
