from dls.config import TrackingConfig
from dls.detection.types import Detection
from dls.tracking import Tracker


def _det(x, y, area=20.0):
    return Detection(cx=x, cy=y, area=area, x=int(x), y=int(y), w=4, h=4)


def test_confirms_and_selects_moving_target():
    trk = Tracker(TrackingConfig(max_track_age_frames=15, gate_px=60,
                                 min_hits_to_confirm=3))
    dt = 0.033
    x, y = 100.0, 100.0
    tgt = None
    for _ in range(10):
        x += 4.0    # движется вправо
        trk.update([_det(x, y)], dt)
        tgt = trk.select_target(min_speed_px_s=3.0)
    assert tgt is not None
    assert tgt.confirmed
    assert tgt.speed > 3.0


def test_stationary_target_filtered_by_speed():
    trk = Tracker(TrackingConfig(min_hits_to_confirm=3, gate_px=60))
    for _ in range(10):
        trk.update([_det(200.0, 200.0)], 0.033)   # неподвижно
    # трек подтверждён, но по скорости не проходит фильтр цели
    assert trk.select_target(min_speed_px_s=5.0) is None


def test_track_ages_out_when_lost():
    trk = Tracker(TrackingConfig(max_track_age_frames=3, gate_px=60,
                                 min_hits_to_confirm=2))
    for _ in range(4):
        trk.update([_det(50.0, 50.0)], 0.033)
    assert len(trk.tracks) >= 1
    for _ in range(6):
        trk.update([], 0.033)   # цель пропала
    assert len(trk.tracks) == 0
