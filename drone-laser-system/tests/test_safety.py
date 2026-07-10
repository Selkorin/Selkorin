from dls.config import NoFireZone, SafetyConfig
from dls.safety import FireMode, FireRequest, SafetyManager


def _clock():
    t = {"v": 0.0}
    return t, (lambda: t["v"])


def _mgr(**over):
    cfg = SafetyConfig(
        require_key=True,
        watchdog_timeout_s=0.5,
        no_fire_zones=[NoFireZone(-180, 180, -90, 0)],   # ниже горизонта запрещено
        human_presence_interlock=True,
        ambient_lux_max_for_eliminate=50.0,
        max_range_m_for_eliminate=3.0,
        max_continuous_fire_s=30.0,
        laser_temp_max_c=55.0,
    )
    for k, v in over.items():
        setattr(cfg, k, v)
    t, clk = _clock()
    m = SafetyManager(cfg, clock=clk)
    m.set_key(True)   # по умолчанию считаем ключ вставленным
    return m, t


def _mark_req(pan=0.0, tilt=30.0):
    return FireRequest(pan=pan, tilt=tilt, mode=FireMode.MARK, classification="drone")


def test_denied_when_not_armed():
    m, _ = _mgr()
    assert not m.evaluate(_mark_req())


def test_armed_mark_above_horizon_permitted():
    m, _ = _mgr()
    assert m.arm()
    assert m.evaluate(_mark_req(tilt=30.0)).permitted


def test_below_horizon_denied():
    m, _ = _mgr()
    m.arm()
    d = m.evaluate(_mark_req(tilt=-5.0))
    assert not d.permitted
    assert any("запрета" in r for r in d.reasons)


def test_estop_denies_and_disarms():
    m, _ = _mgr()
    m.arm()
    m.set_estop(True)
    d = m.evaluate(_mark_req())
    assert not d.permitted
    assert not m.armed


def test_no_key_blocks_arm():
    m, _ = _mgr()
    m.set_key(False)
    assert not m.arm()
    assert not m.evaluate(_mark_req()).permitted


def test_watchdog_timeout_denies():
    m, t = _mgr()
    m.arm()
    t["v"] += 1.0    # прошло больше watchdog_timeout_s
    d = m.evaluate(_mark_req())
    assert not d.permitted
    assert any("watchdog" in r for r in d.reasons)


def test_thermal_limit_denies():
    m, _ = _mgr()
    m.arm()
    m.update_sensors(laser_temp_c=80.0)
    assert not m.evaluate(_mark_req()).permitted


def test_continuous_fire_limit_denies():
    m, _ = _mgr()
    m.arm()
    assert not m.evaluate(_mark_req(), continuous_fire_s=45.0).permitted


def test_eliminate_requires_all_conditions():
    m, _ = _mgr()
    m.arm()
    good = FireRequest(pan=0, tilt=30, mode=FireMode.ELIMINATE,
                       range_m=1.5, classification="insect")
    m.update_sensors(ambient_lux=0.0, human_present=False)
    assert m.evaluate(good).permitted

    # человек в секторе -> запрет
    m.update_sensors(human_present=True)
    assert not m.evaluate(good).permitted
    m.update_sensors(human_present=False)

    # слишком далеко -> не ближняя зона
    far = FireRequest(pan=0, tilt=30, mode=FireMode.ELIMINATE,
                      range_m=10.0, classification="insect")
    assert not m.evaluate(far).permitted

    # неверная классификация -> запрет
    wrong = FireRequest(pan=0, tilt=30, mode=FireMode.ELIMINATE,
                        range_m=1.5, classification="drone")
    assert not m.evaluate(wrong).permitted

    # яркий свет -> вне защищённой зоны
    m.update_sensors(ambient_lux=500.0)
    assert not m.evaluate(good).permitted


def test_mark_does_not_require_range_or_insect():
    # режим подсветки дрона не требует дальности/классификации «насекомое»
    m, _ = _mgr()
    m.arm()
    req = FireRequest(pan=0, tilt=45, mode=FireMode.MARK, classification="drone")
    assert m.evaluate(req).permitted
