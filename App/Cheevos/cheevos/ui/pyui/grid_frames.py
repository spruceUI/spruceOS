"""Outline grid images before PyUI presents them (.agents/pyui.md, "Grid overlays").

The per-cell wrapper selects the border, and the primary-image wrapper uses the actual
rendered size and position. This works for selected and ordinary tiles, rectangular images,
fallbacks, and single-row grids, without duplicating the theme's grid geometry.
"""

from __future__ import annotations

import logging
from typing import Any

from cheevos.ui.pyui import image_frames
from cheevos.ui.pyui.image_frames import Frame

logger = logging.getLogger(__name__)


def attach(view: Any) -> None:  # noqa: ANN401 — PyUI view
    """Outline images while ``view`` draws each grid tile.

    Args:
        view: PyUI's GridView; entries carry MenuItem values with ``frame`` set.
    """
    original_cell = view._render_cell
    original_image = view._render_primary_image
    current: Frame | None = None

    def render_cell(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401 — PyUI's signature
        """Select the tile's outline while PyUI draws its primary image."""
        nonlocal current
        entry = kwargs.get("imageTextPair", args[1] if len(args) > 1 else None)
        previous = current
        current = entry.get_value().frame if entry is not None else None
        try:
            return original_cell(*args, **kwargs)
        finally:
            current = previous

    def render_image(image_path: str, x: int, y: int, *args: Any, **kwargs: Any) -> Any:  # noqa: ANN401 — PyUI's signature
        """Draw the primary image, then outline its actual fitted rectangle."""
        result = original_image(image_path, x, y, *args, **kwargs)
        if current is not None:
            try:
                width, height = (int(value) for value in result)
                image_frames.draw(
                    current, (int(x - width // 2), int(y - height // 2), width, height)
                )
            except Exception:  # decoration must never take the grid down
                logger.exception("Could not draw a badge outline")
        return result

    view._render_cell = render_cell
    view._render_primary_image = render_image
