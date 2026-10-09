"""Select bundled award PNGs and scale their canvases to a theme's row size.

All rasterization is done by ``scripts/render_awards.py`` on the development machine.
The handheld only draws these static assets through PyUI's bounded texture cache.
"""

from __future__ import annotations

from pathlib import Path

from cheevos.core.models import AwardKind
from cheevos.ui.pyui.bar_colors import LIGHT, Palette, luma

DIAMETER = 48  # Circle diameter in the bundled PNGs, excluding transparent margins.
_CANVAS = 50
_MASTERY_CANVAS = 116
_ROOT = Path(__file__).resolve().parents[2] / "res" / "awards"
_IMAGES = {
    (kind, style): str(_ROOT / f"{kind.value}-{style}.png")
    for kind in AwardKind
    for style in ("dark", "light", "black", "white")
}


def images(colors: Palette) -> dict[AwardKind, str]:
    """Select the static image paths once per row palette (ordinary or selected)."""
    # Neutral fallback markers use black/white PNGs; bars retain the theme's text colour.
    text = colors.markers[AwardKind.MASTERED].color
    if text in ((0, 0, 0), (255, 255, 255)):
        style = "black" if text == (0, 0, 0) else "white"
    else:
        style = "light" if luma(colors.background) >= LIGHT else "dark"
    return {kind: _IMAGES[kind, style] for kind in colors.markers}


def canvas_size(kind: AwardKind, diameter: int) -> int:
    """Return the scaled canvas size, keeping the circle's diameter independent of its halo."""
    canvas = _MASTERY_CANVAS if kind == AwardKind.MASTERED else _CANVAS
    return round(diameter * canvas / DIAMETER)
