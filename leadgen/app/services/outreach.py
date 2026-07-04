"""
Движок кампаний рассылки и активности в Telegram.

Поддерживает типы кампаний:
  • broadcast — массовая рассылка личных сообщений (с персонализацией через AI и spintax)
  • reaction  — массовые реакции на сообщения
  • like      — массовые «лайки» (реакция ❤️)
  • circle    — рассылка видео-кружков
  • views     — накрутка просмотров постов канала

Кампания выполняется в фоновом потоке с человекоподобными паузами и учётом
суточных лимитов (app.telegram.safety). Управление: start / pause / stop.
"""
from __future__ import annotations

import random
import threading
import time
from typing import Any

from .. import ai, db
from ..telegram import actions, safety

# campaign_id -> {"stop": bool, "pause": bool, "thread": Thread}
_control: dict[str, dict[str, Any]] = {}


def _parse_message_target(target: str) -> tuple[str, int]:
    """Из t.me/chat/123 или 'chat#123' извлекаем (chat, message_id)."""
    t = str(target).strip()
    if "t.me/" in t:
        parts = t.split("t.me/")[1].split("/")
        if len(parts) >= 2 and parts[1].isdigit():
            return parts[0], int(parts[1])
    if "#" in t:
        chat, mid = t.rsplit("#", 1)
        if mid.isdigit():
            return chat.lstrip("@"), int(mid)
    return t, 0


def start_campaign(campaign_id: str) -> None:
    camp = db.get("campaigns", campaign_id)
    if not camp:
        raise RuntimeError("Кампания не найдена")
    if campaign_id in _control and not _control[campaign_id].get("stop"):
        raise RuntimeError("Кампания уже запущена")
    ctrl = {"stop": False, "pause": False}
    _control[campaign_id] = ctrl
    t = threading.Thread(target=_run, args=(campaign_id, ctrl), daemon=True)
    ctrl["thread"] = t
    db.update("campaigns", campaign_id, {"status": "running"})
    t.start()


def pause_campaign(campaign_id: str) -> None:
    if campaign_id in _control:
        _control[campaign_id]["pause"] = True
        db.update("campaigns", campaign_id, {"status": "paused"})


def resume_campaign(campaign_id: str) -> None:
    if campaign_id in _control:
        _control[campaign_id]["pause"] = False
        db.update("campaigns", campaign_id, {"status": "running"})
    else:
        start_campaign(campaign_id)


def stop_campaign(campaign_id: str) -> None:
    if campaign_id in _control:
        _control[campaign_id]["stop"] = True
    db.update("campaigns", campaign_id, {"status": "done"})


def _log(campaign_id: str, target: str, action: str, status: str, detail: str) -> None:
    db.insert(
        "campaign_logs",
        {
            "campaign_id": campaign_id,
            "target": str(target),
            "action": action,
            "status": status,
            "detail": detail,
        },
    )


def _run(campaign_id: str, ctrl: dict[str, Any]) -> None:
    from ..telegram.client import run_coro

    camp = db.get("campaigns", campaign_id)
    kind = camp["kind"]
    account_id = camp["account_id"]
    targets = camp.get("targets") or []
    cfg = camp.get("settings") or {}
    template = camp.get("message_template") or ""
    media_path = camp.get("media_path") or ""
    emoji = cfg.get("emoji", "👍")
    personalize = bool(cfg.get("personalize"))
    sender_bio = cfg.get("sender_bio", "")
    offer = cfg.get("offer", "")

    total = len(targets)
    sent = failed = 0
    db.log_event(f"Кампания «{camp['name']}» запущена ({kind}, целей: {total})", "info", "campaign")

    for idx, target in enumerate(targets):
        if ctrl.get("stop"):
            break
        while ctrl.get("pause") and not ctrl.get("stop"):
            time.sleep(1)
        if ctrl.get("stop"):
            break

        try:
            result = _do_one(
                run_coro, kind, account_id, target, template, media_path, emoji,
                personalize, sender_bio, offer, cfg,
            )
        except Exception as e:  # noqa: BLE001
            result = {"status": "fail", "detail": str(e)}

        status = result.get("status", "fail")
        if status == "ok":
            sent += 1
        elif status == "fail":
            failed += 1
        _log(campaign_id, target if isinstance(target, str) else str(target),
             kind, status, result.get("detail", ""))
        db.update(
            "campaigns",
            campaign_id,
            {"progress": {"sent": sent, "failed": failed, "total": total, "done": idx + 1}},
        )

        if status == "skip":  # уперлись в суточный лимит — останавливаемся мягко
            db.log_event(f"Кампания «{camp['name']}»: {result.get('detail')}", "warn", "campaign")
            break

        # человекоподобная пауза между действиями
        lo, hi = cfg.get("min_delay"), cfg.get("max_delay")
        from ..config import settings as _s
        lo = lo if lo else _s.tg_min_delay_sec
        hi = hi if hi else _s.tg_max_delay_sec
        time.sleep(random.uniform(float(lo), float(hi)))

    final_status = "done"
    db.update("campaigns", campaign_id, {"status": final_status})
    db.log_event(
        f"Кампания «{camp['name']}» завершена: отправлено {sent}, ошибок {failed}",
        "success" if sent else "warn",
        "campaign",
    )
    _control.pop(campaign_id, None)


def _do_one(
    run_coro, kind, account_id, target, template, media_path, emoji,
    personalize, sender_bio, offer, cfg,
) -> dict[str, Any]:
    if kind == "broadcast":
        text = template
        if personalize:
            lead = _target_lead(target)
            if lead:
                gen = ai.write_outreach(lead, sender_bio, offer, cfg.get("tone", "дружелюбный"))
                text = gen.get("message", template)
        text = actions.apply_spintax(text)
        return run_coro(actions.send_message(account_id, _target_contact(target), text))

    if kind in ("reaction", "like"):
        chat, mid = _parse_message_target(target if isinstance(target, str) else target.get("target", ""))
        em = "❤️" if kind == "like" else emoji
        return run_coro(actions.send_reaction(account_id, chat, mid, em))

    if kind == "circle":
        return run_coro(actions.send_circle(account_id, _target_contact(target), media_path))

    if kind == "views":
        chat, mid = _parse_message_target(target if isinstance(target, str) else str(target))
        return run_coro(actions.boost_views(account_id, chat, [mid]))

    return {"status": "fail", "detail": f"неизвестный тип: {kind}"}


def _target_contact(target: Any) -> str:
    if isinstance(target, dict):
        return target.get("contact") or target.get("target") or ""
    return str(target)


def _target_lead(target: Any) -> dict[str, Any]:
    """Если цель — это лид (dict) или id лида, вернём его данные для персонализации."""
    if isinstance(target, dict) and target.get("snippet"):
        return target
    if isinstance(target, dict) and target.get("lead_id"):
        return db.get("leads", target["lead_id"]) or {}
    return {}
