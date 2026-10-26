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
# A filled holographic band (fill()) changes colour every 16 px of a side, 12 to 32 times.
_HOLO_STEP, _HOLO_MIN_STEPS, _HOLO_MAX_STEPS = 16, 12, 32
# RA's holoimage border (the $2 Patreon badge): a 135° gradient, top left to bottom right.
_HOLO_STOPS: tuple[RGB, ...] = (
    (255, 215, 0),
    (255, 154, 90),
    (255, 106, 213),
    (138, 125, 255),
    (86, 200, 255),
    (255, 215, 0),
)
Bounds = tuple[int, int, int, int]


class Frame(Enum):
    """Image borders shared by achievements and awards, and the badge grid's focus."""

    GOLD = "gold"
    HOLO = "holo"  # RA's holographic border, as wide as gold
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


def fill(frame: Frame, bounds: Bounds) -> None:
    """Outline an image with filled rectangles, for images whose size changes every frame.

    :func:`draw` generates a PNG per size, and the carousel's slides draw each tile at a new
    size in every frame: on a Mini that's a stutter per size (seconds for the holographic
    frame). Filled rectangles cost the same at any size and generate nothing.

    Args:
        frame: Border style.
        bounds: Actual rendered image's ``(left, top, width, height)``.
    """
    from display.display import Display

    for color, rect in strips(frame, bounds):
        Display.render_box(color, *rect)


@functools.lru_cache(maxsize=64)
def strips(frame: Frame, bounds: Bounds) -> tuple[tuple[RGB, Bounds], ...]:
    """Return the filled rectangles that draw a frame, from the outside in.

    Each band is four rectangles: the top and bottom ones span its width, the sides fit
    between them. The holographic band changes colour every :data:`_HOLO_STEP` pixels along
    each side, sampled from RA's 135° gradient over the whole frame.

    Args:
        frame: Border style.
        bounds: Actual rendered image's ``(left, top, width, height)``.

    Returns:
        ``(colour, (left, top, width, height))`` per rectangle; none for an empty image.
    """
    x, y, width, height = bounds
    if width <= 0 or height <= 0:
        return ()
    bands = _bands(frame, width, height)
    outer = sum(thickness for _color, thickness in bands)
    origin_x, origin_y = x - outer, y - outer
    span = max(width + height + 4 * outer - 2, 1)  # the gradient's length, as in _holo_row
    rects: list[tuple[RGB, Bounds]] = []
    inset = 0
    for color, thickness in bands:
        ring = _ring(
            (origin_x + inset, origin_y + inset),
            (width + 2 * (outer - inset), height + 2 * (outer - inset)),
            thickness,
        )
        if color is not None:
            rects += [(color, rect) for rect in ring]
        else:
            for rect in ring:
                for part in _segments(rect):
                    left, top, part_width, part_height = part
                    middle = (left - origin_x) + (top - origin_y) + (part_width + part_height) / 2
                    rects.append((holo_color(middle / span), part))
        inset += thickness
    return tuple(rects)


def _ring(corner: tuple[int, int], size: tuple[int, int], thickness: int) -> tuple[Bounds, ...]:
    """Return a band's four rectangles: top and bottom full width, the sides between them.

    Args:
        corner: The band's outer top-left corner.
        size: Its outer width and height.
        thickness: Its thickness.

    Returns:
        The rectangles that aren't empty.
    """
    (left, top), (width, height) = corner, size
    inner = height - 2 * thickness
    rects = (
        (left, top, width, thickness),
        (left, top + height - thickness, width, thickness),
        (left, top + thickness, thickness, inner),
        (left + width - thickness, top + thickness, thickness, inner),
    )
    return tuple(rect for rect in rects if rect[2] > 0 and rect[3] > 0)


def _segments(rect: Bounds) -> list[Bounds]:
    """Split a band's side along its length: parts of :data:`_HOLO_STEP` pixels, 12 to 32.

    Args:
        rect: A side of the band.

    Returns:
        The parts, end to end.
    """
    left, top, width, height = rect
    length = max(width, height)
    count = min(max(-(-length // _HOLO_STEP), _HOLO_MIN_STEPS), _HOLO_MAX_STEPS, length)
    parts = []
    for index in range(count):
        start, end = length * index // count, length * (index + 1) // count
        if width >= height:
            parts.append((left + start, top, end - start, height))
        else:
            parts.append((left, top + start, width, end - start))
    return parts


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


def _bands(frame: Frame, width: int, height: int) -> tuple[tuple[RGB | None, int], ...]:
    """Return a frame's bands from the outside in: colour and thickness.

    Every style has a 1 px black outer edge. The focus ring's inner black band is exactly
    a gold frame's size, so a gold frame drawn after it fits inside the white ring. A band
    without a colour is the holographic gradient.

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
    if frame is Frame.HOLO:
        return ((BLACK, 1), (None, line))
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
    pixels = bytearray(outer_width * outer_height * 4)  # transparent
    inset = 0
    # Only the bands' own pixels, from the outside in: the artwork area stays transparent, and
    # the holographic gradient is computed for its band alone.
    for color, thickness in bands:
        right, bottom = outer_width - inset, outer_height - inset
        for y in range(inset, bottom):
            edge = y < inset + thickness or y >= bottom - thickness
            spans = (
                ((inset, right),)
                if edge
                else ((inset, inset + thickness), (right - thickness, right))
            )
            for start, end in spans:
                if color is None:
                    row = _holo_row(y, (start, end), outer_width, outer_height)
                else:
                    row = bytes((*color, 255)) * (end - start)
                at = (y * outer_width + start) * 4
                pixels[at : at + len(row)] = row
        inset += thickness
    path = generated.write(
        f"frame-{frame.value}-{width}x{height}.png", outer_width, outer_height, bytes(pixels)
    )
    return str(path), outer


def holo_color(position: float) -> RGB:
    """Return RA's holographic gradient colour at a position along it.

    Args:
        position: 0 (top left) to 1 (bottom right).

    Returns:
        The colour.
    """
    scaled = min(max(position, 0.0), 1.0) * (len(_HOLO_STOPS) - 1)
    index = min(int(scaled), len(_HOLO_STOPS) - 2)
    share = scaled - index
    start, end = _HOLO_STOPS[index], _HOLO_STOPS[index + 1]
    red, green, blue = (round(a + (b - a) * share) for a, b in zip(start, end, strict=True))
    return red, green, blue


def _holo_row(y: int, columns: tuple[int, int], width: int, height: int) -> bytes:
    """Return part of a row of the holographic band (opaque RGBA).

    Args:
        y: Row in the frame image.
        columns: First column, and the column after the last.
        width: Frame image width.
        height: Frame image height.

    Returns:
        The pixels.
    """
    span = max(width + height - 2, 1)
    return b"".join(bytes((*holo_color((x + y) / span), 255)) for x in range(*columns))


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
