"""Оркестратор: связывает обнаружение, сопровождение, наведение, безопасность и лазер.

На каждый кадр вызывается :meth:`Orchestrator.step`, который прогоняет один цикл
конечного автомата (см. :class:`~dls.core.state.SystemState`) и возвращает
:class:`StepResult` с полным снимком состояния для лога/визуализации.

Ключевой инвариант: лазер включается ТОЛЬКО после положительного решения
:class:`~dls.safety.SafetyManager.evaluate`.
"""
from __future__ import annotations

import math
import time
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Tuple

import numpy as np

from ..config import Config
from ..control import Gimbal, make_gimbal_hal
from ..control.hal import SerialLink
from ..detection import Detector
from ..laser import Laser, make_laser_backend
from ..safety import FireMode, FireRequest, SafetyManager
from ..tracking import Tracker, pixel_to_angles
from .state import SystemState


@dataclass
class StepResult:
    state: SystemState
    has_target: bool = False
    target_id: Optional[int] = None
    target_px: Optional[Tuple[float, float]] = None
    target_speed_px_s: float = 0.0
    target_angles: Optional[Tuple[float, float]] = None
    gimbal_angles: Tuple[float, float] = (0.0, 0.0)
    on_target: bool = False
    laser_on: bool = False
    fire_mode: Optional[str] = None
    safety_ok: bool = False
    safety_reasons: List[str] = field(default_factory=list)


@dataclass
class SensorInput:
    """Внешние показания датчиков/органов управления на такт."""
    estop: bool = False
    key_present: bool = True
    ambient_lux: float = 0.0
    human_present: bool = False
    laser_temp_c: float = 20.0
    target_range_m: Optional[float] = None   # оценка дальности (для режима eliminate)


