"""
Рантайм Telegram: единый фоновый event-loop + менеджер сессий Telethon.

Весь код Telethon исполняется в одном выделенном потоке со своим asyncio-циклом.
Это избавляет от проблем «loop already running» и «client used in wrong loop»,
потому что все клиенты создаются и живут внутри этого одного цикла.

Публичные функции возвращают обычные значения (синхронно) — внутри они
прокидывают корутину в фоновый цикл через run_coroutine_threadsafe.

Если Telethon не установлен, модуль всё равно импортируется, а функции
возвращают понятную ошибку — приложение продолжает работать в остальном.
"""
from __future__ import annotations

import asyncio
import threading
from typing import Any, Optional

from .. import db

try:
    from telethon import TelegramClient
    from telethon.errors import SessionPasswordNeededError
    from telethon.sessions import StringSession

    TELETHON_AVAILABLE = True
except ImportError:  # pragma: no cover
    TELETHON_AVAILABLE = False
    TelegramClient = None  # type: ignore
    StringSession = None  # type: ignore
    SessionPasswordNeededError = Exception  # type: ignore


class _Runtime:
    """Фоновый event-loop в отдельном потоке."""

    def __init__(self) -> None:
        self.loop = asyncio.new_event_loop()
        self.thread = threading.Thread(target=self._run, daemon=True, name="tg-loop")
        self.thread.start()
        # account_id -> подключённый TelegramClient
        self.clients: dict[str, Any] = {}
        # account_id -> {phone, phone_code_hash, client} на время ввода кода
        self.pending: dict[str, dict[str, Any]] = {}

    def _run(self) -> None:
        asyncio.set_event_loop(self.loop)
        self.loop.run_forever()

    def run(self, coro, timeout: float = 90.0):
        fut = asyncio.run_coroutine_threadsafe(coro, self.loop)
        return fut.result(timeout=timeout)


_runtime: Optional[_Runtime] = None


def runtime() -> _Runtime:
    global _runtime
    if _runtime is None:
        _runtime = _Runtime()
    return _runtime


def _require_telethon() -> None:
    if not TELETHON_AVAILABLE:
        raise RuntimeError(
            "Telethon не установлен. Установите зависимости: pip install -r requirements.txt"
        )


# ── Внутренние корутины ──────────────────────────────────────────────────────
async def _make_client(api_id: str, api_hash: str, session_string: str = "") -> Any:
    client = TelegramClient(StringSession(session_string or None), int(api_id), api_hash)
    await client.connect()
    return client


async def _get_ready_client(account_id: str) -> Any:
    """Готовый авторизованный клиент для действий (рассылки/парсинг)."""
    rt = runtime()
    if account_id in rt.clients:
        client = rt.clients[account_id]
        if client.is_connected() and await client.is_user_authorized():
            return client
    acc = db.get("telegram_accounts", account_id)
    if not acc:
        raise RuntimeError("Аккаунт не найден")
    if not acc.get("session_string"):
        raise RuntimeError("Аккаунт не авторизован — войдите в разделе «Telegram».")
    client = await _make_client(acc["api_id"], acc["api_hash"], acc["session_string"])
    if not await client.is_user_authorized():
        raise RuntimeError("Сессия недействительна — авторизуйтесь заново.")
    rt.clients[account_id] = client
    return client


async def _start_login(account_id: str) -> dict[str, Any]:
    rt = runtime()
    acc = db.get("telegram_accounts", account_id)
    if not acc:
        raise RuntimeError("Аккаунт не найден")
    client = await _make_client(acc["api_id"], acc["api_hash"], acc.get("session_string", ""))
    if await client.is_user_authorized():
        me = await client.get_me()
        rt.clients[account_id] = client
        return {"status": "connected", "username": me.username, "user_id": str(me.id)}
    sent = await client.send_code_request(acc["phone"])
    rt.pending[account_id] = {
        "phone": acc["phone"],
        "phone_code_hash": sent.phone_code_hash,
        "client": client,
    }
    return {"status": "awaiting_code"}


async def _submit_code(account_id: str, code: str) -> dict[str, Any]:
    rt = runtime()
    pend = rt.pending.get(account_id)
    if not pend:
        raise RuntimeError("Сначала запросите код (login).")
    client = pend["client"]
    try:
        await client.sign_in(
            phone=pend["phone"], code=code, phone_code_hash=pend["phone_code_hash"]
        )
    except SessionPasswordNeededError:
        return {"status": "awaiting_password"}
    return await _finish_login(account_id, client)


async def _submit_password(account_id: str, password: str) -> dict[str, Any]:
    rt = runtime()
    pend = rt.pending.get(account_id)
    if not pend:
        raise RuntimeError("Нет активной сессии входа.")
    client = pend["client"]
    await client.sign_in(password=password)
    return await _finish_login(account_id, client)


async def _finish_login(account_id: str, client: Any) -> dict[str, Any]:
    rt = runtime()
    me = await client.get_me()
    session_string = client.session.save()
    db.update(
        "telegram_accounts",
        account_id,
        {
            "session_string": session_string,
            "status": "connected",
            "me_username": me.username or "",
            "me_id": str(me.id),
        },
    )
    rt.clients[account_id] = client
    rt.pending.pop(account_id, None)
    db.log_event(f"Telegram-аккаунт @{me.username or me.id} подключён", "success", "telegram")
    return {"status": "connected", "username": me.username, "user_id": str(me.id)}


# ── Публичный синхронный API ─────────────────────────────────────────────────
def start_login(account_id: str) -> dict[str, Any]:
    _require_telethon()
    try:
        res = runtime().run(_start_login(account_id))
        db.update("telegram_accounts", account_id, {"status": res["status"]})
        return res
    except Exception as e:  # noqa: BLE001
        db.update("telegram_accounts", account_id, {"status": "error", "note": str(e)})
        raise


def submit_code(account_id: str, code: str) -> dict[str, Any]:
    _require_telethon()
    res = runtime().run(_submit_code(account_id, code))
    db.update("telegram_accounts", account_id, {"status": res["status"]})
    return res


def submit_password(account_id: str, password: str) -> dict[str, Any]:
    _require_telethon()
    res = runtime().run(_submit_password(account_id, password))
    db.update("telegram_accounts", account_id, {"status": res["status"]})
    return res


def get_ready_client(account_id: str):
    """Для использования внутри других корутин Telethon (в том же цикле)."""
    return _get_ready_client(account_id)


def run_coro(coro, timeout: float = 120.0):
    """Прокинуть произвольную корутину Telethon в фоновый цикл."""
    _require_telethon()
    return runtime().run(coro, timeout=timeout)
