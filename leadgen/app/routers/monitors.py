"""Эндпоинты мониторов: CRUD, ручной запуск, включение/выключение."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from .. import db
from ..schemas import MonitorRequest
from ..services import leadgen, monitoring

router = APIRouter(prefix="/api/monitors", tags=["monitors"])


@router.get("")
def list_monitors():
    return db.query("SELECT * FROM monitors ORDER BY created_at DESC")


@router.post("")
def create_monitor(req: MonitorRequest):
    plan = req.plan or leadgen.plan_for(req.query, req.city)
    mid = db.insert(
        "monitors",
        {
            "name": req.name,
            "query": req.query,
            "city": req.city,
            "plan": plan,
            "sources": req.sources or leadgen.DEFAULT_SOURCES,
            "schedule_minutes": req.schedule_minutes,
            "enabled": 1 if req.enabled else 0,
            "stats": {"runs": 0, "total_leads": 0},
        },
    )
    db.log_event(f"Создан монитор «{req.name}»", "success", "monitor")
    return db.get("monitors", mid)


@router.get("/{monitor_id}")
def get_monitor(monitor_id: str):
    mon = db.get("monitors", monitor_id)
    if not mon:
        raise HTTPException(404, "Монитор не найден")
    return mon


@router.post("/{monitor_id}/run")
def run_monitor(monitor_id: str):
    if not db.get("monitors", monitor_id):
        raise HTTPException(404, "Монитор не найден")
    return monitoring.run_monitor(monitor_id)


@router.patch("/{monitor_id}/toggle")
def toggle_monitor(monitor_id: str):
    mon = db.get("monitors", monitor_id)
    if not mon:
        raise HTTPException(404, "Монитор не найден")
    new_val = 0 if mon.get("enabled") else 1
    db.update("monitors", monitor_id, {"enabled": new_val})
    return {"ok": True, "enabled": bool(new_val)}


@router.delete("/{monitor_id}")
def delete_monitor(monitor_id: str):
    db.delete("monitors", monitor_id)
    return {"ok": True}
