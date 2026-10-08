"""Formatting helpers for screens: points, dates, relative times, percentages, sizes."""

from __future__ import annotations

import time

from cheevos.ui import strings

MINUTE = 60
HOUR = 60 * MINUTE
DAY = 24 * HOUR
_RELATIVE_DAYS = 7
_KIB = 1024
# (upper bound in seconds, unit in seconds, template) for relative times under a week.
_RELATIVE_STEPS = (
    (MINUTE, 1, strings.JUST_NOW),
    (HOUR, MINUTE, strings.MINUTES_AGO),
    (DAY, HOUR, strings.HOURS_AGO),
    (2 * DAY, DAY, strings.YESTERDAY),
)


def points(count: int) -> str:
    """Format achievement points: ``"1 pt"``, ``"5 pts"``.

    Args:
        count: Points.

    Returns:
        The label.
    """
    template = strings.POINT if count == 1 else strings.POINTS
    return template.format(count=count)


def number(value: int) -> str:
    """Format an integer with thousands separators.

    Args:
        value: The number.

    Returns:
        E.g. ``"12,843"``.
    """
    return f"{value:,}"


def local_datetime(epoch: int | None) -> str:
    """Format a UTC epoch as local ``"21 Aug 2026 19:02"`` (TZ comes from Spruce's setting).

    Args:
        epoch: Epoch seconds.

    Returns:
        The local time, or ``""`` for ``None``.
    """
    return time.strftime("%d %b %Y %H:%M", time.localtime(epoch)) if epoch else ""


def local_date(epoch: int | None) -> str:
    """Format a UTC epoch as a local date, ``"21 Aug 2026"``.

    Args:
        epoch: Epoch seconds.

    Returns:
        The local date, or ``""`` for ``None``.
    """
    return time.strftime("%d %b %Y", time.localtime(epoch)) if epoch else ""


def ago(epoch: int | None, now: float) -> str:
    """Describe how long ago something happened, falling back to a date after a week.

    Args:
        epoch: Event time (epoch seconds).
        now: Current time.

    Returns:
        E.g. ``"just now"``, ``"5 min ago"``, ``"3 h ago"``, ``"yesterday"``, ``"12 Aug 2026"``.
    """
    if not epoch:
        return ""
    elapsed = max(now - epoch, 0)
    if elapsed >= _RELATIVE_DAYS * DAY:
        return local_date(epoch)
    for limit, unit, template in _RELATIVE_STEPS:
        if elapsed < limit:
            return template.format(count=int(elapsed // unit))
    return strings.DAYS_AGO.format(count=int(elapsed // DAY))


def percent(fraction: float) -> str:
    """Format a 0-1 fraction as a percentage with sensible precision.

    Args:
        fraction: Share between 0 and 1.

    Returns:
        ``"41%"``, ``"3.5%"``, ``"0.4%"``.
    """
    value = max(fraction, 0.0) * 100
    return f"{value:.0f}%" if value >= 10 or value == 0 else f"{value:.1f}%"  # noqa: PLR2004


def size(byte_count: int) -> str:
    """Format a byte count, e.g. ``"1.8 MB"``.

    Args:
        byte_count: Size in bytes.

    Returns:
        Human-readable size.
    """
    value = float(byte_count)
    for unit in ("B", "KB", "MB"):
        if value < _KIB:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= _KIB
    return f"{value:.1f} GB"
