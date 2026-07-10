import math

from dls.config import CameraConfig, GimbalConfig
from dls.tracking.coordinates import angular_offset, pixel_to_angles


def _cam():
    return CameraConfig(fx=1000.0, fy=1000.0, cx=640.0, cy=360.0)


def test_center_has_zero_offset():
    d_pan, d_tilt = angular_offset(640.0, 360.0, _cam())
    assert abs(d_pan) < 1e-9
    assert abs(d_tilt) < 1e-9


def test_right_of_center_positive_pan():
    d_pan, _ = angular_offset(740.0, 360.0, _cam())
    assert d_pan > 0
    assert math.isclose(d_pan, math.degrees(math.atan2(100.0, 1000.0)), rel_tol=1e-6)


def test_above_center_positive_tilt():
    # точка выше центра (v < cy) -> положительный угол места
    _, d_tilt = angular_offset(640.0, 260.0, _cam())
    assert d_tilt > 0


def test_pixel_to_angles_adds_current_and_clamps():
    cam = _cam()
    g = GimbalConfig(pan_min_deg=-170, pan_max_deg=170,
                     tilt_min_deg=0, tilt_max_deg=85)
    pan, tilt = pixel_to_angles(740.0, 260.0, cam, g, cur_pan=10.0, cur_tilt=20.0)
    assert pan > 10.0        # цель правее -> азимут вырос
    assert tilt > 20.0       # цель выше -> угол места вырос
    # проверка ограничения хода
    pan_hi, tilt_hi = pixel_to_angles(100000.0, -100000.0, cam, g, 160.0, 80.0)
    assert pan_hi <= 170.0
    assert tilt_hi <= 85.0
