"""Управление лазерным излучателем.

Класс :class:`Laser` НЕ содержит логики разрешения огня — включать его можно
только после положительного решения :class:`~dls.safety.SafetyManager`.
Однако он ведёт учёт времени непрерывного излучения (``on_time_s``), который
менеджер безопасности использует для контроля предельной длительности.

Backend'ы:
  * :class:`SimLaserBackend`   — эмуляция (запись состояния, без «железа»);
  * :class:`SerialLaserBackend` — реальный контроллер осей по общему UART.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

from ..config import LaserConfig
from ..safety.safety import FireMode


class LaserBackend(ABC):
    @abstractmethod
    def set_output(self, mode: FireMode, power_pct: float, duration_ms: float) -> None: ...
    @abstractmethod
    def hold(self) -> None: ...
    def close(self) -> None: ...


class SimLaserBackend(LaserBackend):
    """Эмуляция лазера: хранит последнее состояние для отладки/симуляции."""

    def __init__(self) -> None:
        self.on = False
        self.mode: Optional[FireMode] = None
        self.power_pct = 0.0

    def set_output(self, mode: FireMode, power_pct: float, duration_ms: float) -> None:
        self.on = power_pct > 0
        self.mode = mode
        self.power_pct = power_pct

    def hold(self) -> None:
        self.on = False
        self.power_pct = 0.0


class SerialLaserBackend(LaserBackend):
    """Реальный лазер через :class:`~dls.control.hal.SerialLink`."""

    def __init__(self, link) -> None:  # link: SerialLink
        self.link = link

    def set_output(self, mode: FireMode, power_pct: float, duration_ms: float) -> None:
        self.link.write_line("FIRE %s %d %d" %
                             (mode.value.upper(), int(power_pct), int(duration_ms)))

    def hold(self) -> None:
        self.link.write_line("HOLD")


class Laser:
    def __init__(self, cfg: LaserConfig, backend: LaserBackend):
        self.cfg = cfg
        self.backend = backend
        self._on = False
        self._on_time_s = 0.0
        self._mode: Optional[FireMode] = None

    @property
    def is_on(self) -> bool:
        return self._on

    @property
    def on_time_s(self) -> float:
        """Длительность текущего непрерывного включения (0, если выключен)."""
        return self._on_time_s if self._on else 0.0

    @property
    def mode(self) -> Optional[FireMode]:
        return self._mode

    def _mode_cfg(self, mode: FireMode):
        return self.cfg.eliminate if mode == FireMode.ELIMINATE else self.cfg.mark

    def fire(self, mode: FireMode, dt: float, power_pct: Optional[float] = None) -> None:
        """Включить/удержать излучение на такт dt. Вызывать ТОЛЬКО после разрешения."""
        mcfg = self._mode_cfg(mode)
        power = mcfg.power_pct if power_pct is None else power_pct
        duration_ms = mcfg.dwell_ms if mode == FireMode.ELIMINATE else mcfg.max_on_time_s * 1000.0
        if self._on and self._mode == mode:
            self._on_time_s += dt
        else:
            self._on_time_s = dt
        self._on = True
        self._mode = mode
        self.backend.set_output(mode, power, duration_ms)

    def off(self) -> None:
        if self._on:
            self.backend.hold()
        self._on = False
        self._on_time_s = 0.0
        self._mode = None

    def close(self) -> None:
        self.off()
        self.backend.close()


def make_laser_backend(cfg: LaserConfig, link=None) -> LaserBackend:
    if cfg.backend == "serial":
        if link is None:
            raise ValueError("Для serial-лазера требуется SerialLink")
        return SerialLaserBackend(link)
    return SimLaserBackend()
