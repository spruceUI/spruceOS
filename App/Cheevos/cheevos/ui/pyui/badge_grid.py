"""A compact badge grid with the selected badge's details underneath (.agents/pyui.md).

Badges sit close together, like the achievement wall on RetroAchievements profiles. The
selected one is drawn last, enlarged and ringed, over its neighbours; its title, points,
description and tags show in two lines under the grid, and a scrollbar shows the position.

The view is PyUI's ``GridView`` with its own ``_render``: input, wraparound, paging (L1/R1 by
a screenful) and the selection stay PyUI's. Only visible tiles are drawn, every frame, as
PyUI's grid does; frames and the focus ring are shared PNGs (one texture draw each).
"""

from __future__ import annotations

import functools
import math
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from cheevos.ui.pyui import generated, image_frames
from cheevos.ui.pyui.image_frames import Bounds, Frame
from cheevos.ui.pyui.primitives import (
    Align,
    Text,
    fit_text,
    screen_size,
    text,
    text_width,
    track_color,
)

# Sizes at 640x480, scaled like the theme (views.theme_scale).
BADGE = 64  # RA's badges
_GAP = 2  # between neighbouring tiles' frames
_EDGE = 2  # between the enlarged selection and the bars or the details
_TEXT_GAP = 16  # between left- and right-aligned details
_SCROLLBAR = 4
_SCROLLBAR_PAD = 4  # each side of the scrollbar
_MIN_THUMB = 16
_ENLARGE = 1.1  # the selected badge
_TRACK_ALPHA = 60  # the scrollbar's track: the body text colour, faint


@dataclass(frozen=True, slots=True)
class Details:
    """The selected badge's second line under the grid.

    Attributes:
        text: Left: the description (or a placeholder when it's hidden).
        tags: Right: unlock mode and type, e.g. ``"Hardcore · Missable"``.
    """

    text: str = ""
    tags: str = ""


@dataclass(frozen=True, slots=True)
class Screen:
    """What the grid's layout depends on: the resolution and the theme's measurements.

    Attributes:
        width: Screen width.
        height: Screen height.
        top: Top bar height.
        bottom: Bottom bar height.
        title_line: Line height of the title font (first details line).
        body_line: Line height of the body font (second details line).
        scale: The theme's size against its 640x480 design.
    """

    width: int
    height: int
    top: int
    bottom: int
    title_line: int
    body_line: int
    scale: float


@dataclass(frozen=True, slots=True)
class Geometry:
    """Where the grid, the details and the scrollbar go (see :func:`layout`).

    Attributes:
        columns: Tiles per row.
        rows: Visible rows.
        badge: Badge size.
        enlarged: The selected badge's size.
        pitch: Cell size: a badge, its frame and a gap.
        left: Left edge of the first column's cells.
        top: Top edge of the first row's cells.
        details_top: Top of the first details line.
        title_line: Height of the first details line.
        text_gap: Space between left- and right-aligned details.
        bar_x: Left edge of the scrollbar.
        bar_width: Scrollbar width.
    """

    columns: int
    rows: int
    badge: int
    enlarged: int
    pitch: int
    left: int
    top: int
    details_top: int
    title_line: int
    text_gap: int
    bar_x: int
    bar_width: int

    @property
    def page(self) -> int:
        """Tiles on one screen."""
        return self.columns * self.rows

    @property
    def edges(self) -> tuple[int, int]:
        """Return the left and right edges of the tiles' frames (the details align to them)."""
        start, end = self._frame_span()
        return self.left + start, self.left + (self.columns - 1) * self.pitch + end

    def track(self) -> tuple[int, int]:
        """Return the scrollbar track's top and height: the tiles' frames, top to bottom."""
        start, end = self._frame_span()
        return self.top + start, (self.rows - 1) * self.pitch + end - start

    def _frame_span(self) -> tuple[int, int]:
        """Return where a tile's frame starts and ends inside its cell (a centred badge)."""
        start = self.pitch // 2 - self.badge // 2
        padding = image_frames.padding(Frame.GOLD, self.badge, self.badge)
        return start - padding, start + self.badge + padding

    def centre(self, index: int) -> tuple[int, int]:
        """Return the centre of a visible tile.

        Args:
            index: Position on screen, row by row.

        Returns:
            ``(x, y)``.
        """
        row, column = divmod(index, self.columns)
        half = self.pitch // 2
        return self.left + column * self.pitch + half, self.top + row * self.pitch + half

    def cell_at(self, x: int, y: int) -> int | None:
        """Return the visible tile under a point, if any.

        Args:
            x: Screen x.
            y: Screen y.

        Returns:
            Position on screen, row by row, or ``None`` outside the grid.
        """
        if x < self.left or y < self.top:
            return None
        column, row = (x - self.left) // self.pitch, (y - self.top) // self.pitch
        if column >= self.columns or row >= self.rows:
            return None
        return row * self.columns + column


