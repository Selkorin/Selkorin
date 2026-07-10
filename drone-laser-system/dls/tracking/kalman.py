"""Фильтр Калмана с моделью постоянной скорости в плоскости изображения.

Вектор состояния: [x, y, vx, vy] (позиция в пикселях, скорость в пикс/с).
Измерение: [x, y]. Используется для сглаживания траектории цели и
предсказания её положения на следующий кадр (компенсация задержки наведения).
"""
from __future__ import annotations

import numpy as np


class KalmanFilter2D:
    def __init__(self, x0: float, y0: float,
                 process_var: float = 50.0, measurement_var: float = 4.0):
        # состояние
        self.x = np.array([x0, y0, 0.0, 0.0], dtype=float)
        # ковариация состояния (начальная неопределённость по скорости велика)
        self.P = np.diag([4.0, 4.0, 500.0, 500.0]).astype(float)
        self._q = float(process_var)
        self.R = np.eye(2) * float(measurement_var)
        self.H = np.array([[1, 0, 0, 0], [0, 1, 0, 0]], dtype=float)

    def _F(self, dt: float) -> np.ndarray:
        return np.array([[1, 0, dt, 0],
                         [0, 1, 0, dt],
                         [0, 0, 1, 0],
                         [0, 0, 0, 1]], dtype=float)

    def _Q(self, dt: float) -> np.ndarray:
        # дискретная белошумная модель ускорения
        dt2 = dt * dt
        dt3 = dt2 * dt / 2.0
        dt4 = dt2 * dt2 / 4.0
        q = self._q
        return np.array([[dt4, 0, dt3, 0],
                         [0, dt4, 0, dt3],
                         [dt3, 0, dt2, 0],
                         [0, dt3, 0, dt2]], dtype=float) * q

    def predict(self, dt: float) -> np.ndarray:
        F = self._F(dt)
        self.x = F @ self.x
        self.P = F @ self.P @ F.T + self._Q(dt)
        return self.x.copy()

    def update(self, zx: float, zy: float) -> np.ndarray:
        z = np.array([zx, zy], dtype=float)
        y = z - self.H @ self.x
        S = self.H @ self.P @ self.H.T + self.R
        K = self.P @ self.H.T @ np.linalg.inv(S)
        self.x = self.x + K @ y
        self.P = (np.eye(4) - K @ self.H) @ self.P
        return self.x.copy()

    @property
    def position(self) -> tuple:
        return float(self.x[0]), float(self.x[1])

    @property
    def velocity(self) -> tuple:
        return float(self.x[2]), float(self.x[3])

    @property
    def speed(self) -> float:
        return float(np.hypot(self.x[2], self.x[3]))

    def predict_position(self, dt: float) -> tuple:
        """Экстраполяция положения на dt вперёд без изменения состояния."""
        return (float(self.x[0] + self.x[2] * dt),
                float(self.x[1] + self.x[3] * dt))
