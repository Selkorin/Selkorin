"""Управление лазером."""
from .laser import Laser, LaserBackend, SimLaserBackend, SerialLaserBackend, make_laser_backend

__all__ = ["Laser", "LaserBackend", "SimLaserBackend", "SerialLaserBackend",
           "make_laser_backend"]