def layout(screen: Screen) -> Geometry:
    """Fit as many whole rows and columns of badges as the screen holds.

    Badges keep the theme's size (they never shrink to fit more). Every cell holds a gold
    frame, so no tile moves with its unlock mode. Room is kept around the grid for the
    enlarged selection, its frame and focus ring, so it never touches the bars, the details or
    the scrollbar.

    Args:
        screen: Resolution and theme measurements.

    Returns:
        The geometry.
    """
    scale = screen.scale
    badge = round(BADGE * scale)
    gap = max(round(_GAP * scale), 1)
    pitch = badge + 2 * image_frames.padding(Frame.GOLD, badge, badge) + gap
    enlarged = round(badge * _ENLARGE)
    # How far the selection reaches past its cell, on each side.
    reach = math.ceil(enlarged / 2) + image_frames.padding(Frame.FOCUS, enlarged, enlarged)
    margin = max(reach - pitch // 2, 0) + round(_EDGE * scale)
    bar_width = max(round(_SCROLLBAR * scale), 2)
    bar_pad = round(_SCROLLBAR_PAD * scale)
    gutter = bar_width + 2 * bar_pad
    details_top = screen.height - screen.bottom - screen.title_line - screen.body_line
    height = details_top - screen.top
    columns = max((screen.width - gutter - 2 * margin) // pitch, 1)
    rows = max((height - 2 * margin) // pitch, 1)
    return Geometry(
        columns=columns,
        rows=rows,
        badge=badge,
        enlarged=enlarged,
        pitch=pitch,
        left=(screen.width - gutter - columns * pitch) // 2,
        top=screen.top + (height - rows * pitch) // 2,
        details_top=details_top,
        title_line=screen.title_line,
        text_gap=round(_TEXT_GAP * scale),
        bar_x=screen.width - gutter + bar_pad,
        bar_width=bar_width,
    )


def thumb(first_row: int, total_rows: int, rows: int, track: int) -> tuple[int, int] | None:
    """Return the scrollbar thumb's offset and length in its track.

    Args:
        first_row: First visible row.
        total_rows: Rows of the whole list.
        rows: Visible rows.
        track: Track length.

    Returns:
        ``(offset, length)``, or ``None`` when every row is visible (no scrollbar).
    """
    if total_rows <= rows or track <= 0:
        return None
    length = min(max(track * rows // total_rows, _MIN_THUMB), track)
    last = total_rows - rows
    first = min(max(first_row, 0), last)
    return (track - length) * first // last, length


def measure(scale: float) -> Screen:
    """Read the screen's and theme's measurements from PyUI.

    Args:
        scale: The theme's size against its 640x480 design.

    Returns:
        The measurements :func:`layout` needs.
    """
    from display.display import Display
    from display.font_purpose import FontPurpose

    width, height = screen_size()
    return Screen(
        width=width,
        height=height,
        top=int(Display.get_top_bar_height()),
        bottom=int(Display.get_bottom_bar_height()),
        title_line=int(Display.get_line_height(FontPurpose.DESCRIPTIVE_LIST_TITLE)),
        body_line=int(Display.get_line_height(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)),
        scale=scale,
    )


def create(title: str, entries: Sequence[Any], selected: int, scale: float) -> Any:  # noqa: ANN401 — PyUI view
    """Create the grid view for PyUI entries carrying ``MenuItem`` values.

    Args:
        title: Top-bar text.
        entries: PyUI entries (see ``views._entries``); ``frame`` and ``details`` are used.
        selected: Initially selected index.
        scale: The theme's size against its 640x480 design.

    Returns:
        The view (a PyUI ``GridView``).
    """
    painter = _Painter(layout(measure(scale)))
    return _view_class()(title, list(entries), selected, painter)


def fitted_details(item: Any, geometry: Geometry) -> tuple[str, str, str, str]:  # noqa: ANN401 — MenuItem
    """Fit the selected item's details: the right-aligned parts first, the rest gets the room.

    Args:
        item: The selected ``MenuItem`` (``title``, ``value`` and ``details``).
        geometry: The layout.

    Returns:
        Title, points, description and tags, shortened with an ellipsis where needed.
    """
    left, right = geometry.edges
    room = right - left
    details = item.details or Details()
    points = fit_text(item.value, Text.TITLE, room // 2)
    tags = fit_text(details.tags, Text.BODY, room // 2)

    def beside(value: str, role: Text, other: str) -> str:
        """Fit text next to a right-aligned part."""
        used = text_width(other, role) + geometry.text_gap if other else 0
        return fit_text(value, role, room - used)

    return (
        beside(item.title, Text.TITLE, points),
        points,
        beside(details.text, Text.BODY, tags),
        tags,
    )


class _Painter:
    """Draws a badge grid's content between PyUI's bars, one frame at a time.

    The view is PyUI's grid: ``options``, ``selected`` and the visible window
    ``current_left``/``current_right``, kept by PyUI's own input handling.

    Args:
        geometry: The layout.
    """

    def __init__(self, geometry: Geometry) -> None:
        self.geometry = geometry
        self._fitted: tuple[object, int, tuple[str, str, str, str]] = (None, -1, ("", "", "", ""))
        self._thumb = track_color()
        self._track = str(generated.swatch(self._thumb, _TRACK_ALPHA, tall=True))

    def draw(self, view: Any) -> None:  # noqa: ANN401 — PyUI view
        """Draw the visible tiles, the selection over them, the details and the scrollbar.

        Args:
            view: The grid, its window already moved to the selection.
        """
        geometry, first, selected = self.geometry, view.current_left, view.selected
        visible = view.options[first : view.current_right]
        size = geometry.badge
        for index, entry in enumerate(visible):
            if first + index == selected:
                continue
            frame = entry.get_value().frame
            bounds = _image(entry.get_image_path_ideal(size, size), geometry.centre(index), size)
            if bounds is not None and frame is not None:
                image_frames.draw(frame, bounds)
        if first <= selected < first + len(visible):
            self._selection(view.options[selected], selected - first)
        self._details(view.options, selected)
        self._scrollbar(len(view.options), first)

    def touched(self, view: Any, point: tuple[int, int] | None) -> int | None:  # noqa: ANN401 — PyUI view
        """Return the option under a tap, if it is a tile (the details and scrollbar aren't).

        Args:
            view: The grid.
            point: Logical screen coordinates.

        Returns:
            The option's index, or ``None``.
        """
        if point is None or not view.options:
            return None
        index = self.geometry.cell_at(int(point[0]), int(point[1]))
        if index is None:
            return None
        index += view.current_left
        return index if index < min(view.current_right, len(view.options)) else None

    def _selection(self, entry: Any, index: int) -> None:  # noqa: ANN401 — PyUI entry
        """Draw the selected badge enlarged and ringed, then its own frame inside the ring.

        Args:
            entry: The selected entry.
            index: Its position on screen.
        """
        geometry = self.geometry
        size, (x, y) = geometry.enlarged, geometry.centre(index)
        path = entry.get_image_path_selected_ideal(geometry.badge, geometry.badge)
        # A missing image is ringed too: the selection must always show.
        bounds = _image(path, (x, y), size) or (x - size // 2, y - size // 2, size, size)
        image_frames.draw(Frame.FOCUS, bounds)
        frame = entry.get_value().frame
        if frame is not None:
            image_frames.draw(frame, bounds)

    def _details(self, options: Sequence[Any], selected: int) -> None:
        """Draw the selected item's title, points, description and tags, fitted once.

        Args:
            options: The grid's entries.
            selected: The selected index.
        """
        key, index, lines = self._fitted
        if key is not options or index != selected:
            lines = fitted_details(options[selected].get_value(), self.geometry)
            self._fitted = (options, selected, lines)
        title, points, description, tags = lines
        left, right = self.geometry.edges
        y = self.geometry.details_top
        text(title, left, y, Text.TITLE)
        text(points, right, y, Text.TITLE, Align.TOP_RIGHT)
        y += self.geometry.title_line
        text(description, left, y, Text.BODY)
        text(tags, right, y, Text.BODY, Align.TOP_RIGHT)

    def _scrollbar(self, count: int, first: int) -> None:
        """Draw the scrollbar when the list is longer than a screen.

        Args:
            count: Number of options.
            first: Index of the first visible option.
        """
        from display.display import Display
        from display.render_mode import RenderMode
        from display.resize_type import ResizeType

        geometry = self.geometry
        top, height = geometry.track()
        rows = math.ceil(count / geometry.columns)
        shown = thumb(first // geometry.columns, rows, geometry.rows, height)
        if shown is None:
            return
        x, width = geometry.bar_x, geometry.bar_width
        mode = RenderMode.TOP_LEFT_ALIGNED
        Display.render_image(self._track, x, top, mode, width, height, ResizeType.ZOOM)
        offset, length = shown
        Display.render_box(self._thumb, x, top + offset, width, length)


def _image(path: str | None, centre: tuple[int, int], size: int) -> Bounds | None:
    """Draw an image fitted in a square around a point.

    Args:
        path: Image file (PyUI draws nothing for ``None`` or a file it can't load).
        centre: ``(x, y)``.
        size: Square side.

    Returns:
        The drawn image's bounds, or ``None`` if nothing was drawn.
    """
    from display.display import Display
    from display.render_mode import RenderMode

    x, y = centre
    mode = RenderMode.MIDDLE_CENTER_ALIGNED
    width, height = (int(value) for value in Display.render_image(path, x, y, mode, size, size))
    return (x - width // 2, y - height // 2, width, height) if width else None


@functools.cache
def _view_class() -> type:
    """Define the view class once PyUI can be imported.

    Returns:
        A ``GridView`` subclass drawn by a :class:`_Painter`.
    """
    from display.display import Display
    from views.grid_view import GridView

    class BadgeGridView(GridView):
        """PyUI's grid, drawn by a :class:`_Painter` (see the module docstring).

        Args:
            title: Top-bar text.
            options: PyUI entries carrying ``MenuItem`` values.
            selected: Initially selected index.
            painter: Draws the content.
        """

        def __init__(
            self, title: str, options: list[Any], selected: int, painter: _Painter
        ) -> None:
            geometry = painter.geometry
            super().__init__(
                top_bar_text=title,
                options=options,
                cols=geometry.columns,
                rows=geometry.rows,
                selected_index=selected,
                show_grid_text=False,
                resized_width=geometry.badge,
                resized_height=geometry.badge,
                wrap_around_single_row=False,
            )
            self.painter = painter
            # Start with the selection on the first visible row (PyUI's grid puts it last).
            rows = math.ceil(len(options) / geometry.columns)
            row = min(selected // geometry.columns, max(rows - geometry.rows, 0))
            self.current_left = row * geometry.columns
            self.current_right = self.current_left + geometry.page

        def _render(self) -> None:
            """Draw one frame, as ``GridView._render`` does, with the painter's content."""
            if Display._screensaver_active:
                return
            Display.clear(self.top_bar_text)
            self.correct_selected_for_off_list()
            self.painter.draw(self)
            Display.add_index_text(self.selected + 1, len(self.options))
            Display.present()

        def cell_at_touch_point(self, point: tuple[int, int] | None) -> int | None:
            """Return the option under a tap (see :meth:`_Painter.touched`)."""
            return self.painter.touched(self, point)

    return BadgeGridView
