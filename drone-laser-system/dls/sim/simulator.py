"""Синтетический стенд для проверки всего конвейера без камеры и приводов.

Ключевая особенность — физически корректная модель замкнутого контура:
камера установлена на приводе, поэтому положение цели В КАДРЕ зависит от
текущего наведения. Цель задаётся мировым направлением (азимут/угол места),
а её пиксельные координаты вычисляются проекцией относительно текущих углов
гимбала. Когда привод наводится на цель, она смещается к центру кадра — как
на реальном оборудовании.

Также в сцене есть неподвижные «звёзды» (статичный фон) — проверка того, что
детектор/трекер их отсеивают, а система захватывает именно движущийся объект.
"""
from __future__ import annotations

import math
from collections import Counter
from typing import Optional, Tuple

import numpy as np

from ..config import CameraConfig, Config
from ..core import SensorInput, build_system
from ..core.state import SystemState


class SyntheticScene:
    def __init__(self, cam: CameraConfig, mode: str = "drone", seed: int = 0):
        self.cam = cam
        self.w = cam.width
        self.h = cam.height
        self._rng = np.random.default_rng(seed)
        # неподвижные звёзды (в системе кадра) — статичный яркий фон
        self.stars = [(int(self._rng.integers(40, self.w - 40)),
                       int(self._rng.integers(20, self.h // 2)))
                      for _ in range(30)]
        # цель как мировое направление (град) и угловая скорость (град/с)
        if mode == "insect":
            self.az, self.el = -6.0, 8.0
            self.az_rate, self.el_rate = 8.0, 1.5
            self.radius = 2
        else:
            self.az, self.el = -8.0, 10.0
            self.az_rate, self.el_rate = 3.0, 0.8
            self.radius = 3
        self.brightness = 255

    def advance(self, dt: float) -> None:
        self.az += self.az_rate * dt
        self.el += self.el_rate * dt
        if self.az > 15.0 or self.az < -15.0:
            self.az_rate = -self.az_rate
        if self.el > 16.0 or self.el < 6.0:
            self.el_rate = -self.el_rate

    def project(self, pan: float, tilt: float) -> Tuple[float, float, float, float]:
        d_az = self.az - pan
        d_el = self.el - tilt
        u = self.cam.cx + self.cam.fx * math.tan(math.radians(d_az))
        v = self.cam.cy - self.cam.fy * math.tan(math.radians(d_el))
        return u, v, d_az, d_el

    def _disk(self, frame, cx, cy, r, val) -> None:
        x0, x1 = max(0, int(cx - r)), min(self.w, int(cx + r + 1))
        y0, y1 = max(0, int(cy - r)), min(self.h, int(cy + r + 1))
        for y in range(y0, y1):
            for x in range(x0, x1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    frame[y, x] = val

    def render(self, pan: float, tilt: float, dt: float):
        """Кадр, каким его видит камера при текущем наведении (pan, tilt)."""
        self.advance(dt)
        frame = (self._rng.normal(10, 3, (self.h, self.w)).clip(0, 255).astype(np.uint8))
        for sx, sy in self.stars:
            self._disk(frame, sx, sy, 1, 200)
        u, v, d_az, d_el = self.project(pan, tilt)
        visible = (0 <= u < self.w) and (0 <= v < self.h) and abs(d_az) < 80
        if visible:
            self._disk(frame, u, v, self.radius, self.brightness)
            return frame, (u, v)
        return frame, None


def run_sim(cfg: Config, duration_s: float = 15.0, fps: int = 30,
            verbose: bool = True) -> dict:
    """Прогоняет симуляцию замкнутого контура и возвращает сводку.

    В середине прогона кратко «нажимается» E-STOP — демонстрация немедленного
    перехода в SAFE, выключения лазера и повторного захвата после снятия.
    """
    mode = cfg.system.mode
    scene = SyntheticScene(cfg.camera, mode=mode)

    clock = {"t": 0.0}
    orch = build_system(cfg, clock=lambda: clock["t"])

    dt = 1.0 / fps
    n = int(duration_s * fps)
    estop_from, estop_to = int(n * 0.55), int(n * 0.62)

    orch.safety.set_key(True)               # оператор вставил ключ взведения
    if not orch.arm():
        return {"error": "не удалось взвести систему (проверьте ключ/E-STOP)"}

    states = Counter()
    engaged_frames = 0
    max_err = 0.0

    for i in range(n):
        clock["t"] += dt
        pan, tilt = orch.gimbal.angles
        frame, _ = scene.render(pan, tilt, dt)

        estop = estop_from <= i < estop_to
        sensors = SensorInput(
            estop=estop,
            key_present=True,
            ambient_lux=0.0,
            human_present=False,
            laser_temp_c=25.0,
            target_range_m=1.5 if mode == "insect" else None,
        )
        res = orch.step(frame, dt, sensors)

        if not orch.safety.armed and not estop:   # оператор снова взводит после E-STOP
            orch.arm()

        states[res.state.value] += 1
        if res.state == SystemState.ENGAGE:
            engaged_frames += 1
        if res.on_target and res.target_angles:
            max_err = max(max_err, orch.gimbal.aim_error(*res.target_angles))

        if verbose and (i % max(1, fps // 3) == 0 or estop):
            _print_status(i, dt, res)

    summary = {
        "mode": mode,
        "frames": n,
        "states": dict(states),
        "engaged_frames": engaged_frames,
        "reached_engage": engaged_frames > 0,
        "max_on_target_error_deg": round(max_err, 4),
    }
    if verbose:
        _print_summary(summary)
    return summary


def _print_status(i: int, dt: float, res) -> None:
    px = (f"({res.target_px[0]:6.1f},{res.target_px[1]:6.1f})"
          if res.target_px else "     -      ")
    ang = (f"pan={res.target_angles[0]:7.2f} tilt={res.target_angles[1]:6.2f}"
           if res.target_angles else "        -         ")
    laser = f"ЛАЗЕР:{res.fire_mode}" if res.laser_on else "лазер:off"
    reasons = ("  ⛔ " + "; ".join(res.safety_reasons)) if res.safety_reasons else ""
    print(f"t={i*dt:5.2f}s {res.state.value:7s} px={px} {ang}  {laser}{reasons}")


def _print_summary(s: dict) -> None:
    print("\n===== СВОДКА СИМУЛЯЦИИ =====")
    print(f"Режим: {s['mode']}   Кадров: {s['frames']}")
    print(f"Состояния: {s['states']}")
    print(f"Кадров воздействия (ENGAGE): {s['engaged_frames']}")
    print(f"Достигнут режим воздействия: {'ДА' if s['reached_engage'] else 'НЕТ'}")
    print(f"Макс. ошибка наведения при огне: {s['max_on_target_error_deg']}°")
    print("============================\n")
