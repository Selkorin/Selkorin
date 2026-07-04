"""Эндпоинты лидов: список с фильтрами, карточка, смена статуса, генерация письма."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from .. import ai, db
from ..schemas import LeadStatusRequest, OutreachRequest

router = APIRouter(prefix="/api/leads", tags=["leads"])


@router.get("")
def list_leads(
    status: str = "",
    source: str = "",
    intent: str = "",
    min_score: int = 0,
    q: str = "",
    limit: int = 200,
):
    where = ["1=1"]
    params: list = []
    if status:
        where.append("status=?")
        params.append(status)
    if source:
        where.append("source=?")
        params.append(source)
    if intent:
        where.append("intent=?")
        params.append(intent)
    if min_score:
        where.append("score>=?")
        params.append(min_score)
    if q:
        where.append("(title LIKE ? OR snippet LIKE ? OR name LIKE ?)")
        like = f"%{q}%"
        params += [like, like, like]
    sql = (
        f"SELECT * FROM leads WHERE {' AND '.join(where)} "
        "ORDER BY score DESC, created_at DESC LIMIT ?"
    )
    params.append(limit)
    return db.query(sql, tuple(params))


@router.get("/{lead_id}")
def get_lead(lead_id: str):
    lead = db.get("leads", lead_id)
    if not lead:
        raise HTTPException(404, "Лид не найден")
    return lead


@router.patch("/{lead_id}/status")
def set_status(lead_id: str, req: LeadStatusRequest):
    if not db.get("leads", lead_id):
        raise HTTPException(404, "Лид не найден")
    db.update("leads", lead_id, {"status": req.status})
    return {"ok": True, "status": req.status}


@router.post("/{lead_id}/message")
def generate_message(lead_id: str, req: OutreachRequest):
    """Сгенерировать персональное первое сообщение под лид."""
    lead = db.get("leads", lead_id)
    if not lead:
        raise HTTPException(404, "Лид не найден")
    gen = ai.write_outreach(lead, req.sender_bio, req.offer, req.tone)
    db.update("leads", lead_id, {"suggested_message": gen.get("message", "")})
    return gen


@router.delete("/{lead_id}")
def delete_lead(lead_id: str):
    db.delete("leads", lead_id)
    return {"ok": True}
