"""Пересчёт координат цели из пикселей в углы наведения гимбала.

Модель камеры-обскуры: точка изображения (u, v) при внутренних параметрах
(fx, fy, cx, cy) соответствует угловому смещению относительно оптической оси

    ang_x = atan((u - cx) / fx)      # по горизонтали (азимут)
    ang_y = atan((v - cy) / fy)      # по вертикали   (возвышение)

Целевые углы гимбала = текущие углы + угловое смещение (+ поправка боресайта).
Знак по возвышению инвертирован: рост v (вниз по кадру) — уменьшение угла места.
"""
from __future__ import annotations

import math
from typing import Tuple

from ..config import CameraConfig, GimbalConfig


def angular_offset(u: float, v: float, cam: CameraConfig) -> Tuple[float, float]:
    """Угловое смещение точки (u, v) от оптической оси, в градусах.

    Возвращает (d_pan, d_tilt): d_pan>0 — цель правее центра, d_tilt>0 — выше.
    """
    ang_x = math.degrees(math.atan2(u - cam.cx, cam.fx))
    ang_y = math.degrees(math.atan2(v - cam.cy, cam.fy))
    return ang_x, -ang_y


def pixel_to_angles(u: float, v: float, cam: CameraConfig, gimbal: GimbalConfig,
                    cur_pan: float, cur_tilt: float) -> Tuple[float, float]:
    """Целевые углы (pan, tilt) в градусах для наведения оптоси на точку (u, v).

    Учитывает текущее положение гимбала, поправку боресайта и ограничения хода.
    """
    d_pan, d_tilt = angular_offset(u, v, cam)
    pan = cur_pan + d_pan + gimbal.boresight_offset_pan_deg
    tilt = cur_tilt + d_tilt + gimbal.boresight_offset_tilt_deg
    pan = _clamp(pan, gimbal.pan_min_deg, gimbal.pan_max_deg)
    tilt = _clamp(tilt, gimbal.tilt_min_deg, gimbal.tilt_max_deg)
    return pan, tilt


def angular_size(size_px: float, distance_px_equiv: float) -> float:
    """Угловой размер объекта (град) по его размеру в пикселях и фокусу (в пикс)."""
    return math.degrees(2.0 * math.atan2(size_px / 2.0, distance_px_equiv))


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)
