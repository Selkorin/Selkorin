"""Точка входа: запуск системы Selkorin Sky Sentinel.

Примеры:
  python -m dls --config config/system.yaml --sim --duration 15
  python -m dls --config config/system.yaml --mode insect --sim
  python -m dls --config config/system.yaml           # реальное оборудование
"""
from __future__ import annotations

import argparse
import sys
import time

from .config import Config, load_config
from .core import SensorInput, build_system
from .core.state import SystemState


def _load(args) -> Config:
    cfg = load_config(args.config) if args.config else Config()
    if args.mode:
        cfg = cfg.with_mode(args.mode)
    return cfg


def _run_sim(args) -> int:
    from .sim import run_sim
    cfg = _load(args)
    print(f"[СИМУЛЯЦИЯ] {cfg.system.name} | режим: {cfg.system.mode} | "
          f"{args.duration}s @ {args.fps} к/с\n")
    summary = run_sim(cfg, duration_s=args.duration, fps=args.fps, verbose=True)
    if summary.get("error"):
        print("Ошибка:", summary["error"])
        return 1
    return 0


def _run_hardware(args) -> int:
    """Основной цикл на реальном оборудовании (камера + контроллер осей)."""
    try:
        import cv2  # type: ignore
    except Exception:
        print("OpenCV не установлен: `pip install opencv-python` для работы с камерой.")
        return 1

    cfg = _load(args)
    orch = build_system(cfg)
    cap = cv2.VideoCapture(cfg.camera.device)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, cfg.camera.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, cfg.camera.height)
    if not cap.isOpened():
        print(f"Не удалось открыть камеру: {cfg.camera.device}")
        return 1

    print(f"[РАБОТА] {cfg.system.name} | режим: {cfg.system.mode}. Ctrl+C для выхода.")
    print("ВНИМАНИЕ: убедитесь, что E-STOP исправен и оператор в защитных очках "
          "(см. SAFETY.md).")
    if not orch.arm():
        print("Не удалось взвести систему: проверьте ключ взведения и E-STOP.")
        return 1

    last = time.monotonic()
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                print("Кадр не получен, остановка.")
                break
            now = time.monotonic()
            dt = max(1e-3, now - last)
            last = now
            # TODO: подставить реальные показания датчиков (E-STOP/ключ/lux/PIR/дальность)
            sensors = SensorInput()
            res = orch.step(frame, dt, sensors)
            if res.state in (SystemState.ENGAGE, SystemState.AIM):
                status = res.fire_mode if res.laser_on else "заблокирован"
                extra = "" if res.laser_on else " | " + "; ".join(res.safety_reasons)
                print(f"{res.state.value}: цель #{res.target_id} "
                      f"углы={res.target_angles} лазер={status}{extra}")
    except KeyboardInterrupt:
        print("\nОстановка по Ctrl+C.")
    finally:
        orch.disarm()
        orch.laser.close()
        cap.release()
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="dls", description="Selkorin Sky Sentinel — мониторинг неба и лазерное наведение")
    p.add_argument("--config", help="путь к YAML-конфигурации")
    p.add_argument("--mode", choices=["drone", "insect", "idle"],
                   help="переопределить режим работы")
    p.add_argument("--sim", action="store_true", help="запуск в симуляторе (без «железа»)")
    p.add_argument("--duration", type=float, default=15.0, help="длительность симуляции, с")
    p.add_argument("--fps", type=int, default=30, help="кадров в секунду")
    args = p.parse_args(argv)

    return _run_sim(args) if args.sim else _run_hardware(args)


if __name__ == "__main__":
    sys.exit(main())
