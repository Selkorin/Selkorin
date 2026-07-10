from dls.config import PIDConfig
from dls.control.pid import PID


def test_output_clamped():
    pid = PID(PIDConfig(kp=100.0, ki=0.0, kd=0.0, out_limit=5.0))
    out = pid.step(error=1000.0, dt=0.1)
    assert -5.0 <= out <= 5.0
    assert out == 5.0


def test_proportional_sign():
    pid = PID(PIDConfig(kp=1.0, ki=0.0, kd=0.0, out_limit=100.0))
    assert pid.step(2.0, 0.1) > 0
    pid.reset()
    assert pid.step(-2.0, 0.1) < 0


def test_anti_windup_bounds_integral():
    # при постоянном насыщении интеграл не должен накапливаться безгранично
    pid = PID(PIDConfig(kp=0.0, ki=10.0, kd=0.0, out_limit=1.0))
    for _ in range(100):
        pid.step(5.0, 0.1)
    # выход остаётся ограниченным
    assert abs(pid.step(5.0, 0.1)) <= 1.0


def test_zero_dt_returns_zero():
    pid = PID(PIDConfig(kp=1.0))
    assert pid.step(10.0, 0.0) == 0.0


def test_converges_to_setpoint():
    # интегрирующая модель (позиция = интеграл выхода): P-регулятор
    # обеспечивает нулевую установившуюся ошибку по ступенчатому входу
    pid = PID(PIDConfig(kp=2.0, ki=0.0, kd=0.0, out_limit=50.0))
    pos, target, dt = 0.0, 10.0, 0.05
    for _ in range(500):
        pos += pid.step(target - pos, dt) * dt
    assert abs(target - pos) < 0.05
