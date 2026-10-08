"""Pure layout of the bottom-bar content: a status (icon and text) followed by button hints.

No PyUI or SDL here: widths come in as numbers and through ``measure``/``fit`` callables, so
the arithmetic is unit-tested on its own.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass

ICON_GAP = 6  # between an icon or glyph and its text
ITEM_GAP = 16  # between the status and a hint, and between hints


@dataclass(frozen=True, slots=True)
class Metrics:
    """Space available in the bar.

    Attributes:
        width: Screen width.
        left: First free x after the theme's own hints.
        right: Last free x before the index text.
        centred: The theme hides its hints: centre the content on the screen.
        icon: Status icon width (0: none).
    """

    width: int
    left: int
    right: int
    centred: bool
    icon: int


@dataclass(frozen=True, slots=True)
class HintSize:
    """A button hint to place.

    Attributes:
        glyph: Button glyph width (0: no glyph; the label names the button).
        label: What the button does, e.g. "Sync".
    """

    glyph: int
    label: str


@dataclass(frozen=True, slots=True)
class PlacedHint:
    """A placed hint (left edges; everything is vertically centred).

    Attributes:
        index: Position in the requested hints.
        glyph_x: Button glyph, or ``None``.
        label: Hint label.
        label_x: Hint label.
    """

    index: int
    glyph_x: int | None
    label: str
    label_x: int


@dataclass(frozen=True, slots=True)
class Placement:
    """Where each part goes (left edges; everything is vertically centred).

    Attributes:
        icon_x: Status icon, or ``None``.
        text: Fitted status text (empty when there is no room).
        text_x: Status text.
        hints: Placed hints, in order (trailing ones are dropped when they don't fit).
    """

    icon_x: int | None
    text: str
    text_x: int
    hints: tuple[PlacedHint, ...]


def _hints_width(hints: Sequence[HintSize], measure: Callable[[str], int]) -> int:
    """Total width of hints laid out one after another.

    Args:
        hints: Hints.
        measure: Text width in pixels.

    Returns:
        Width in pixels.
    """
    parts = [(hint.glyph + ICON_GAP if hint.glyph else 0) + measure(hint.label) for hint in hints]
    return sum(parts) + ITEM_GAP * max(len(parts) - 1, 0)


def place(
    text: str,
    *,
    icon: bool,
    hints: Sequence[HintSize],
    metrics: Metrics,
    measure: Callable[[str], int],
    fit: Callable[[str, int], str],
) -> Placement | None:
    """Lay out the status and hints between the theme's hints and the index text.

    Hints win over the status text: the text is shortened (or dropped) to make room, and
    trailing hints are dropped only when they don't fit next to the status icon.

    Args:
        text: Status text (may be empty).
        icon: The status has an icon.
        hints: Button hints, most important first.
        metrics: Available space.
        measure: Text width in pixels.
        fit: Shortens text to a pixel width.

    Returns:
        The placement, or ``None`` when there is nothing to show or no room.
    """
    icon_width = metrics.icon if icon else 0
    room = metrics.right - metrics.left
    kept = list(hints)
    while kept:
        joint = ITEM_GAP if icon_width else 0
        if icon_width + joint + _hints_width(kept, measure) <= room:
            break
        kept.pop()
    if icon_width > room:
        return None
    used = _hints_width(kept, measure)
    lead = icon_width + ICON_GAP if icon_width else 0
    text_room = room - lead - used - (ITEM_GAP if kept else 0)
    shown = fit(text, text_room) if text and text_room > 0 else ""
    if not shown.rstrip(".…").strip():  # nothing left but an ellipsis
        shown = ""
    status = (lead if shown else icon_width) + (measure(shown) if shown else 0)
    joint = ITEM_GAP if status and kept else 0
    total = status + joint + used
    if total == 0:
        return None
    x = metrics.left
    if metrics.centred:
        x = max(metrics.left, min((metrics.width - total) // 2, metrics.right - total))
    cursor = x + status + joint
    placed = []
    for index, hint in enumerate(kept):
        label_x = cursor + (hint.glyph + ICON_GAP if hint.glyph else 0)
        placed.append(PlacedHint(index, cursor if hint.glyph else None, hint.label, label_x))
        cursor = label_x + measure(hint.label) + ITEM_GAP
    return Placement(x if icon_width else None, shown, x + lead, tuple(placed))
