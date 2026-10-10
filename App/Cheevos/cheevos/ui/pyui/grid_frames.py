"""Award frames around grid tiles, after RetroAchievements' awards showcase.

RA draws a mastered game's icon with a 2 px gold border (``goldimage``). The awards wall here
also shows completed and beaten games, so it extends that with RA's award-indicator colours
(see :mod:`bar_colors`): gold for the mastery family, silver for beaten, a thick frame for
hardcore and a thin one for casual.

PyUI's ``GridView._render`` presents the frame itself, so the frames can't be drawn after it.
The bridge wraps the view's per-tile ``_render_cell`` instead and draws each tile's frame right
after the tile, using the geometry ``GridView._render_cell`` uses.
"""

from __future__ import annotations

import logging
from typing import Any

from cheevos.ui.pyui import generated
from cheevos.ui.pyui.bar_colors import Paint, Palette
from cheevos.ui.pyui.row_bars import page_palette

logger = logging.getLogger(__name__)

_THICK_SHARE = 1 / 32  # hardcore frame thickness per icon size (3 px at 96 px)


def attach(view: Any) -> None:  # noqa: ANN401 — PyUI view
    """Frame awarded tiles on every frame of ``view`` (a multi-row ``GridView``).

    Args:
        view: The grid; its entries' values are ``MenuItem`` objects with ``frame`` set.
    """
    original = view._render_cell
    colors: list[Palette] = []

    def render_cell(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401 — PyUI's signature
        """Draw the tile, then its award frame."""
        result = original(*args, **kwargs)
        visible_index = kwargs.get("visible_index", args[0] if args else 0)
        entry = kwargs.get("imageTextPair", args[1] if len(args) > 1 else None)
        kind = getattr(entry.get_value(), "frame", None) if entry is not None else None
        if kind is not None:
            try:
                if not colors:
                    colors.append(page_palette())
                _frame(view, visible_index, colors[0].markers[kind])
            except Exception:  # frames are decoration; never take the grid down
                logger.exception("Could not draw an award frame")
        return result

    view._render_cell = render_cell


def _frame(view: Any, visible_index: int, marker: Any) -> None:  # noqa: ANN401 — PyUI view
    """Draw a frame around one tile's image box (geometry as in ``GridView._render_cell``).

    Args:
        view: The grid.
        visible_index: Tile position on the page.
        marker: Colour and fill (filled: hardcore, thick frame).
    """
    from display.display import Display
    from themes.theme import Theme

    width, height = view.resized_width, view.resized_height
    if not width or not height or view.rows < 2:  # noqa: PLR2004 — multi-row grids only
        return
    column = int(view.x_pad + (visible_index % view.cols) * view.icon_width)
    x = column + int(view.icon_width // 2)
    spacing = Display.get_usable_screen_height() / view.rows
    top_bar = Display.get_top_bar_height(force_include_top_bar=False)
    bottom = (visible_index // view.cols) * spacing + spacing + top_bar
    text = Display.get_line_height(view.font_purpose) if view.show_grid_text else 0
    y = int(bottom - spacing // 2 + Theme.get_grid_multi_row_img_y_offset(text) // 2)
    size = int(min(width, height))  # icons are square and drawn fitted into the box
    thick = max(round(size * _THICK_SHARE), 2)
    line = thick if marker.filled else max(thick // 2, 1)
    left, top = x - size // 2 - line, y - size // 2 - line
    outer = size + 2 * line
    paint = Paint(marker.color)
    for rect in (
        (left, top, outer, line),
        (left, top + outer - line, outer, line),
        (left, top, line, outer),
        (left + outer - line, top, line, outer),
    ):
        _fill(paint, rect)


def _fill(paint: Paint, rect: tuple[int, int, int, int]) -> None:
    """Fill a rectangle (through a swatch, like the row bars).

    Args:
        paint: Colour and opacity.
        rect: ``(x, y, width, height)``.
    """
    from display.display import Display
    from display.render_mode import RenderMode
    from display.resize_type import ResizeType

    x, y, width, height = rect
    path = str(generated.swatch(paint.color, paint.alpha, tall=height > width))
    Display.render_image(path, x, y, RenderMode.TOP_LEFT_ALIGNED, width, height, ResizeType.ZOOM)
