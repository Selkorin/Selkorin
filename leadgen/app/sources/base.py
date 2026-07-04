"""Общие типы и утилиты для источников лидов."""
from __future__ import annotations

import hashlib
from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class Candidate:
    """Сырой кандидат в лиды до скоринга."""

    source: str
    snippet: str
    title: str = ""
    name: str = ""
    contact: str = ""
    location: str = ""
    url: str = ""
    raw: dict[str, Any] = field(default_factory=dict)

    def dedup_key(self) -> str:
        base = f"{self.source}|{self.contact}|{self.url}|{self.snippet[:80]}"
        return hashlib.sha1(base.encode("utf-8")).hexdigest()[:16]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
