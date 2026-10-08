"""Button glyphs for bottom-bar hints: the theme's own where it has them, generated otherwise.

Themes ship X, Y and START badges (``icon-x``, ``icon-y``, ``icon-START``) but no Select badge,
and SPRUCE's A/B icons are 640 px wide transparent images. Missing glyphs are drawn once in the
style of the theme's START badge (its fill and ink colours and height, the theme font in bold):
a circle for one letter, a rounded pill for a word (see :mod:`generated`).
"""

from __future__ import annotations

import ctypes
import logging
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

from cheevos.ui.pyui import generated
from cheevos.ui.pyui.buttons import Button

logger = logging.getLogger(__name__)

_LABELS = {Button.START: "START", Button.SELECT: "SELECT"}
_THEME_ASSETS = {Button.X: "icon-x.qoi", Button.Y: "icon-y.qoi"}
_MAX_HEIGHT = 64  # taller "glyphs" are layout tricks (SPRUCE's 640x54 A/B), not badges
_REFERENCE_HEIGHT = 26  # START badge height at 480 px; used when a theme has no badge
_REFERENCE_SCREEN = 480
_WORD_FONT = 0.5  # point size per badge height, words (matches START's lettering)
_LETTER_FONT = 0.62  # point size per badge height, single letters
_PILL_RADIUS = 0.2  # corner radius per badge height
_PILL_PADDING = 0.3  # horizontal padding per badge height
_SAMPLES = 4  # supersampling per axis for anti-aliased edges
_OPAQUE = 255

RGB = tuple[int, int, int]


@dataclass(frozen=True, slots=True)
class Style:
    """Look of generated glyphs, taken from the theme's START badge.

    Attributes:
        height: Glyph height in pixels.
        fill: Badge colour.
        ink: Letter colour.
    """

    height: int
    fill: RGB
    ink: RGB


_cache: dict[Button, Path | None] = {}


def reset() -> None:
    """Forget resolved glyphs (a new theme or scratch directory)."""
    _cache.clear()


def glyph(button: Button) -> Path | None:
    """Return an image of ``button`` for hints.

    Args:
        button: The button.

    Returns:
        The image, or ``None`` if none could be found or made.
    """
    if button not in _cache:
        try:
            _cache[button] = _theme_glyph(button) or _generated(button)
        except Exception:  # a missing hint glyph must never break a screen
            logger.exception("Could not make a glyph for %s", button.name)
            _cache[button] = None
    return _cache[button]


def _size(path: str) -> tuple[int, int]:
    """Read an image's size.

    Args:
        path: Image file.

    Returns:
        ``(width, height)``; ``(0, 0)`` when unreadable.
    """
    from display.display import Display

    width, height = Display.get_image_dimensions(path)
    return int(width), int(height)


def _theme_glyph(button: Button) -> Path | None:
    """Return the theme's own glyph for ``button``, if it has a usable one.

    Args:
        button: The button.

    Returns:
        The image, or ``None``.
    """
    from themes.theme import Theme

    if button is Button.START:
        path = Theme.start_icon()
    elif button in _THEME_ASSETS:
        path = Theme._asset(_THEME_ASSETS[button])
    else:
        return None
    if not path:
        return None
    width, height = _size(path)
    return Path(path) if 0 < height <= _MAX_HEIGHT and width <= height * 4 else None


def style_from_pixels(height: int, pixels: bytes) -> Style | None:
    """Derive the glyph style from a badge's pixels.

    Args:
        height: Badge height.
        pixels: RGBA bytes.

    Returns:
        Fill (most common opaque colour) and ink (opaque colour furthest from it in
        brightness), or ``None`` for a badge without opaque pixels.
    """
    opaque = Counter(
        (pixels[i], pixels[i + 1], pixels[i + 2])
        for i in range(0, len(pixels), 4)
        if pixels[i + 3] == _OPAQUE
    )
    if not opaque:
        return None
    fill = opaque.most_common(1)[0][0]
    ink = max(opaque, key=lambda color: abs(generated.luma(color) - generated.luma(fill)))
    return Style(height, fill, ink)


def _style() -> Style:
    """Take the glyph style from the theme's START badge, or derive one from its text colour.

    Returns:
        The style.
    """
    from devices.device import Device
    from display.font_purpose import FontPurpose
    from themes.theme import Theme

    badge = Theme.start_icon()
    loaded = generated.load_rgba(badge) if badge else None
    if loaded is not None:
        width, height, pixels = loaded
        derived = style_from_pixels(height, pixels) if width and height else None
        if derived is not None:
            return derived
    fill = tuple(Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE))[:3]
    ink = (0, 0, 0) if generated.luma(fill) > 127 else (255, 255, 255)  # noqa: PLR2004 — mid-grey
    screen = int(Device.get_device().screen_height())
    height = round(_REFERENCE_HEIGHT * screen / _REFERENCE_SCREEN)
    return Style(height, (int(fill[0]), int(fill[1]), int(fill[2])), ink)


