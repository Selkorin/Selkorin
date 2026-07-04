"""
Планировщик мониторов.

Монитор — это сохранённый запрос («Найди клиентов, кому нужен сайт») с планом,
списком источников и интервалом. Планировщик в фоне запускает те мониторы,
у которых пришло время (schedule_minutes > 0), и складывает новые лиды.
"""
from __future__ import annotations

import threading
import time
from typing import Any

from .. import db
from . import leadgen

_scheduler_thread: threading.Thread | None = None
_stop = threading.Event()


def run_monitor(monitor_id: str) -> dict[str, Any]:
    mon = db.get("monitors", monitor_id)
    if not mon:
        raise RuntimeError("Монитор не найден")
    result = leadgen.run_search(
        query=mon["query"],
        city=mon.get("city", ""),
        sources=mon.get("sources") or leadgen.DEFAULT_SOURCES,
        monitor_id=monitor_id,
        plan=mon.get("plan"),
    )
    stats = mon.get("stats") or {"runs": 0, "total_leads": 0}
    stats["runs"] = stats.get("runs", 0) + 1
    stats["total_leads"] = stats.get("total_leads", 0) + result["saved"]
    stats["last_saved"] = result["saved"]
    db.update(
        "monitors",
        monitor_id,
        {"last_run_at": time.time(), "stats": stats},
    )
    return result


def _due(mon: dict[str, Any]) -> bool:
    if not mon.get("enabled") or not mon.get("schedule_minutes"):
        return False
    last = mon.get("last_run_at") or 0
    return (time.time() - last) >= mon["schedule_minutes"] * 60


def _loop() -> None:
    while not _stop.is_set():
        try:
            for mon in db.query("SELECT * FROM monitors WHERE enabled=1"):
                if _due(mon):
                    try:
                        run_monitor(mon["id"])
                    except Exception as e:  # noqa: BLE001
                        db.log_event(f"Ошибка монитора «{mon.get('name')}»: {e}", "error", "monitor")
        except Exception:  # noqa: BLE001
            pass
        _stop.wait(30)


def start_scheduler() -> None:
    global _scheduler_thread
    if _scheduler_thread and _scheduler_thread.is_alive():
        return
    _stop.clear()
    _scheduler_thread = threading.Thread(target=_loop, daemon=True, name="monitor-scheduler")
    _scheduler_thread.start()
