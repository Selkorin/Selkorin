"""Загрузка и валидация конфигурации системы.

Конфиг можно построить из словаря (:meth:`Config.from_dict`) — это позволяет
тестам работать без файла и без PyYAML. :func:`load_config` читает YAML-файл.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
from typing import Any, Dict, List


def _get(d: Dict[str, Any], key: str, default: Any) -> Any:
    v = d.get(key, default)
    return default if v is None else v


@dataclass
class PIDConfig:
    kp: float = 12.0
    ki: float = 6.0
    kd: float = 0.4
    out_limit: float = 120.0

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "PIDConfig":
        d = d or {}
        return cls(_get(d, "kp", 12.0), _get(d, "ki", 6.0),
                   _get(d, "kd", 0.4), _get(d, "out_limit", 120.0))


@dataclass
class CameraConfig:
    device: Any = 0
    width: int = 1280
    height: int = 720
    fps: int = 30
    fx: float = 1000.0
    fy: float = 1000.0
    cx: float = 640.0
    cy: float = 360.0

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "CameraConfig":
        d = d or {}
        return cls(
            _get(d, "device", 0), _get(d, "width", 1280), _get(d, "height", 720),
            _get(d, "fps", 30), _get(d, "fx", 1000.0), _get(d, "fy", 1000.0),
            _get(d, "cx", 640.0), _get(d, "cy", 360.0),
        )


@dataclass
class GimbalConfig:
    backend: str = "sim"
    serial_port: str = "/dev/ttyUSB0"
    baud: int = 115200
    pan_min_deg: float = -170.0
    pan_max_deg: float = 170.0
    tilt_min_deg: float = 0.0
    tilt_max_deg: float = 85.0
    max_speed_deg_s: float = 120.0
    boresight_offset_pan_deg: float = 0.0
    boresight_offset_tilt_deg: float = 0.0
    aim_tolerance_deg: float = 0.1
    pid_pan: PIDConfig = field(default_factory=PIDConfig)
    pid_tilt: PIDConfig = field(default_factory=PIDConfig)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "GimbalConfig":
        d = d or {}
        return cls(
            _get(d, "backend", "sim"), _get(d, "serial_port", "/dev/ttyUSB0"),
            _get(d, "baud", 115200),
            _get(d, "pan_min_deg", -170.0), _get(d, "pan_max_deg", 170.0),
            _get(d, "tilt_min_deg", 0.0), _get(d, "tilt_max_deg", 85.0),
            _get(d, "max_speed_deg_s", 120.0),
            _get(d, "boresight_offset_pan_deg", 0.0),
            _get(d, "boresight_offset_tilt_deg", 0.0),
            _get(d, "aim_tolerance_deg", 0.05),
            PIDConfig.from_dict(_get(d, "pid_pan", {})),
            PIDConfig.from_dict(_get(d, "pid_tilt", {})),
        )


@dataclass
class DetectClassConfig:
    min_area_px: float = 4.0
    max_area_px: float = 2000.0
    bg_history: int = 200
    bg_var_threshold: float = 24.0
    min_speed_px_s: float = 3.0

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "DetectClassConfig":
        d = d or {}
        return cls(
            _get(d, "min_area_px", 4.0), _get(d, "max_area_px", 2000.0),
            _get(d, "bg_history", 200), _get(d, "bg_var_threshold", 24.0),
            _get(d, "min_speed_px_s", 3.0),
        )


@dataclass
class DetectionConfig:
    drone: DetectClassConfig = field(default_factory=DetectClassConfig)
    insect: DetectClassConfig = field(
        default_factory=lambda: DetectClassConfig(1.0, 60.0, 100, 18.0, 20.0))

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "DetectionConfig":
        d = d or {}
        return cls(
            DetectClassConfig.from_dict(_get(d, "drone", {})),
            DetectClassConfig.from_dict(_get(d, "insect", {})),
        )


@dataclass
class TrackingConfig:
    max_track_age_frames: int = 15
    gate_px: float = 60.0
    min_hits_to_confirm: int = 3

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "TrackingConfig":
        d = d or {}
        return cls(
            _get(d, "max_track_age_frames", 15), _get(d, "gate_px", 60.0),
            _get(d, "min_hits_to_confirm", 3),
        )


@dataclass
class LaserModeConfig:
    power_pct: float = 100.0
    max_on_time_s: float = 30.0
    dwell_ms: float = 120.0
    max_range_m: float = 3.0

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "LaserModeConfig":
        d = d or {}
        return cls(
            _get(d, "power_pct", 100.0), _get(d, "max_on_time_s", 30.0),
            _get(d, "dwell_ms", 120.0), _get(d, "max_range_m", 3.0),
        )


@dataclass
class LaserConfig:
    backend: str = "sim"
    mark: LaserModeConfig = field(default_factory=LaserModeConfig)
    eliminate: LaserModeConfig = field(
        default_factory=lambda: LaserModeConfig(100.0, 30.0, 120.0, 3.0))

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "LaserConfig":
        d = d or {}
        return cls(
            _get(d, "backend", "sim"),
            LaserModeConfig.from_dict(_get(d, "mark", {})),
            LaserModeConfig.from_dict(_get(d, "eliminate", {})),
        )


@dataclass
class NoFireZone:
    """Угловая зона, в которой огонь ЗАПРЕЩЁН."""
    pan_min: float
    pan_max: float
    tilt_min: float
    tilt_max: float

    def contains(self, pan: float, tilt: float) -> bool:
        return (self.pan_min <= pan <= self.pan_max
                and self.tilt_min <= tilt <= self.tilt_max)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "NoFireZone":
        return cls(float(d["pan_min"]), float(d["pan_max"]),
                   float(d["tilt_min"]), float(d["tilt_max"]))


@dataclass
class SafetyConfig:
    require_key: bool = True
    watchdog_timeout_s: float = 0.5
    aim_tolerance_deg: float = 0.1
    no_fire_zones: List[NoFireZone] = field(default_factory=list)
    human_presence_interlock: bool = True
    ambient_lux_max_for_eliminate: float = 50.0
    max_range_m_for_eliminate: float = 3.0
    max_continuous_fire_s: float = 30.0
    laser_temp_max_c: float = 55.0

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "SafetyConfig":
        d = d or {}
        zones = [NoFireZone.from_dict(z) for z in _get(d, "no_fire_zones_deg", [])]
        return cls(
            _get(d, "require_key", True), _get(d, "watchdog_timeout_s", 0.5),
            _get(d, "aim_tolerance_deg", 0.1), zones,
            _get(d, "human_presence_interlock", True),
            _get(d, "ambient_lux_max_for_eliminate", 50.0),
            _get(d, "max_range_m_for_eliminate", 3.0),
            _get(d, "max_continuous_fire_s", 30.0),
            _get(d, "laser_temp_max_c", 55.0),
        )


@dataclass
class SystemConfig:
    name: str = "Selkorin Sky Sentinel"
    mode: str = "drone"

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "SystemConfig":
        d = d or {}
        return cls(_get(d, "name", "Selkorin Sky Sentinel"), _get(d, "mode", "drone"))


@dataclass
class Config:
    system: SystemConfig = field(default_factory=SystemConfig)
    camera: CameraConfig = field(default_factory=CameraConfig)
    gimbal: GimbalConfig = field(default_factory=GimbalConfig)
    detection: DetectionConfig = field(default_factory=DetectionConfig)
    tracking: TrackingConfig = field(default_factory=TrackingConfig)
    laser: LaserConfig = field(default_factory=LaserConfig)
    safety: SafetyConfig = field(default_factory=SafetyConfig)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Config":
        d = d or {}
        return cls(
            SystemConfig.from_dict(_get(d, "system", {})),
            CameraConfig.from_dict(_get(d, "camera", {})),
            GimbalConfig.from_dict(_get(d, "gimbal", {})),
            DetectionConfig.from_dict(_get(d, "detection", {})),
            TrackingConfig.from_dict(_get(d, "tracking", {})),
            LaserConfig.from_dict(_get(d, "laser", {})),
            SafetyConfig.from_dict(_get(d, "safety", {})),
        )

    def with_mode(self, mode: str) -> "Config":
        return replace(self, system=replace(self.system, mode=mode))


def load_config(path: str) -> Config:
    """Читает YAML-файл конфигурации и возвращает :class:`Config`."""
    import yaml  # локальный импорт: тестам YAML не нужен
    with open(path, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f) or {}
    return Config.from_dict(raw)
