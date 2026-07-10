"""Типы данных слоя обнаружения."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Detection:
    """Один обнаруженный объект на кадре (координаты в пикселях)."""
    cx: float          # центр по горизонтали
    cy: float          # центр по вертикали
    area: float        # площадь, пикс²
    x: int             # bbox: левый край
    y: int             # bbox: верхний край
    w: int             # bbox: ширина
    h: int             # bbox: высота
    intensity: float = 0.0   # средняя яркость области (0..255)

    @property
    def bbox(self) -> tuple:
        return (self.x, self.y, self.w, self.h)
