"""Аппаратный уровень абстракции (HAL) для гимбала.

Два backend'а:
  * :class:`SimulatedGimbalHAL` — идеальный привод, отрабатывает команды мгновенно
    (динамика движения ограничивается регулятором :class:`~dls.control.gimbal.Gimbal`);
  * :class:`SerialGimbalHAL` — реальный контроллер осей по UART (см. прошивку и
    docs/electronics.md#протокол-обмена).

:class:`SerialLink` — общий транспорт UART, разделяемый гимбалом и лазером
(они физически подключены к одному контроллеру осей).
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional, Tuple

from ..config import GimbalConfig


class GimbalHAL(ABC):
    @abstractmethod
    def enable(self) -> None: ...
    @abstractmethod
    def disable(self) -> None: ...
    @abstractmethod
    def set_angles(self, pan: float, tilt: float) -> None: ...
    @abstractmethod
    def get_angles(self) -> Tuple[float, float]: ...
    def home(self) -> None: ...
    def ping(self) -> None: ...
    def close(self) -> None: ...


class SimulatedGimbalHAL(GimbalHAL):
    """Программная модель привода для запуска без «железа»."""

    def __init__(self, cfg: GimbalConfig):
        self.cfg = cfg
        self._pan = 0.0
        self._tilt = 0.0
        self._enabled = False

    def enable(self) -> None:
        self._enabled = True

    def disable(self) -> None:
        self._enabled = False

    def set_angles(self, pan: float, tilt: float) -> None:
        if not self._enabled:
            return
        self._pan = _clamp(pan, self.cfg.pan_min_deg, self.cfg.pan_max_deg)
        self._tilt = _clamp(tilt, self.cfg.tilt_min_deg, self.cfg.tilt_max_deg)

    def get_angles(self) -> Tuple[float, float]:
        return self._pan, self._tilt

    def home(self) -> None:
        self._pan = 0.0
        self._tilt = 0.0


class SerialLink:
    """Транспорт UART к контроллеру осей (общий для гимбала и лазера)."""

    def __init__(self, port: str, baud: int = 115200):
        import serial  # локальный импорт: нужен только на реальном оборудовании
        self._ser = serial.Serial(port, baud, timeout=0.05)
        self.last_telemetry: dict = {}

    def write_line(self, line: str) -> None:
        self._ser.write((line + "\n").encode("ascii"))

    def poll(self) -> None:
        """Читает и парсит строки телеметрии контроллера (best-effort)."""
        try:
            while self._ser.in_waiting:
                raw = self._ser.readline().decode("ascii", "ignore").strip()
                self._parse(raw)
        except Exception:
            pass

    def _parse(self, line: str) -> None:
        toks = line.split()
        it = iter(toks)
        for key in it:
            try:
                self.last_telemetry[key] = next(it)
            except StopIteration:
                break

    def close(self) -> None:
        try:
            self._ser.close()
        except Exception:
            pass


class SerialGimbalHAL(GimbalHAL):
    """Гимбал на реальном контроллере осей через :class:`SerialLink`."""

    def __init__(self, cfg: GimbalConfig, link: SerialLink):
        self.cfg = cfg
        self.link = link

    def enable(self) -> None:
        self.link.write_line("ARM")

    def disable(self) -> None:
        self.link.write_line("DISARM")

    def set_angles(self, pan: float, tilt: float) -> None:
        pan = _clamp(pan, self.cfg.pan_min_deg, self.cfg.pan_max_deg)
        tilt = _clamp(tilt, self.cfg.tilt_min_deg, self.cfg.tilt_max_deg)
        self.link.write_line("AIM %.3f %.3f" % (pan, tilt))

    def get_angles(self) -> Tuple[float, float]:
        self.link.poll()
        t = self.link.last_telemetry
        try:
            return float(t.get("PAN", 0.0)), float(t.get("TILT", 0.0))
        except (TypeError, ValueError):
            return 0.0, 0.0

    def home(self) -> None:
        self.link.write_line("HOME")

    def ping(self) -> None:
        self.link.write_line("PING")

    def close(self) -> None:
        self.link.close()


def make_gimbal_hal(cfg: GimbalConfig,
                    link: Optional[SerialLink] = None) -> GimbalHAL:
    if cfg.backend == "serial":
        if link is None:
            link = SerialLink(cfg.serial_port, cfg.baud)
        return SerialGimbalHAL(cfg, link)
    return SimulatedGimbalHAL(cfg)


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)
