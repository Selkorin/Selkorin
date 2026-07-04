"""Pydantic-схемы тел запросов API."""
from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel


class PlanRequest(BaseModel):
    query: str
    city: str = ""


class SearchRequest(BaseModel):
    query: str
    city: str = ""
    sources: Optional[list[str]] = None
    min_score: int = 45
    account_id: str = ""
    plan: Optional[dict[str, Any]] = None


class MonitorRequest(BaseModel):
    name: str
    query: str
    city: str = ""
    sources: Optional[list[str]] = None
    schedule_minutes: int = 0
    enabled: bool = True
    plan: Optional[dict[str, Any]] = None


class LeadStatusRequest(BaseModel):
    status: str


class OutreachRequest(BaseModel):
    sender_bio: str = ""
    offer: str = ""
    tone: str = "дружелюбный"


class TelegramAccountRequest(BaseModel):
    label: str = ""
    phone: str
    api_id: str
    api_hash: str


class CodeRequest(BaseModel):
    code: str


class PasswordRequest(BaseModel):
    password: str


class CampaignRequest(BaseModel):
    name: str
    kind: str  # broadcast|reaction|like|circle|views
    account_id: str
    message_template: str = ""
    media_path: str = ""
    targets: list[Any] = []
    settings: dict[str, Any] = {}


class SettingsRequest(BaseModel):
    anthropic_api_key: Optional[str] = None
    anthropic_model: Optional[str] = None
    yandex_search_api_key: Optional[str] = None
    yandex_maps_api_key: Optional[str] = None
    mode: Optional[str] = None
