"""Эндпоинты поиска: предпросмотр плана и запуск разового поиска лидов."""
from __future__ import annotations

from fastapi import APIRouter

from ..schemas import PlanRequest, SearchRequest
from ..services import leadgen

router = APIRouter(prefix="/api", tags=["search"])


@router.post("/plan")
def preview_plan(req: PlanRequest):
    """Показать, как «мозг» разложил запрос на план поиска (без сбора лидов)."""
    return leadgen.plan_for(req.query, req.city)


@router.post("/search")
def run_search(req: SearchRequest):
    """Запустить разовый поиск: собрать и оценить лиды по запросу."""
    return leadgen.run_search(
        query=req.query,
        city=req.city,
        sources=req.sources,
        account_id=req.account_id,
        min_score=req.min_score,
        plan=req.plan,
    )
