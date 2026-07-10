"""Многоцелевой трекер с ассоциацией «ближайший в окне» и фильтром Калмана.

Каждый трек сглаживается своим :class:`KalmanFilter2D`. Трек считается
подтверждённым после нескольких последовательных попаданий; это отсекает
шумовые ложные срабатывания. Скорость трека используется для отсечения
статичных объектов (звёзд): у них скорость близка к нулю.
"""
from __future__ import annotations

import math
from typing import List, Optional, Sequence

from ..config import TrackingConfig
from ..detection.types import Detection
from .kalman import KalmanFilter2D


class Track:
    _next_id = 1

    def __init__(self, det: Detection):
        self.id = Track._next_id
        Track._next_id += 1
        self.kf = KalmanFilter2D(det.cx, det.cy)
        self.hits = 1
        self.misses = 0
        self.age = 1
        self.area = det.area
        self.confirmed = False

    @property
    def position(self):
        return self.kf.position

    @property
    def speed(self):
        return self.kf.speed

    def predict(self, dt: float):
        self.kf.predict(dt)
        self.age += 1

    def correct(self, det: Detection):
        self.kf.update(det.cx, det.cy)
        self.hits += 1
        self.misses = 0
        # сглаженная площадь
        self.area = 0.7 * self.area + 0.3 * det.area

    def mark_missed(self):
        self.misses += 1


class Tracker:
    def __init__(self, cfg: TrackingConfig):
        self.cfg = cfg
        self.tracks: List[Track] = []

    def reset(self) -> None:
        """Сбрасывает все треки (после E-STOP/паузы — цель захватывается заново)."""
        self.tracks = []

    def shift(self, du: float, dv: float) -> None:
        """Сдвигает позиции всех треков в кадре (компенсация движения камеры).

        Камера установлена на приводе; при повороте привода неподвижная в мире
        цель смещается в кадре. Сдвиг треков на соответствующую величину
        сохраняет корректную ассоциацию детекций между кадрами.
        """
        for t in self.tracks:
            t.kf.x[0] += du
            t.kf.x[1] += dv

    def update(self, detections: Sequence[Detection], dt: float) -> List[Track]:
        # 1) предсказание
        for t in self.tracks:
            t.predict(dt)

        # 2) жадная ассоциация по минимальному расстоянию в пределах gate
        unmatched = list(range(len(detections)))
        gate = self.cfg.gate_px
        for t in sorted(self.tracks, key=lambda tr: tr.misses):
            best_j, best_d = -1, gate
            tx, ty = t.position
            for j in unmatched:
                d = detections[j]
                dist = math.hypot(d.cx - tx, d.cy - ty)
                if dist < best_d:
                    best_d, best_j = dist, j
            if best_j >= 0:
                t.correct(detections[best_j])
                unmatched.remove(best_j)
            else:
                t.mark_missed()

        # 3) новые треки из непривязанных детекций
        for j in unmatched:
            self.tracks.append(Track(detections[j]))

        # 4) подтверждение и удаление устаревших
        for t in self.tracks:
            if not t.confirmed and t.hits >= self.cfg.min_hits_to_confirm:
                t.confirmed = True
        self.tracks = [t for t in self.tracks
                       if t.misses <= self.cfg.max_track_age_frames]
        return self.tracks

    def confirmed_tracks(self, min_speed_px_s: float = 0.0) -> List[Track]:
        return [t for t in self.tracks
                if t.confirmed and t.speed >= min_speed_px_s]

    def select_target(self, min_speed_px_s: float = 0.0) -> Optional[Track]:
        """Выбирает приоритетную цель: подтверждённую, движущуюся, наиболее «живую».

        Приоритет — по числу попаданий (устойчивость трека), затем по площади.
        """
        candidates = self.confirmed_tracks(min_speed_px_s)
        if not candidates:
            return None
        return max(candidates, key=lambda t: (t.hits, t.area))
