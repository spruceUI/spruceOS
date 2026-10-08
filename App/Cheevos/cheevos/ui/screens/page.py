"""A page of rows of known height, scrolled with the D-pad a whole row at a time.

Scrolling by whole rows means nothing is ever drawn over the top or bottom bar, without any
clipping. A thin scrollbar on the right shows the position when the page doesn't fit.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass

from cheevos.ui.pyui import primitives as ui
from cheevos.ui.pyui.primitives import Button
from cheevos.ui.screens.common import PADDING

SCROLLBAR = 3  # scroll thumb width


@dataclass(frozen=True, slots=True)
class Row:
    """One slice of the page.

    Attributes:
        height: Height in pixels.
        draw: Draws the row with its top at the given y.
        heading: A section title: never left alone at the bottom of the page.
    """

    height: int
    draw: Callable[[int], None]
    heading: bool = False


def last_first(heights: Sequence[int], room: int) -> int:
    """Return the furthest useful scroll position: the last rows exactly fill the page.

    Args:
        heights: Row heights.
        room: Page height.

    Returns:
        The largest first-row index worth scrolling to.
    """
    used = 0
    for index in range(len(heights) - 1, -1, -1):
        used += heights[index]
        if used > room:
            return index + 1
    return 0


def clamp(first: int, rows: Sequence[Row], area: ui.Area) -> int:
    """Keep the scroll position within the page.

    Args:
        first: Requested first visible row.
        rows: All rows.
        area: Drawable area.

    Returns:
        The first visible row.
    """
    return max(min(first, last_first([row.height for row in rows], area.height)), 0)


def scroll(first: int, pressed: Button | None, rows: Sequence[Row] | None, room: int) -> int:
    """Move the scroll position for a button press (up/down: a row, L1/R1: a screenful).

    L1/R1 keep one row in view, like PyUI's lists: R1 brings the last visible row to the top,
    L1 the first visible row to the bottom. How many rows that is depends on the screen.

    Args:
        first: Current first visible row.
        pressed: The button, or ``None``.
        rows: All rows (for their heights), or ``None`` while they're being rebuilt.
        room: Page height in pixels.

    Returns:
        The new first row (not yet clamped to the end; :func:`clamp` does that).
    """
    heights = [row.height for row in rows or []]
    if pressed is Button.R1:
        return first + max(_fitting(heights[first:], room) - 1, 1)
    if pressed is Button.L1:
        return max(first - max(_fitting(heights[first::-1], room) - 1, 1), 0)
    step = {Button.UP: -1, Button.DOWN: 1}.get(pressed, 0) if pressed else 0
    return max(first + step, 0)


def _fitting(heights: Sequence[int], room: int) -> int:
    """Return how many rows, from the first given, fit in ``room`` (at least one).

    Args:
        heights: Row heights, in the order they would be stacked.
        room: Page height in pixels.

    Returns:
        The number of rows.
    """
    used = 0
    for count, height in enumerate(heights):
        used += height
        if used > room:
            return max(count, 1)
    return max(len(heights), 1)


def draw(rows: Sequence[Row], first: int, area: ui.Area) -> None:
    """Draw the rows that fit from ``first`` (a heading only with its next row), then the bar.

    Args:
        rows: All rows.
        first: First visible row.
        area: Drawable area.
    """
    y, bottom = area.y, area.y + area.height
    visible = rows[first:]
    for index, row in enumerate(visible):
        following = visible[index + 1].height if row.heading and index + 1 < len(visible) else 0
        if y + row.height + following > bottom:
            break
        row.draw(y)
        y += row.height
    _scrollbar([row.height for row in rows], first, area)


def _scrollbar(heights: Sequence[int], first: int, area: ui.Area) -> None:
    """Draw a thin scroll thumb on the right edge when the page doesn't fit.

    Args:
        heights: Row heights.
        first: First visible row.
        area: Drawable area.
    """
    total = sum(heights)
    if total <= area.height:
        return
    thumb = max(area.height * area.height // total, PADDING)
    offset = sum(heights[:first]) * (area.height - thumb) // max(total - area.height, 1)
    x = area.width - SCROLLBAR - 2
    ui.box(ui.chart_color(), x, area.y + min(offset, area.height - thumb), SCROLLBAR, thumb)
