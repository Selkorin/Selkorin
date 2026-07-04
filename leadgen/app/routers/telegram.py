"""
Эндпоинты Telegram-аккаунтов: добавление, авторизация по сессии (код + 2FA),
статус, суточные лимиты. Именно здесь заводятся «телеграм-сессии» для парсинга
и рассылок.
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from .. import db
from ..schemas import CodeRequest, PasswordRequest, TelegramAccountRequest
from ..telegram import client as tg_client
from ..telegram import safety

router = APIRouter(prefix="/api/telegram", tags=["telegram"])


def _public(acc: dict) -> dict:
    """Не отдаём наружу session_string и api_hash."""
    safe = {k: v for k, v in acc.items() if k not in ("session_string", "api_hash")}
    safe["has_session"] = bool(acc.get("session_string"))
    return safe


@router.get("/accounts")
def list_accounts():
    rows = db.query("SELECT * FROM telegram_accounts ORDER BY created_at DESC")
    return [_public(r) for r in rows]


@router.post("/accounts")
def add_account(req: TelegramAccountRequest):
    aid = db.insert(
        "telegram_accounts",
        {
            "label": req.label or req.phone,
            "phone": req.phone,
            "api_id": req.api_id,
            "api_hash": req.api_hash,
            "status": "disconnected",
        },
    )
    db.log_event(f"Добавлен Telegram-аккаунт {req.phone}", "info", "telegram")
    return _public(db.get("telegram_accounts", aid))


@router.post("/accounts/{account_id}/login")
def login(account_id: str):
    """Шаг 1: запросить код подтверждения (Telegram пришлёт его в приложение)."""
    if not db.get("telegram_accounts", account_id):
        raise HTTPException(404, "Аккаунт не найден")
    try:
        return tg_client.start_login(account_id)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(400, str(e))


@router.post("/accounts/{account_id}/code")
def submit_code(account_id: str, req: CodeRequest):
    """Шаг 2: отправить полученный код."""
    try:
        return tg_client.submit_code(account_id, req.code)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(400, str(e))


@router.post("/accounts/{account_id}/password")
def submit_password(account_id: str, req: PasswordRequest):
    """Шаг 3 (если включена двухфакторка): пароль облачного пароля Telegram."""
    try:
        return tg_client.submit_password(account_id, req.password)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(400, str(e))


@router.get("/accounts/{account_id}/usage")
def usage(account_id: str):
    return safety.usage_snapshot(account_id)


@router.delete("/accounts/{account_id}")
def delete_account(account_id: str):
    db.delete("telegram_accounts", account_id)
    return {"ok": True}
