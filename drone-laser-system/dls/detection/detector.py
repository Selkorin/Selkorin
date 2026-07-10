"""Детектор движущихся объектов на кадре ночного неба.

Работает поверх OpenCV (вычитание фона MOG2), а при его отсутствии — на
чистом numpy (фон как экспоненциальное скользящее среднее). Это позволяет
прогонять весь конвейер в симуляторе и в тестах без установки OpenCV.

Детектор отсекает шум и статичные объекты (звёзды) по площади; фильтрация
по скорости выполняется выше — в трекере, где известна история объекта.
"""
from __future__ import annotations

from typing import List

import numpy as np

from ..config import DetectClassConfig
from .types import Detection

try:  # OpenCV опционален
    import cv2  # type: ignore
    _HAVE_CV2 = True
except Exception:  # pragma: no cover - зависит от окружения
    cv2 = None  # type: ignore
    _HAVE_CV2 = False


def _to_gray(frame: np.ndarray) -> np.ndarray:
    """Приводит кадр к 8-битному полутоновому 2D-массиву."""
    arr = np.asarray(frame)
    if arr.ndim == 3:
        arr = arr.mean(axis=2)
    if arr.dtype != np.uint8:
        arr = np.clip(arr, 0, 255).astype(np.uint8)
    return arr


def _connected_components(mask: np.ndarray):
    """Простая 4-связная разметка компонент по булевой маске (numpy-fallback).

    Рассчитана на разреженную маску (несколько небольших ярких пятен), как
    в задаче обнаружения точечных целей на тёмном небе.
    """
    h, w = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    comps = []
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if visited[sy, sx]:
            continue
        stack = [(sy, sx)]
        visited[sy, sx] = True
        pts = []
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    stack.append((ny, nx))
        comps.append(pts)
    return comps


class Detector:
    """Обнаружитель целей заданного класса (drone/insect)."""

    def __init__(self, cfg: DetectClassConfig):
        self.cfg = cfg
        if _HAVE_CV2:
            self._bg = cv2.createBackgroundSubtractorMOG2(
                history=int(cfg.bg_history),
                varThreshold=float(cfg.bg_var_threshold),
                detectShadows=False,
            )
        else:
            self._bg_mean = None  # экспоненциальное среднее фона
            self._alpha = 1.0 / max(1.0, float(cfg.bg_history))

    # ------------------------------------------------------------------
    def process(self, frame: np.ndarray) -> List[Detection]:
        gray = _to_gray(frame)
        mask = self._foreground(gray)
        return self._extract(mask, gray)

    # ------------------------------------------------------------------
    def _foreground(self, gray: np.ndarray) -> np.ndarray:
        if _HAVE_CV2:
            fg = self._bg.apply(gray)
            _, mask = cv2.threshold(fg, 200, 255, cv2.THRESH_BINARY)
            kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
            mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
            return mask > 0
        # numpy-fallback
        g = gray.astype(np.float32)
        if self._bg_mean is None:
            self._bg_mean = g.copy()
            return np.zeros(gray.shape, dtype=bool)
        diff = g - self._bg_mean
        # порог: значимо ярче фона (движущийся яркий объект на тёмном небе)
        thr = max(float(self.cfg.bg_var_threshold), 12.0)
        mask = diff > thr
        # обновление фона (медленнее там, где нет переднего плана)
        self._bg_mean += self._alpha * (g - self._bg_mean) * (~mask)
        return mask

    # ------------------------------------------------------------------
    def _extract(self, mask: np.ndarray, gray: np.ndarray) -> List[Detection]:
        dets: List[Detection] = []
        if _HAVE_CV2:
            m = (mask.astype(np.uint8)) * 255
            contours, _ = cv2.findContours(m, cv2.RETR_EXTERNAL,
                                           cv2.CHAIN_APPROX_SIMPLE)
            for c in contours:
                area = float(cv2.contourArea(c))
                if area < 1:
                    area = float(len(c))
                if not (self.cfg.min_area_px <= area <= self.cfg.max_area_px):
                    continue
                x, y, w, h = cv2.boundingRect(c)
                cx, cy = x + w / 2.0, y + h / 2.0
                roi = gray[y:y + h, x:x + w]
                dets.append(Detection(cx, cy, area, x, y, w, h,
                                      float(roi.mean()) if roi.size else 0.0))
            return dets

        for pts in _connected_components(mask):
            area = float(len(pts))
            if not (self.cfg.min_area_px <= area <= self.cfg.max_area_px):
                continue
            ys = [p[0] for p in pts]
            xs = [p[1] for p in pts]
            x, y = min(xs), min(ys)
            w, h = max(xs) - x + 1, max(ys) - y + 1
            cx = sum(xs) / len(xs)
            cy = sum(ys) / len(ys)
            roi = gray[y:y + h, x:x + w]
            dets.append(Detection(cx, cy, area, x, y, w, h,
                                  float(roi.mean()) if roi.size else 0.0))
        return dets