def _generated(button: Button) -> Path | None:
    """Draw a glyph for ``button`` in the theme's badge style.

    Args:
        button: The button.

    Returns:
        The PNG, or ``None`` if the text could not be rendered.
    """
    label = _LABELS.get(button, button.value)
    style = _style()
    text = _render_label(label, style)
    if text is None:
        return None
    width, pixels = compose(label, style, text)
    fill, ink = "{:02x}{:02x}{:02x}".format(*style.fill), "{:02x}{:02x}{:02x}".format(*style.ink)
    return generated.write(
        f"glyph-{label}-{style.height}-{fill}-{ink}.png", width, style.height, pixels
    )


@dataclass(frozen=True, slots=True)
class Lettering:
    """A rendered label: its coverage mask and where its capitals sit.

    Attributes:
        width: Mask width.
        height: Mask height.
        alpha: One coverage byte per pixel.
        cap_top: Row of the capitals' top edge.
        cap_bottom: Row of the baseline.
    """

    width: int
    height: int
    alpha: bytes
    cap_top: int
    cap_bottom: int


def _render_label(label: str, style: Style) -> Lettering | None:
    """Render ``label`` in the theme font, bold, at a size that suits the badge.

    Args:
        label: Upper-case label.
        style: Glyph style.

    Returns:
        The lettering, or ``None`` if SDL_ttf failed.
    """
    import sdl2
    from display.display import Display
    from display.font_purpose import FontPurpose
    from sdl2 import sdlttf

    share = _LETTER_FONT if len(label) == 1 else _WORD_FONT
    font_path = Display.fonts[FontPurpose.DESCRIPTIVE_LIST_TITLE].font_path
    font = sdlttf.TTF_OpenFont(str(font_path).encode(), max(round(style.height * share), 6))
    if not font:
        return None
    try:
        sdlttf.TTF_SetFontStyle(font, sdlttf.TTF_STYLE_BOLD)
        white = sdl2.SDL_Color(255, 255, 255)
        surface = sdlttf.TTF_RenderUTF8_Blended(font, label.encode(), white)
        if not surface:
            return None
        try:
            width, height, pixels = generated.surface_rgba(surface)
        finally:
            sdl2.SDL_FreeSurface(surface)
        ascent = sdlttf.TTF_FontAscent(font)
        cap = 0
        for char in label:
            metrics = [ctypes.c_int() for _ in range(5)]
            if sdlttf.TTF_GlyphMetrics(font, ord(char), *(ctypes.byref(m) for m in metrics)) == 0:
                cap = max(cap, metrics[3].value)  # maxy: height above the baseline
        cap = cap or ascent
    finally:
        sdlttf.TTF_CloseFont(font)
    return Lettering(width, height, pixels[3::4], ascent - cap, ascent)


def compose(label: str, style: Style, text: Lettering) -> tuple[int, bytes]:
    """Draw the badge shape and centre the lettering on it.

    Args:
        label: The label (one letter: circle; a word: pill).
        style: Glyph style.
        text: Rendered lettering.

    Returns:
        ``(width, RGBA bytes)``; the height is ``style.height``.
    """
    height = style.height
    if len(label) == 1:
        width, radius = height, height / 2
    else:
        width = text.width + round(height * _PILL_PADDING) * 2
        radius = height * _PILL_RADIUS
    left = (width - text.width) // 2
    top = (height - (text.cap_bottom - text.cap_top)) // 2 - text.cap_top
    step = 1 / _SAMPLES
    out = bytearray(width * height * 4)
    for y in range(height):
        middle_row = radius <= y and y + 1 <= height - radius
        for x in range(width):
            if middle_row or (radius <= x and x + 1 <= width - radius):
                hits = _SAMPLES**2  # no corner reaches this pixel: skip the slow supersampling
            else:
                hits = sum(
                    generated.inside_rounded(
                        x + (sx + 0.5) * step, y + (sy + 0.5) * step, width, height, radius
                    )
                    for sx in range(_SAMPLES)
                    for sy in range(_SAMPLES)
                )
            if not hits:
                continue
            tx, ty = x - left, y - top
            ink = 0.0
            if 0 <= tx < text.width and 0 <= ty < text.height:
                ink = text.alpha[ty * text.width + tx] / 255
            offset = (y * width + x) * 4
            for channel in range(3):
                mixed = style.fill[channel] * (1 - ink) + style.ink[channel] * ink
                out[offset + channel] = round(mixed)
            out[offset + 3] = round(255 * hits / _SAMPLES**2)
    return width, bytes(out)
