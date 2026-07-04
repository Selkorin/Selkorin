"""Слой хранения. Обычный sqlite3 из стандартной библиотеки — без внешних ORM."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from typing import Any, Optional

from .config import DB_PATH

_local = threading.local()
_lock = threading.Lock()


def _conn() -> sqlite3.Connection:
    conn = getattr(_local, "conn", None)
    if conn is None:
        conn = sqlite3.connect(DB_PATH, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        _local.conn = conn
    return conn


def new_id() -> str:
    return uuid.uuid4().hex[:12]


def now() -> float:
    return time.time()


SCHEMA = """
CREATE TABLE IF NOT EXISTS telegram_accounts (
    id TEXT PRIMARY KEY,
    label TEXT,
    phone TEXT,
    api_id TEXT,
    api_hash TEXT,
    session_string TEXT,
    status TEXT DEFAULT 'disconnected',   -- disconnected|awaiting_code|awaiting_password|connected|error
    me_username TEXT,
    me_id TEXT,
    note TEXT,
    created_at REAL
);

CREATE TABLE IF NOT EXISTS monitors (
    id TEXT PRIMARY KEY,
    name TEXT,
    query TEXT,
    city TEXT,
    plan TEXT,                 -- JSON план поиска
    sources TEXT,              -- JSON список источников
    schedule_minutes INTEGER DEFAULT 0,   -- 0 = вручную
    enabled INTEGER DEFAULT 1,
    last_run_at REAL,
    stats TEXT,                -- JSON статистика
    created_at REAL
);

CREATE TABLE IF NOT EXISTS leads (
    id TEXT PRIMARY KEY,
    monitor_id TEXT,
    source TEXT,               -- yandex_maps|yandex_search|telegram|manual
    title TEXT,
    name TEXT,
    contact TEXT,              -- @username / телефон / ссылка
    location TEXT,
    snippet TEXT,
    url TEXT,
    score INTEGER DEFAULT 0,
    intent TEXT,               -- hot|warm|cold
    reason TEXT,
    suggested_message TEXT,
    status TEXT DEFAULT 'new', -- new|contacted|replied|won|lost|skip
    tags TEXT,                 -- JSON
    raw TEXT,                  -- JSON исходные данные
    dedup_key TEXT,
    created_at REAL
);

CREATE TABLE IF NOT EXISTS campaigns (
    id TEXT PRIMARY KEY,
    name TEXT,
    kind TEXT,                 -- broadcast|reaction|like|circle|views|forward
    account_id TEXT,
    message_template TEXT,
    media_path TEXT,
    targets TEXT,              -- JSON список целей
    settings TEXT,             -- JSON (эмодзи реакции, лимиты и т.п.)
    status TEXT DEFAULT 'draft',  -- draft|running|paused|done|error
    progress TEXT,             -- JSON {sent,failed,total}
    created_at REAL
);

CREATE TABLE IF NOT EXISTS campaign_logs (
    id TEXT PRIMARY KEY,
    campaign_id TEXT,
    target TEXT,
    action TEXT,
    status TEXT,               -- ok|fail|skip
    detail TEXT,
    created_at REAL
);

CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY,
    level TEXT,                -- info|success|warn|error
    kind TEXT,
    message TEXT,
    created_at REAL
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
);
"""


def init_db() -> None:
    with _lock:
        conn = _conn()
        conn.executescript(SCHEMA)
        conn.commit()


# ── Универсальные помощники ──────────────────────────────────────────────────
_JSON_FIELDS = {"plan", "sources", "stats", "tags", "raw", "targets", "settings", "progress"}


def _encode(data: dict[str, Any]) -> dict[str, Any]:
    out = {}
    for k, v in data.items():
        if k in _JSON_FIELDS and not isinstance(v, (str, type(None))):
            out[k] = json.dumps(v, ensure_ascii=False)
        else:
            out[k] = v
    return out


def _decode(row: sqlite3.Row) -> dict[str, Any]:
    d = dict(row)
    for k in list(d.keys()):
        if k in _JSON_FIELDS and isinstance(d[k], str):
            try:
                d[k] = json.loads(d[k])
            except (json.JSONDecodeError, TypeError):
                pass
    return d


def insert(table: str, data: dict[str, Any]) -> str:
    data = dict(data)
    data.setdefault("id", new_id())
    data.setdefault("created_at", now())
    data = _encode(data)
    cols = ", ".join(data.keys())
    placeholders = ", ".join("?" for _ in data)
    with _lock:
        conn = _conn()
        conn.execute(
            f"INSERT INTO {table} ({cols}) VALUES ({placeholders})",
            list(data.values()),
        )
        conn.commit()
    return data["id"]


def update(table: str, row_id: str, data: dict[str, Any]) -> None:
    data = _encode(dict(data))
    sets = ", ".join(f"{k}=?" for k in data)
    with _lock:
        conn = _conn()
        conn.execute(
            f"UPDATE {table} SET {sets} WHERE id=?",
            list(data.values()) + [row_id],
        )
        conn.commit()


def get(table: str, row_id: str) -> Optional[dict[str, Any]]:
    conn = _conn()
    cur = conn.execute(f"SELECT * FROM {table} WHERE id=?", (row_id,))
    row = cur.fetchone()
    return _decode(row) if row else None


def query(sql: str, params: tuple = ()) -> list[dict[str, Any]]:
    conn = _conn()
    cur = conn.execute(sql, params)
    return [_decode(r) for r in cur.fetchall()]


def delete(table: str, row_id: str) -> None:
    with _lock:
        conn = _conn()
        conn.execute(f"DELETE FROM {table} WHERE id=?", (row_id,))
        conn.commit()


def count(table: str, where: str = "", params: tuple = ()) -> int:
    conn = _conn()
    sql = f"SELECT COUNT(*) AS c FROM {table}"
    if where:
        sql += f" WHERE {where}"
    return conn.execute(sql, params).fetchone()["c"]


# ── Логи событий (лента активности) ──────────────────────────────────────────
def log_event(message: str, level: str = "info", kind: str = "system") -> None:
    insert("events", {"message": message, "level": level, "kind": kind})


# ── Настройки (key/value) ────────────────────────────────────────────────────
def set_setting(key: str, value: str) -> None:
    with _lock:
        conn = _conn()
        conn.execute(
            "INSERT INTO settings(key, value) VALUES(?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            (key, value),
        )
        conn.commit()


def get_setting(key: str, default: str = "") -> str:
    conn = _conn()
    row = conn.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return row["value"] if row else default
