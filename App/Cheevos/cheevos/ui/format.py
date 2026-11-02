"""Formatting helpers for screens: points, dates, relative times, percentages, sizes.

Numbers, dates and plural forms follow the app's language (:mod:`cheevos.ui.language`).
"""

from __future__ import annotations

import time
from collections.abc import Callable

from cheevos.ui import language, strings

MINUTE = 60
HOUR = 60 * MINUTE
DAY = 24 * HOUR
_RELATIVE_DAYS = 7
_KIB = 1024
# (upper bound in seconds, unit in seconds, template) for relative times under a week. The
# templates are looked up when used: the language is applied after this module is imported.
_RELATIVE_STEPS: tuple[tuple[int, int, Callable[[], str | strings.Plural]], ...] = (
    (MINUTE, 1, lambda: strings.JUST_NOW),
    (HOUR, MINUTE, lambda: strings.MINUTES_AGO),
    (DAY, HOUR, lambda: strings.HOURS_AGO),
    (2 * DAY, DAY, lambda: strings.YESTERDAY),
)


def count(template: str | strings.Plural, value: int, **fields: object) -> str:
    """Format a template for ``value`` things, in the plural form the language uses for it.

    Args:
        template: A template with ``{count}``, or forms per plural category.
        value: The count, shown with thousands separators.
        **fields: The template's other fields.

    Returns:
        E.g. ``"1 event"``, ``"5 events"``.
    """
    if isinstance(template, strings.Plural):
        template = template.form(language.plural_category(value))
    return template.format(count=number(value), **fields)


def points(value: int) -> str:
    """Format achievement points: ``"1 pt"``, ``"5 pts"``.

    Args:
        value: Points.

    Returns:
        The label.
    """
    return count(strings.POINTS, value)


def number(value: int) -> str:
    """Format an integer with thousands separators.

    Args:
        value: The number.

    Returns:
        E.g. ``"12,843"``.
    """
    return f"{value:,}".replace(",", strings.THOUSANDS_SEPARATOR)


def decimal(value: float, places: int) -> str:
    """Format a number with a fixed count of decimals and the language's decimal separator.

    Args:
        value: The number.
        places: Decimals to show.

    Returns:
        E.g. ``"3.5"``.
    """
    return f"{value:.{places}f}".replace(".", strings.DECIMAL_SEPARATOR)


def local_datetime(epoch: int | None) -> str:
    """Format a UTC epoch as local ``"21 Aug 2026 19:02"`` (TZ comes from Spruce's setting).

    Args:
        epoch: Epoch seconds.

    Returns:
        The local time, or ``""`` for ``None``.
    """
    if not epoch:
        return ""
    when = time.localtime(epoch)
    return strings.DATETIME.format(
        date=local_date(epoch), time=f"{when.tm_hour:02d}:{when.tm_min:02d}"
    )


def local_date(epoch: int | None) -> str:
    """Format a UTC epoch as a local date, ``"21 Aug 2026"``.

    Args:
        epoch: Epoch seconds.

    Returns:
        The local date, or ``""`` for ``None``.
    """
    if not epoch:
        return ""
    when = time.localtime(epoch)
    month = strings.MONTHS[when.tm_mon - 1]
    return strings.DATE.format(day=when.tm_mday, month=month, year=when.tm_year)


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
            return count(template(), int(elapsed // unit))
    return count(strings.DAYS_AGO, int(elapsed // DAY))


def percent(fraction: float) -> str:
    """Format a 0-1 fraction as a percentage with sensible precision.

    Args:
        fraction: Share between 0 and 1.

    Returns:
        ``"41%"``, ``"3.5%"``, ``"0.4%"``.
    """
    value = max(fraction, 0.0) * 100
    places = 0 if value >= 10 or value == 0 else 1  # noqa: PLR2004
    return strings.PERCENT.format(percent=decimal(value, places))


def size(byte_count: int) -> str:
    """Format a byte count, e.g. ``"1.8 MB"``.

    Args:
        byte_count: Size in bytes.

    Returns:
        Human-readable size.
    """
    value = float(byte_count)
    *smaller, largest = strings.SIZE_UNITS
    for index, unit in enumerate(smaller):
        if value < _KIB:
            return strings.SIZE.format(value=decimal(value, 1 if index else 0), unit=unit)
        value /= _KIB
    return strings.SIZE.format(value=decimal(value, 1), unit=largest)
