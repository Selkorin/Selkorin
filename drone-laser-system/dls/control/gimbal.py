"""Контур наведения гимбала: PID по угловой ошибке + ограничение скорости.

На каждом такте вычисляется ошибка между текущим и целевым углом; PID выдаёт
угловую скорость (град/с), она ограничивается ``max_speed_deg_s`` и
интегрируется в новую командную позицию, которая отправляется в HAL. Это
сглаживает наведение и предотвращает перерегулирование при задержках.
"""
from __future__ import annotations

from typing import Tuple

from ..config import GimbalConfig
from .hal import GimbalHAL
from .pid import PID


class Gimbal:
    def __init__(self, cfg: GimbalConfig, hal: GimbalHAL):
        self.cfg = cfg
        self.hal = hal
        self._pid_pan = PID(cfg.pid_pan)
        self._pid_tilt = PID(cfg.pid_tilt)
        self._cmd_pan, self._cmd_tilt = hal.get_angles()

    def enable(self) -> None:
        self.hal.enable()
        self._pid_pan.reset()
        self._pid_tilt.reset()
        self._cmd_pan, self._cmd_tilt = self.hal.get_angles()

    def disable(self) -> None:
        self.hal.disable()

    def home(self) -> None:
        self.hal.home()
        self._cmd_pan, self._cmd_tilt = self.hal.get_angles()

    @property
    def angles(self) -> Tuple[float, float]:
        return self.hal.get_angles()

    def aim(self, target_pan: float, target_tilt: float, dt: float) -> Tuple[float, float]:
        """Один такт наведения на целевые углы. Возвращает текущие углы."""
        cur_pan, cur_tilt = self.hal.get_angles()

        rate_pan = self._pid_pan.step(target_pan - cur_pan, dt)
        rate_tilt = self._pid_tilt.step(target_tilt - cur_tilt, dt)

        max_step = self.cfg.max_speed_deg_s * dt
        self._cmd_pan = cur_pan + _clamp(rate_pan * dt, -max_step, max_step)
        self._cmd_tilt = cur_tilt + _clamp(rate_tilt * dt, -max_step, max_step)

        self._cmd_pan = _clamp(self._cmd_pan, self.cfg.pan_min_deg, self.cfg.pan_max_deg)
        self._cmd_tilt = _clamp(self._cmd_tilt, self.cfg.tilt_min_deg, self.cfg.tilt_max_deg)

        self.hal.set_angles(self._cmd_pan, self._cmd_tilt)
        return self.hal.get_angles()

    def aim_error(self, target_pan: float, target_tilt: float) -> float:
        """Текущая абсолютная угловая ошибка до цели, град."""
        cur_pan, cur_tilt = self.hal.get_angles()
        return max(abs(target_pan - cur_pan), abs(target_tilt - cur_tilt))

    def is_on_target(self, target_pan: float, target_tilt: float) -> bool:
        return self.aim_error(target_pan, target_tilt) <= self.cfg.aim_tolerance_deg


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)