class Orchestrator:
    def __init__(self, cfg: Config, detector: Detector, tracker: Tracker,
                 gimbal: Gimbal, laser: Laser, safety: SafetyManager,
                 clock: Callable[[], float] = time.monotonic):
        self.cfg = cfg
        self.detector = detector
        self.tracker = tracker
        self.gimbal = gimbal
        self.laser = laser
        self.safety = safety
        self._clock = clock
        self.state = SystemState.SAFE
        self._target_id: Optional[int] = None   # захваченная (удерживаемая) цель
        self._last_pose: Optional[Tuple[float, float]] = None  # для ego-компенсации

    # ------------------------------------------------------------------
    @property
    def mode(self) -> str:
        return self.cfg.system.mode

    @property
    def fire_mode(self) -> FireMode:
        return FireMode.ELIMINATE if self.mode == "insect" else FireMode.MARK

    @property
    def _min_speed(self) -> float:
        d = self.cfg.detection
        return d.insect.min_speed_px_s if self.mode == "insect" else d.drone.min_speed_px_s

    # ------------------------------------------------------------------
    def arm(self) -> bool:
        if self.safety.arm():
            self.gimbal.enable()
            self._target_id = None
            self._last_pose = None
            self.state = SystemState.SEARCH
            return True
        self.state = SystemState.SAFE
        return False

    def disarm(self) -> None:
        self.laser.off()
        self.gimbal.disable()
        self.safety.disarm()
        self._target_id = None
        self._last_pose = None
        self.state = SystemState.SAFE

    def _acquire_or_hold(self):
        """Возвращает активную цель: удерживает захваченную по id, иначе захватывает новую.

        Захват новой цели использует фильтр по скорости в кадре (отсекает
        неподвижные звёзды). Уже сопровождаемая цель удерживается по id, даже
        если после стабилизации её скорость в кадре упала почти до нуля.
        """
        if self._target_id is not None:
            for t in self.tracker.tracks:
                if t.id == self._target_id and t.confirmed:
                    return t
        target = self.tracker.select_target(self._min_speed)
        self._target_id = target.id if target else None
        return target

    # ------------------------------------------------------------------
    def step(self, frame: np.ndarray, dt: float,
             sensors: Optional[SensorInput] = None) -> StepResult:
        sensors = sensors or SensorInput()

        # 1) обновление входов безопасности + сброс watchdog (цикл жив)
        self.safety.set_estop(sensors.estop)
        self.safety.set_key(sensors.key_present)
        self.safety.update_sensors(sensors.ambient_lux, sensors.human_present,
                                   sensors.laser_temp_c)
        self.safety.ping()
        self.gimbal.hal.ping()

        # 2) аварийные условия -> SAFE
        if sensors.estop or not self.safety.armed:
            self.laser.off()
            self.tracker.reset()   # после паузы цель захватывается заново
            self._target_id = None
            self._last_pose = None
            self.state = SystemState.SAFE
            return StepResult(state=self.state, gimbal_angles=self.gimbal.angles)

        # 3) компенсация собственного движения камеры (привод повернулся между кадрами)
        cur_pan, cur_tilt = self.gimbal.angles
        if self._last_pose is not None:
            d_pan = cur_pan - self._last_pose[0]
            d_tilt = cur_tilt - self._last_pose[1]
            du = -self.cfg.camera.fx * math.tan(math.radians(d_pan))
            dv = self.cfg.camera.fy * math.tan(math.radians(d_tilt))
            self.tracker.shift(du, dv)
        self._last_pose = (cur_pan, cur_tilt)

        # 4) восприятие
        detections = self.detector.process(frame)
        self.tracker.update(detections, dt)
        target = self._acquire_or_hold()

        if target is None:
            self.laser.off()
            self.state = SystemState.SEARCH
            return StepResult(state=self.state, gimbal_angles=self.gimbal.angles)

        # 5) целеуказание: предсказываем положение вперёд на такт (компенсация задержки)
        px, py = target.kf.predict_position(dt)
        tgt_pan, tgt_tilt = pixel_to_angles(px, py, self.cfg.camera, self.cfg.gimbal,
                                            cur_pan, cur_tilt)

        # 6) наведение
        self.gimbal.aim(tgt_pan, tgt_tilt, dt)
        on_tgt = self.gimbal.is_on_target(tgt_pan, tgt_tilt)

        res = StepResult(
            state=SystemState.TRACK,
            has_target=True,
            target_id=target.id,
            target_px=(px, py),
            target_speed_px_s=target.speed,
            target_angles=(tgt_pan, tgt_tilt),
            gimbal_angles=self.gimbal.angles,
            on_target=on_tgt,
        )

        if not on_tgt:
            self.laser.off()
            self.state = SystemState.TRACK
            res.state = self.state
            return res

        # 7) на цели — запрос разрешения огня
        classification = "insect" if self.mode == "insect" else "drone"
        req = FireRequest(pan=tgt_pan, tilt=tgt_tilt, mode=self.fire_mode,
                          range_m=sensors.target_range_m, classification=classification)
        decision = self.safety.evaluate(req, continuous_fire_s=self.laser.on_time_s)

        res.safety_ok = decision.permitted
        res.safety_reasons = decision.reasons

        if decision.permitted:
            self.laser.fire(self.fire_mode, dt)
            self.state = SystemState.ENGAGE
        else:
            self.laser.off()
            self.state = SystemState.AIM   # наведён, но огонь заблокирован

        res.state = self.state
        res.laser_on = self.laser.is_on
        res.fire_mode = self.laser.mode.value if self.laser.mode else None
        return res


# ----------------------------------------------------------------------
def build_system(cfg: Config, link: Optional[SerialLink] = None,
                 clock: Callable[[], float] = time.monotonic) -> Orchestrator:
    """Собирает полную систему из конфигурации.

    При serial-backend'ах гимбал и лазер разделяют один :class:`SerialLink`.
    """
    if (cfg.gimbal.backend == "serial" or cfg.laser.backend == "serial") and link is None:
        link = SerialLink(cfg.gimbal.serial_port, cfg.gimbal.baud)

    det_cfg = cfg.detection.insect if cfg.system.mode == "insect" else cfg.detection.drone
    detector = Detector(det_cfg)
    tracker = Tracker(cfg.tracking)
    gimbal = Gimbal(cfg.gimbal, make_gimbal_hal(cfg.gimbal, link))
    laser = Laser(cfg.laser, make_laser_backend(cfg.laser, link))
    safety = SafetyManager(cfg.safety, clock=clock)
    return Orchestrator(cfg, detector, tracker, gimbal, laser, safety, clock=clock)
