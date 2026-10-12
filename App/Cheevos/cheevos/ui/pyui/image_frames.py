"""Draw badge outlines outside the artwork, including on bright themes (.agents/pyui.md)."""

from __future__ import annotations

import functools
import logging
from enum import Enum
from typing import Any

from cheevos.ui.pyui import generated
from cheevos.ui.pyui.bar_colors import BLACK, GOLD, RGB, WHITE, ZINC_300, ZINC_400
from cheevos.ui.pyui.visible_images import image_version

logger = logging.getLogger(__name__)

_LINE_SHARE = 1 / 32  # 2 px at RA's 64 px badge size, 3 px at the 96 px game icon size
_ICON_SHARE = 0.125  # DescriptiveListView's icon column
Bounds = tuple[int, int, int, int]


class Frame(Enum):
    """Image borders shared by achievements and the awards wall, and the badge grid's focus."""

    GOLD = "gold"
    SILVER = "silver"
    SILVER_THIN = "silver-thin"
    # The badge grid's selection: a white ring with room inside for a gold frame drawn after it.
    FOCUS = "focus"


def draw(frame: Frame, bounds: Bounds) -> None:
    """Outline an image without covering its pixels.

    A black outer edge keeps gold recognisable on light or gold theme backgrounds, without
    replacing its colour with the theme's text colour. One transparent PNG per style and
    rendered size is shared by every badge, so subsequent frames make one texture draw.

    Args:
        frame: Border style.
        bounds: Actual rendered image's ``(left, top, width, height)``.
    """
    from display.display import Display

    x, y, width, height = bounds
    if width <= 0 or height <= 0:
        return
    path, padding = _image(frame, width, height)
    Display.render_image(path, x - padding, y - padding)


def padding(frame: Frame, width: int, height: int) -> int:
    """Return how far a frame reaches outside the image on each side.

    Args:
        frame: Border style.
        width: Image width.
        height: Image height.

    Returns:
        Pixels outside each edge.
    """
    return sum(thickness for _color, thickness in _bands(frame, width, height))


def _bands(frame: Frame, width: int, height: int) -> tuple[tuple[RGB, int], ...]:
    """Return a frame's bands from the outside in: colour and thickness.

    Every style has a 1 px black outer edge. The focus ring's inner black band is exactly
    a gold frame's size, so a gold frame drawn after it fits inside the white ring.

    Args:
        frame: Border style.
        width: Image width.
        height: Image height.

    Returns:
        The bands.
    """
    line = max(round(min(width, height) * _LINE_SHARE), 2)
    if frame is Frame.FOCUS:
        return ((BLACK, 1), (WHITE, line), (BLACK, line + 1))
    if frame is Frame.SILVER_THIN:
        return ((BLACK, 1), (ZINC_400, max(line // 2, 1)))
    return ((BLACK, 1), (GOLD if frame is Frame.GOLD else ZINC_300, line))


@functools.lru_cache(maxsize=32)
def _image(frame: Frame, width: int, height: int) -> tuple[str, int]:
    """Generate a shared frame once per style and size, in the RAM scratch directory.

    Args:
        frame: Border style.
        width: Artwork width, excluding the border.
        height: Artwork height, excluding the border.

    Returns:
        PNG path and the padding around its transparent artwork area.
    """
    bands = _bands(frame, width, height)
    outer = sum(thickness for _color, thickness in bands)
    outer_width, outer_height = width + 2 * outer, height + 2 * outer
    pixels = bytearray(outer_width * outer_height * 4)
    inset = 0
    # Nested rectangles from the outside in; the artwork area stays transparent.
    for color, thickness in bands:
        row = bytes((*color, 255)) * (outer_width - 2 * inset)
        start = (inset * outer_width + inset) * 4
        for _ in range(outer_height - 2 * inset):
            pixels[start : start + len(row)] = row
            start += outer_width * 4
        inset += thickness
    clear = bytes(width * 4)
    start = (outer * outer_width + outer) * 4
    for _ in range(height):
        pixels[start : start + len(clear)] = clear
        start += outer_width * 4
    path = generated.write(
        f"frame-{frame.value}-{width}x{height}.png", outer_width, outer_height, bytes(pixels)
    )
    return str(path), outer


@functools.lru_cache(maxsize=128)
def _dimensions(path: str) -> tuple[int, int]:
    """Measure only visible framed images, with a bounded cache.

    Args:
        path: Image file.

    Returns:
        Source dimensions; PyUI loads the file to measure them.
    """
    from display.display import Display

    width, height = Display.get_image_dimensions(path)
    return int(width), int(height)


def attach_list(view: Any) -> None:  # noqa: ANN401 — PyUI view
    """Outline the visible icons after a descriptive list draws, before it presents.

    Args:
        view: PyUI's DescriptiveListView; entries carry MenuItem values.
    """
    original = view._render
    frames = _ListFrames(view)

    def render() -> None:
        """Draw the rows and their image outlines."""
        original()
        try:
            frames.draw()
        except Exception:  # decoration must never take the list down
            logger.exception("Could not draw badge outlines")

    view._render = render


class _ListFrames:
    """Cache one visible window's fitted frames until rows or downloaded images change.

    Args:
        view: PyUI's descriptive list.
    """

    def __init__(self, view: Any) -> None:  # noqa: ANN401 — PyUI view
        self._view = view
        self._options: object = None
        self._window: tuple[int, int] | None = None
        self._version = -1
        self._frames: tuple[tuple[Frame, Bounds], ...] = ()

    def draw(self) -> None:
        """Reuse the fitted rectangles while this window and its media stay unchanged."""
        view = self._view
        window, version = (view.current_top, view.current_bottom), image_version()
        if view.options is not self._options or window != self._window or version != self._version:
            self._frames = _list_frames(view)
            self._options, self._window, self._version = view.options, window, version
        for frame, bounds in self._frames:
            draw(frame, bounds)


def _list_frames(view: Any) -> tuple[tuple[Frame, Bounds], ...]:  # noqa: ANN401 — PyUI view
    """Mirror DescriptiveListView's fitted icon geometry for visible framed rows.

    Args:
        view: The descriptive list.

    Returns:
        The frames and fitted rectangles for this visible window.
    """
    from themes.theme import Theme

    visible = view.options[view.current_top : view.current_bottom]
    if not any(entry.get_value().frame is not None for entry in visible):
        return ()
    top, row_height = view.get_row_geometry()
    target_width = int(view.each_entry_width * _ICON_SHARE)
    target_height = int(row_height * 0.90)
    x = int(Theme.get_descriptive_list_icon_offset_x()) + target_width // 2
    frames = []
    for index, entry in enumerate(visible):
        frame = entry.get_value().frame
        if frame is None or (path := entry.get_icon()) is None:
            continue
        width, height = _dimensions(path)
        if width <= 0 or height <= 0:
            continue
        scale = min(target_width / width, target_height / height)
        width, height = int(width * scale), int(height * scale)
        y = top + index * row_height + row_height // 2
        frames.append((frame, (int(x - width // 2), int(y - height // 2), width, height)))
    return tuple(frames)
