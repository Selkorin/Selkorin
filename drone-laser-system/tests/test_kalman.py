from dls.tracking.kalman import KalmanFilter2D


def test_tracks_constant_velocity():
    kf = KalmanFilter2D(0.0, 0.0)
    dt = 0.1
    vx, vy = 5.0, -3.0
    x = y = 0.0
    for _ in range(60):
        x += vx * dt
        y += vy * dt
        kf.predict(dt)
        kf.update(x, y)
    px, py = kf.position
    assert abs(px - x) < 1.0
    assert abs(py - y) < 1.0
    evx, evy = kf.velocity
    assert abs(evx - vx) < 0.5
    assert abs(evy - vy) < 0.5


def test_predict_position_extrapolates():
    kf = KalmanFilter2D(0.0, 0.0)
    dt = 0.1
    for i in range(30):
        kf.predict(dt)
        kf.update(2.0 * (i + 1), 0.0)   # vx = 20 px/s
    fx, _ = kf.predict_position(0.1)
    px, _ = kf.position
    assert fx > px    # экстраполяция вперёд по направлению движения


def test_speed_nonnegative_and_reasonable():
    kf = KalmanFilter2D(100.0, 100.0)
    for _ in range(20):
        kf.predict(0.1)
        kf.update(100.0, 100.0)   # неподвижная цель
    assert kf.speed < 1.0
