"""Buttons screens react to (its own module so the status bar and primitives can share it)."""

from __future__ import annotations

from enum import Enum


class Button(Enum):
    """Buttons screens react to, mapped to PyUI controller inputs."""

    A = "A"
    B = "B"
    X = "X"
    Y = "Y"
    UP = "DPAD_UP"
    DOWN = "DPAD_DOWN"
    LEFT = "DPAD_LEFT"
    RIGHT = "DPAD_RIGHT"
    L1 = "L1"
    R1 = "R1"
    START = "START"
    SELECT = "SELECT"
