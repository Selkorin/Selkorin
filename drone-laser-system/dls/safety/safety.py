"""Менеджер безопасности: единая точка принятия решения о разрешении огня.

Любой запрос на включение лазера обязан пройти :meth:`SafetyManager.evaluate`.
Огонь разрешается, только если выполнены ВСЕ применимые условия. При нарушении
любого — огонь запрещается и причина попадает в решение (для лога/индикации).

Аппаратные блокировки (E-STOP, ключ, watchdog, перегрев) продублированы в
прошивке контроллера осей и не зависят от этого кода — см. ../SAFETY.md.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, List, Optional

from ..config import SafetyConfig


class FireMode(str, Enum):
    MARK = "mark"          # подсветка/маркировка дрона (безопасно для глаз)
    ELIMINATE = "eliminate"  # уничтожение насекомого (только ближняя зона)


@dataclass
class FireRequest:
    pan: float
    tilt: float
    mode: FireMode
    range_m: Optional[float] = None
    classification: Optional[str] = None   # ожидается "insect" для режима ELIMINATE


@dataclass
class SafetyDecision:
    permitted: bool
    reasons: List[str] = field(default_factory=list)   # причины запрета

    def __bool__(self) -> bool:
        return self.permitted


class SafetyManager:
    def __init__(self, cfg: SafetyConfig, clock: Callable[[], float] = time.monotonic):
        self.cfg = cfg
        self._clock = clock
        self._armed = False
        self._estop = False
        self._key_present = not cfg.require_key   # если ключ не требуется — считаем «есть»
        self._ambient_lux = 0.0
        self._human_present = False
        self._laser_temp_c = 20.0
        self._last_ping = clock()

    # ---- взведение -----------------------------------------------------
    @property
    def armed(self) -> bool:
        return self._armed

    def arm(self) -> bool:
        """Взводит систему. Возвращает False, если условия не выполнены."""
        if self._estop:
            return False
        if self.cfg.require_key and not self._key_present:
            return False
        self._armed = True
        self.ping()
        return True

    def disarm(self) -> None:
        self._armed = False

    # ---- ввод состояния датчиков --------------------------------------
    def ping(self) -> None:
        """Сброс watchdog: подтверждает, что управляющий цикл жив."""
        self._last_ping = self._clock()

    def set_estop(self, pressed: bool) -> None:
        self._estop = bool(pressed)
        if pressed:
            self._armed = False

    def set_key(self, present: bool) -> None:
        self._key_present = bool(present)

    def update_sensors(self, ambient_lux: Optional[float] = None,
                       human_present: Optional[bool] = None,
                       laser_temp_c: Optional[float] = None) -> None:
        if ambient_lux is not None:
            self._ambient_lux = float(ambient_lux)
        if human_present is not None:
            self._human_present = bool(human_present)
        if laser_temp_c is not None:
            self._laser_temp_c = float(laser_temp_c)

    # ---- главная проверка ---------------------------------------------
    def evaluate(self, req: FireRequest, continuous_fire_s: float = 0.0) -> SafetyDecision:
        reasons: List[str] = []

        if self._estop:
            reasons.append("E-STOP нажат")
        if not self._armed:
            reasons.append("система не взведена")
        if self.cfg.require_key and not self._key_present:
            reasons.append("нет ключа взведения")
        if (self._clock() - self._last_ping) > self.cfg.watchdog_timeout_s:
            reasons.append("watchdog просрочен")
        if self._laser_temp_c > self.cfg.laser_temp_max_c:
            reasons.append("перегрев лазера")
        if continuous_fire_s > self.cfg.max_continuous_fire_s:
            reasons.append("превышено время непрерывного излучения")
        if self._in_no_fire_zone(req.pan, req.tilt):
            reasons.append("цель в зоне запрета огня")

        if req.mode == FireMode.ELIMINATE:
            reasons.extend(self._eliminate_checks(req))

        return SafetyDecision(permitted=(len(reasons) == 0), reasons=reasons)

    # ---- частные проверки ---------------------------------------------
    def _in_no_fire_zone(self, pan: float, tilt: float) -> bool:
        return any(z.contains(pan, tilt) for z in self.cfg.no_fire_zones)

    def _eliminate_checks(self, req: FireRequest) -> List[str]:
        out: List[str] = []
        if self.cfg.human_presence_interlock and self._human_present:
            out.append("обнаружено присутствие человека")
        if self._ambient_lux > self.cfg.ambient_lux_max_for_eliminate:
            out.append("освещённость выше допустимой (работа вне защищённой зоны)")
        if req.range_m is None or req.range_m > self.cfg.max_range_m_for_eliminate:
            out.append("цель вне ближней зоны")
        if req.classification != "insect":
            out.append("цель не классифицирована как насекомое")
        return out
