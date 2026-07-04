"""
Эндпоинты кампаний: создание рассылок/реакций/лайков/кружков/просмотров,
управление (старт/пауза/стоп), логи, загрузка медиа (для кружков).
"""
from __future__ import annotations

import shutil

from fastapi import APIRouter, File, HTTPException, UploadFile

from .. import db
from ..config import MEDIA_DIR
from ..schemas import CampaignRequest
from ..services import outreach

router = APIRouter(prefix="/api/campaigns", tags=["campaigns"])


@router.get("")
def list_campaigns():
    return db.query("SELECT * FROM campaigns ORDER BY created_at DESC")


@router.post("")
def create_campaign(req: CampaignRequest):
    if req.kind not in ("broadcast", "reaction", "like", "circle", "views", "forward"):
        raise HTTPException(400, "Неизвестный тип кампании")
    if not db.get("telegram_accounts", req.account_id):
        raise HTTPException(400, "Сначала подключите Telegram-аккаунт")
    cid = db.insert(
        "campaigns",
        {
            "name": req.name,
            "kind": req.kind,
            "account_id": req.account_id,
            "message_template": req.message_template,
            "media_path": req.media_path,
            "targets": req.targets,
            "settings": req.settings,
            "status": "draft",
            "progress": {"sent": 0, "failed": 0, "total": len(req.targets), "done": 0},
        },
    )
    db.log_event(f"Создана кампания «{req.name}» ({req.kind})", "info", "campaign")
    return db.get("campaigns", cid)


@router.get("/{campaign_id}")
def get_campaign(campaign_id: str):
    camp = db.get("campaigns", campaign_id)
    if not camp:
        raise HTTPException(404, "Кампания не найдена")
    return camp


@router.post("/{campaign_id}/start")
def start(campaign_id: str):
    try:
        outreach.start_campaign(campaign_id)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(400, str(e))
    return {"ok": True, "status": "running"}


@router.post("/{campaign_id}/pause")
def pause(campaign_id: str):
    outreach.pause_campaign(campaign_id)
    return {"ok": True, "status": "paused"}


@router.post("/{campaign_id}/stop")
def stop(campaign_id: str):
    outreach.stop_campaign(campaign_id)
    return {"ok": True, "status": "done"}


@router.get("/{campaign_id}/logs")
def logs(campaign_id: str, limit: int = 200):
    return db.query(
        "SELECT * FROM campaign_logs WHERE campaign_id=? ORDER BY created_at DESC LIMIT ?",
        (campaign_id, limit),
    )


@router.delete("/{campaign_id}")
def delete_campaign(campaign_id: str):
    db.delete("campaigns", campaign_id)
    return {"ok": True}


@router.post("/media/upload")
async def upload_media(file: UploadFile = File(...)):
    """Загрузить видео/картинку для кружков и рассылок."""
    dest = MEDIA_DIR / file.filename
    with dest.open("wb") as f:
        shutil.copyfileobj(file.file, f)
    return {"ok": True, "path": str(dest), "filename": file.filename}
