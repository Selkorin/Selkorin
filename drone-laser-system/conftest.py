"""Делает пакет ``dls`` импортируемым при запуске pytest из этой директории."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
