"""Progress bars in list rows, drawn where PyUI would draw the row's description.

PyUI's descriptive list has no progress bars, so for a list whose items carry
:class:`Progress`, the bridge wraps that view's ``_render``: PyUI draws the rows (icon, title,
value, an empty description), then the bars go into the description slots, using the same
geometry PyUI uses (``DescriptiveListView._render``).

A bar follows RetroAchievements' web client (colours in :mod:`bar_colors`): a gold hardcore
segment, a grey casual-only segment, then an award dot and the percentage. All bars in a list
share one length, so they line up.
"""

from __future__ import annotations

import logging
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from cheevos.core.models import AwardKind
from cheevos.ui.pyui import generated
from cheevos.ui.pyui.bar_colors import RGB, Marker, Paint, Palette, palette
from cheevos.ui.pyui.text import Text, text_width

logger = logging.getLogger(__name__)

_ICON_SHARE = 0.125  # PyUI's icon column: 1/8 of the selected-row background's width
_GAP = 10  # between the bar, the award dot and the value text
_DOT_GAP = 4  # between the award dot and the percentage
_BAR_SHARE = 0.4  # bar height per description line height
_DOT_SHARE = 0.45  # award dot diameter per description line height
_RING_SHARE = 0.2  # hollow dot ring thickness per diameter


@dataclass(frozen=True, slots=True)
class Progress:
    """A progress bar shown in a list row instead of its description.

    Attributes:
        done: Hardcore share, 0-1 (gold).
        extra: Casual-only share drawn after it, 0-1 (grey).
        label: Text after the bar, e.g. "47%".
        award: The game's highest award, shown as a dot before the label.
    """

    done: float
    extra: float = 0.0
    label: str = ""
    award: AwardKind | None = None


@dataclass(frozen=True, slots=True)
class _Layout:
    """Layout shared by every row of one list.

    Attributes:
        bar_x: Bar left edge.
        bar_width: Bar length.
        dot_x: Award dot left edge.
        label_x: Percentage left edge.
        dot: Award dot diameter.
        palettes: Colours for ordinary rows and for the selected row.
    """

    bar_x: int
    bar_width: int
    dot_x: int
    label_x: int
    dot: int
    palettes: tuple[Palette, Palette]


def attach(view: Any) -> None:  # noqa: ANN401 — PyUI view
    """Draw progress bars on every frame of ``view`` (a ``DescriptiveListView``).

    Args:
        view: The PyUI list view; its entries' values are ``MenuItem`` objects.
    """
    original = view._render
    layouts: dict[int, _Layout] = {}

    def render() -> None:
        """Let PyUI draw the rows, then add the bars."""
        original()
        try:
            _draw(view, layouts)
        except Exception:  # bars are decoration; never take the list down
            logger.exception("Could not draw progress bars")

    view._render = render


def _progress(entry: Any) -> Progress | None:  # noqa: ANN401 — PyUI entry
    """Return a list entry's progress bar, if its item has one.

    Args:
        entry: ``GridOrListEntry`` whose value is a ``MenuItem``.

    Returns:
        The progress, or ``None``.
    """
    return getattr(entry.get_value(), "progress", None)


def _rgb(color: Sequence[int]) -> RGB:
    """Normalise a PyUI colour (tuple or list, maybe with alpha) to RGB.

    Args:
        color: PyUI colour.

    Returns:
        ``(r, g, b)``.
    """
    return int(color[0]), int(color[1]), int(color[2])


def page_palette() -> Palette:
    """Pick RA colours for things drawn on the page background (grid tiles, ordinary rows).

    Returns:
        The palette.
    """
    from display.display import Display
    from display.font_purpose import FontPurpose
    from themes.theme import Theme

    page_image = Display.bg_path or Theme.background()
    page = generated.average_color(str(page_image)) if page_image else (0, 0, 0)
    return palette(page, _rgb(Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION)))


def top_bar_palette() -> Palette:
    """Pick RA colours for things drawn on the top bar (a game's award dot).

    Returns:
        The palette.
    """
    from display.display import Display
    from display.font_purpose import FontPurpose
    from themes.theme import Theme

    page_image = Display.bg_path or Theme.background()
    page = generated.average_color(str(page_image)) if page_image else (0, 0, 0)
    bar_image = Theme.get_title_bar_bg()
    bar = generated.average_color(str(bar_image), page) if bar_image else page
    return palette(bar, _rgb(Theme.text_color(FontPurpose.TOP_BAR_TEXT)))


def dot_size(line: int) -> int:
    """Return the award dot's diameter next to text of this height.

    Args:
        line: Text height in pixels.

    Returns:
        Diameter in pixels.
    """
    return max(round(line * _DOT_SHARE), 6)


def _palettes(view: Any) -> tuple[Palette, Palette]:  # noqa: ANN401 — PyUI view
    """Pick bar colours for ordinary rows and the selected row from their backgrounds.

    Args:
        view: The list view (its ``selected_bg`` is the highlight image).

    Returns:
        ``(ordinary, selected)`` palettes.
    """
    from display.display import Display
    from display.font_purpose import FontPurpose
    from themes.theme import Theme

    page_image = Display.bg_path or Theme.background()
    page = generated.average_color(str(page_image)) if page_image else (0, 0, 0)
    highlight = getattr(view, "selected_bg", None)
    selected = generated.average_color(str(highlight), page) if highlight else page
    font = FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION
    return page_palette(), palette(selected, _rgb(Theme.text_color_selected(font)))


