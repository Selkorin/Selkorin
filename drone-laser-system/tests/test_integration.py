"""Сквозной тест всего конвейера в симуляторе (без «железа»).

Прогоняет замкнутый контур: детектор → трекер → ego-компенсация → пересчёт
углов → PID гимбала → безопасность → лазер, и проверяет ключевые инварианты.
"""
from dls.config import Config
from dls.core import SensorInput, build_system
from dls.core.state import SystemState
from dls.sim import run_sim


def test_drone_pipeline_reaches_engage():
    cfg = Config().with_mode("drone")
    s = run_sim(cfg, duration_s=8.0, fps=30, verbose=False)
    assert s["reached_engage"], s["states"]
    assert "SEARCH" in s["states"]
    assert "TRACK" in s["states"]
    # E-STOP в середине прогона обязан дать кадры SAFE
    assert "SAFE" in s["states"]
    # при разрешённом огне привод действительно наведён (в пределах допуска)
    assert s["max_on_target_error_deg"] <= cfg.gimbal.aim_tolerance_deg + 1e-6


def test_insect_pipeline_reaches_engage():
    cfg = Config().with_mode("insect")
    s = run_sim(cfg, duration_s=10.0, fps=30, verbose=False)
    assert s["reached_engage"], s["states"]


def test_laser_off_under_estop():
    cfg = Config().with_mode("drone")
    orch = build_system(cfg)
    orch.safety.set_key(True)
    assert orch.arm()
    import numpy as np
    frame = np.zeros((cfg.camera.height, cfg.camera.width), dtype=np.uint8)
    res = orch.step(frame, 0.033, SensorInput(estop=True, key_present=True))
    assert res.state == SystemState.SAFE
    assert not res.laser_on
    assert not orch.laser.is_on


def test_no_target_stays_in_search():
    cfg = Config().with_mode("drone")
    orch = build_system(cfg)
    orch.safety.set_key(True)
    orch.arm()
    import numpy as np
    frame = np.full((cfg.camera.height, cfg.camera.width), 10, dtype=np.uint8)
    res = None
    for _ in range(5):
        res = orch.step(frame, 0.033, SensorInput(key_present=True))
    assert res.state == SystemState.SEARCH
    assert not res.laser_on
