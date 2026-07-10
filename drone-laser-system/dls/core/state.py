"""Состояния конечного автомата системы (см. docs/architecture.md)."""
from enum import Enum


class SystemState(str, Enum):
    BOOT = "BOOT"          # инициализация
    SELFTEST = "SELFTEST"  # самопроверка
    SAFE = "SAFE"          # безопасное состояние, лазер выключен
    SEARCH = "SEARCH"      # поиск цели
    TRACK = "TRACK"        # цель найдена, идёт наведение
    AIM = "AIM"            # наведён на цель, ожидание разрешения огня
    ENGAGE = "ENGAGE"      # активное воздействие (подсветка/уничтожение)
    FAULT = "FAULT"        # отказ, требуется вмешательство оператора