def _layout(view: Any, entries: Sequence[Any]) -> _Layout:  # noqa: ANN401 — PyUI view
    """Lay out bar, dot and percentage so that they line up across the whole list.

    Args:
        view: The list view.
        entries: All its entries.

    Returns:
        The layout.
    """
    from devices.device import Device
    from display.display import Display
    from display.font_purpose import FontPurpose
    from themes.theme import Theme

    icon = int(view.each_entry_width * _ICON_SHARE) if view.contains_any_icons else 0
    padding = int(Theme.get_descriptive_list_text_from_icon_offset())
    bar_x = int(Theme.get_descriptive_list_icon_offset_x()) + icon + padding
    right = int(Device.get_device().screen_width()) - padding
    if not Theme.get_use_text_for_line_height():
        # The value text is centred on the whole row, so it shares the bar's line.
        values = {entry.get_value_text() or "" for entry in entries}
        right -= max((text_width(value, Text.TITLE) for value in values), default=0) + _GAP
    shown = [progress for entry in entries if (progress := _progress(entry))]
    labels = {progress.label for progress in shown}  # a few distinct percentages
    label = max((text_width(text, Text.BODY) for text in labels), default=0)
    line = int(Display.get_text_dimensions(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION, "A")[1])
    dot = dot_size(line) if any(p.award for p in shown) else 0
    tail = (dot + _DOT_GAP if dot else 0) + label
    bar_width = max(right - bar_x - (tail + _GAP if tail else 0), 0)
    dot_x = bar_x + bar_width + _GAP
    label_x = dot_x + (dot + _DOT_GAP if dot else 0)
    return _Layout(bar_x, bar_width, dot_x, label_x, dot, _palettes(view))


def _fill(paint: Paint, rect: tuple[int, int, int, int]) -> None:
    """Fill a rectangle, translucent if needed (a stretched swatch; see :mod:`generated`).

    Args:
        paint: Colour and opacity.
        rect: ``(x, y, width, height)``.
    """
    from display.display import Display
    from display.render_mode import RenderMode
    from display.resize_type import ResizeType

    x, y, width, height = rect
    if width <= 0 or height <= 0:
        return
    path = str(generated.swatch(paint.color, paint.alpha, tall=height > width))
    Display.render_image(path, x, y, RenderMode.TOP_LEFT_ALIGNED, width, height, ResizeType.ZOOM)


def draw_dot(marker: Marker, size: int, x: int, mid: int) -> None:
    """Draw an award dot, vertically centred on ``mid``.

    Args:
        marker: Colour and fill.
        size: Diameter.
        x: Left edge.
        mid: Vertical centre.
    """
    from display.display import Display
    from display.render_mode import RenderMode

    ring = 0 if marker.filled else max(round(size * _RING_SHARE), 1)
    path = str(generated.disc(marker.color, size, ring))
    Display.render_image(path, x, mid, RenderMode.MIDDLE_LEFT_ALIGNED)


def _draw(view: Any, cache: dict[int, _Layout]) -> None:  # noqa: ANN401 — PyUI view
    """Draw the bars of the visible rows.

    Args:
        view: The list view.
        cache: Layout per options list (recomputed when the list is replaced).
    """
    from display.display import Display
    from display.font_purpose import FontPurpose
    from display.render_mode import RenderMode
    from themes.theme import Theme

    visible = view.options[view.current_top : view.current_bottom]
    if not any(_progress(entry) for entry in visible):
        return
    key = id(view.options)
    if key not in cache:
        cache.clear()
        cache[key] = _layout(view, view.options)
    layout = cache[key]
    top, row_height = view.get_row_geometry()
    title_height = int(Display.get_text_dimensions(FontPurpose.DESCRIPTIVE_LIST_TITLE, "A")[1])
    font = FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION
    line = int(Display.get_text_dimensions(font, "A")[1])
    bar_height = max(int(line * _BAR_SHARE), 4)
    offset = int(Theme.get_descriptive_list_text_offset_y()) + title_height + line // 2
    for row, entry in enumerate(visible):
        progress = _progress(entry)
        if progress is None:
            continue
        selected = view.current_top + row == view.selected
        colors = layout.palettes[1 if selected else 0]
        text = _rgb(Theme.text_color_selected(font) if selected else Theme.text_color(font))
        mid = int(top + row * row_height + offset)
        y = mid - bar_height // 2
        width = layout.bar_width
        solid = round(width * min(max(progress.done, 0.0), 1.0))
        reach = round(width * min(max(progress.done + progress.extra, 0.0), 1.0))
        _fill(colors.track, (layout.bar_x + reach, y, width - reach, bar_height))
        _fill(colors.casual, (layout.bar_x + solid, y, reach - solid, bar_height))
        _fill(colors.hardcore, (layout.bar_x, y, solid, bar_height))
        marker = colors.markers.get(progress.award) if progress.award else None
        if marker is not None and layout.dot:
            draw_dot(marker, layout.dot, layout.dot_x, mid)
        if progress.label:
            color = marker.color if marker is not None else text
            mode = RenderMode.MIDDLE_LEFT_ALIGNED
            Display.render_text(progress.label, layout.label_x, mid, color, font, mode)
