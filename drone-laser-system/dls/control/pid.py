"""PID-регулятор с ограничением выхода и защитой от интегрального насыщения."""
from __future__ import annotations

from ..config import PIDConfig


class PID:
    def __init__(self, cfg: PIDConfig):
        self.kp = cfg.kp
        self.ki = cfg.ki
        self.kd = cfg.kd
        self.out_limit = cfg.out_limit
        self._integral = 0.0
        self._prev_error = 0.0
        self._initialized = False

    def reset(self) -> None:
        self._integral = 0.0
        self._prev_error = 0.0
        self._initialized = False

    def step(self, error: float, dt: float) -> float:
        if dt <= 0:
            return 0.0
        # производная (по первому шагу — 0, чтобы избежать скачка)
        deriv = 0.0 if not self._initialized else (error - self._prev_error) / dt
        self._initialized = True
        self._prev_error = error

        # интеграл с anti-windup: не накапливаем при насыщении выхода
        candidate_i = self._integral + error * dt
        out = self.kp * error + self.ki * candidate_i + self.kd * deriv
        if -self.out_limit <= out <= self.out_limit:
            self._integral = candidate_i
        else:
            out = _clamp(out, -self.out_limit, self.out_limit)
        return out


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)
