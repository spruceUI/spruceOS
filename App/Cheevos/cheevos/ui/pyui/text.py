"""Text handling for the PyUI bridge: glyph coverage, fast width estimates, fitting.

Theme fonts vary a lot (the Pico-8 theme's pixel font lacks "·" and "…"), and measuring every
row with SDL_ttf is too slow on a Miyoo Mini for big lists, so widths come from cached glyph
advances.
"""

from __future__ import annotations

import ctypes
import functools
import logging
import re
import unicodedata
from dataclasses import dataclass, field
from enum import Enum

# Emoji and pictographs: theme fonts have no glyphs for them (they render as boxes).
logger = logging.getLogger(__name__)

_NO_GLYPH = re.compile("[\U0001f000-\U0001faff\u2600-\u27bf\ufe0f\u200d\u2b50\u2b55\u231a-\u23ff]")
# Typographic characters we use, with ASCII stand-ins for theme fonts that lack them
# (e.g. the Pico-8 theme's pixel font has neither "·" nor "…").
_ASCII_FALLBACKS = {
    "\u00b7": "-",  # middle dot
    "\u2026": "...",  # ellipsis
    "\u2014": "-",  # em dash
    "\u2013": "-",  # en dash
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
}
_BMP_MAX = 0xFFFF  # Legacy SDL_ttf glyph APIs only take 16-bit code points.
# Width estimates ignore kerning; keep a little slack so fitted text never touches neighbours.
_FIT_MARGIN = 0.97
# Share of the screen width the top-bar title may use if PyUI's top bar can't be measured.
_TITLE_WIDTH_SHARE = 0.44
_TOP_BAR_PAD = 10  # PyUI's spacing in the top bar (TopBar.render_top_bar_menu_not_skipped)
_title_rooms: dict[int, int] = {}  # screen width -> room for the title


class Text(Enum):
    """Text roles, mapped to PyUI font purposes (and so to theme fonts and colours)."""

    TITLE = "DESCRIPTIVE_LIST_TITLE"
    BODY = "DESCRIPTIVE_LIST_DESCRIPTION"
    LIST = "LIST"
    HEADING = "TOP_BAR_TEXT"
    GRID = "GRID_MULTI_ROW"  # captions under grid tiles


def font_purpose(role: Text) -> object:
    """Return PyUI's ``FontPurpose`` member for a text role.

    Args:
        role: Text role.

    Returns:
        The ``FontPurpose`` member.
    """
    from display.font_purpose import FontPurpose

    return FontPurpose[role.value]


@functools.lru_cache(maxsize=256)
def _has_glyph(purpose: str, char: str) -> bool:
    """Whether the active theme's font for ``purpose`` can draw ``char``.

    Args:
        purpose: ``FontPurpose`` member name.
        char: One character.

    Returns:
        ``True`` if the font has a glyph (or the check is unavailable).
    """
    from display.display import Display
    from display.font_purpose import FontPurpose
    from sdl2 import sdlttf

    fonts = getattr(Display, "fonts", None)
    loaded = fonts.get(FontPurpose[purpose]) if fonts else None
    if loaded is None:
        return True
    try:
        return bool(sdlttf.TTF_GlyphIsProvided32(loaded.font, ord(char)))
    except (AttributeError, RuntimeError):  # PySDL2 uses RuntimeError stubs on SDL_ttf < 2.0.18.
        return ord(char) > _BMP_MAX or bool(sdlttf.TTF_GlyphIsProvided(loaded.font, ord(char)))


def displayable(value: str, role: Text = Text.BODY) -> str:
    """Make RA text drawable in the theme font for ``role``.

    Removes emoji and pictographs (no theme font has them), swaps typographic characters the
    font lacks for ASCII, drops accents the font can't draw ("Pokémon" -> "Pokemon" in the
    Pico-8 theme), and collapses leftover spaces.

    Args:
        value: Text from RA or our strings (titles, rich presence, ...).
        role: Text role whose font will draw it.

    Returns:
        Text safe to render.
    """
    if value.isascii() and value.isprintable() and "  " not in value and value == value.strip():
        return value  # most RA text: nothing to drop, swap or collapse (cheap for big lists)
    text = " ".join(_NO_GLYPH.sub("", value).split())
    if text.isascii():
        return text
    glyphs = _glyphs.get(role)
    if glyphs is None:
        glyphs = _glyphs[role] = _Glyphs()
    chars = set(text)
    for char in chars - glyphs.checked:  # each character is looked up once per font
        glyphs.checked.add(char)
        if not char.isascii() and not _has_glyph(role.value, char):
            glyphs.swaps[ord(char)] = _ASCII_FALLBACKS.get(char) or _plain(char)
            glyphs.missing.add(char)
    if chars.isdisjoint(glyphs.missing):
        return text
    return text.translate(glyphs.swaps)


@dataclass(slots=True)
class _Glyphs:
    """The characters one theme font lacks, found as text comes by.

    Attributes:
        checked: Characters looked up so far.
        missing: The ones the font can't draw.
        swaps: What to draw instead (code point to text): an ASCII stand-in for typographic
            characters, the base letter for accented ones.
    """

    checked: set[str] = field(default_factory=set)
    missing: set[str] = field(default_factory=set)
    swaps: dict[int, str] = field(default_factory=dict)


_glyphs: dict[Text, _Glyphs] = {}


@functools.lru_cache(maxsize=512)
def _plain(char: str) -> str:
    """Return a character without its accent ("é" -> "e"), for fonts that lack the accented one.

    Args:
        char: One character.

    Returns:
        The base letter, or the character itself when it has none.
    """
    base = "".join(c for c in unicodedata.normalize("NFKD", char) if not unicodedata.combining(c))
    return base or char


class _Advances(dict[str, int]):
    """How far each character advances the pen in one theme font, measured on first use.

    Measuring long lists costs a dictionary lookup per character instead of an SDL_ttf call
    per string (on the Mini, per-string measurement of 1,000 rows took longer than 15 s).

    Args:
        purpose: ``FontPurpose`` member name.
    """

    def __init__(self, purpose: str) -> None:
        super().__init__()
        self._purpose = purpose

    def __missing__(self, char: str) -> int:
        """Measure a character the first time it is looked up."""
        width = self[char] = _advance(self._purpose, char)
        return width


_advances: dict[Text, _Advances] = {}


def _font_advances(role: Text) -> _Advances:
    """Return the advance table of the theme font for ``role``.

    Args:
        role: Text role.

    Returns:
        Character to advance width.
    """
    found = _advances.get(role)
    if found is None:
        found = _advances[role] = _Advances(role.value)
    return found


def _advance(purpose: str, char: str) -> int:
    """Measure how far one character advances the pen in the theme font for ``purpose``.

    Args:
        purpose: ``FontPurpose`` member name.
        char: One character.

    Returns:
        Advance width in pixels.
    """
    from display.display import Display
    from display.font_purpose import FontPurpose
    from sdl2 import sdlttf

    font = Display.fonts[FontPurpose[purpose]].font
    codepoint = ord(char)
    metrics = [ctypes.c_int() for _ in range(5)]
    pointers = [ctypes.byref(m) for m in metrics]
    try:
        failed = sdlttf.TTF_GlyphMetrics32(font, codepoint, *pointers)
    except (AttributeError, RuntimeError):  # PySDL2 uses RuntimeError stubs on SDL_ttf < 2.0.18.
        failed = (
            sdlttf.TTF_GlyphMetrics(font, codepoint, *pointers) if codepoint <= _BMP_MAX else True
        )
    if not failed:
        return metrics[4].value
    return int(Display.get_text_dimensions(FontPurpose[purpose], char)[0])


def text_width(value: str, role: Text) -> int:
    """Estimate the rendered width of ``value`` from cached glyph advances.

    Ignores kerning, which is within a few pixels for UI text; callers keep a small margin.

    Args:
        value: Text (already passed through :func:`displayable`).
        role: Text role (font).

    Returns:
        Width in pixels.
    """
    return sum(map(_font_advances(role).__getitem__, value))


@functools.lru_cache(maxsize=8)
def _ellipsis(role: Text) -> str:
    """Return "…" if the font for ``role`` has it, else "...".

    Args:
        role: Text role.

    Returns:
        The ellipsis to append when truncating.
    """
    return displayable("…", role)


def fit_title(value: str) -> str:
    """Shorten a top-bar title with an ellipsis so it clears the clock and the status icons.

    Args:
        value: Desired title.

    Returns:
        The title, truncated if needed.
    """
    return fit_text(value, Text.HEADING, title_room())


def title_room() -> int:
    """Return the width the top-bar title has between the clock and the status icons.

    Returns:
        Width in pixels (measured once per screen width).
    """
    from devices.device import Device

    width = int(Device.get_device().screen_width())
    if width not in _title_rooms:  # screens draw a title every frame; measure once
        try:
            _title_rooms[width] = _title_room(width)
        except Exception:  # an unusual theme or device: a share of the screen
            logger.exception("Could not measure the top bar; the title gets a fixed share")
            _title_rooms[width] = int(width * _TITLE_WIDTH_SHARE)
    return _title_rooms[width]


def _title_room(width: int) -> int:
    """Return the width the centred top-bar title has between the clock and the icons.

    Mirrors PyUI's ``TopBar.render_top_bar_menu_not_skipped``: the clock starts at the theme's
    offset on the left; the battery percentage, battery and Wi-Fi icons stack leftwards from
    20 px off the right edge, 10 px apart. They have fixed pixel widths, so they take a bigger
    share of a narrow screen. The clock is measured with zeros (its widest digits here), and
    the Wi-Fi icon counts whether or not Wi-Fi is on, so the room never changes mid-session.
    A Bluetooth icon (only while a device is connected) isn't counted.

    Args:
        width: Screen width.

    Returns:
        Width in pixels.
    """
    from devices.device import Device
    from devices.wifi.wifi_status import WifiStatus
    from display.display import Display
    from display.font_purpose import FontPurpose
    from themes.theme import Theme

    def text(value: str) -> int:
        """Width of top-bar status text."""
        return int(Display.get_text_dimensions(FontPurpose.BATTERY_PERCENT, value)[0])

    def image(path: object) -> int:
        """Width of a top-bar icon plus its spacing (0 for none)."""
        return int(Display.get_image_dimensions(path)[0]) + _TOP_BAR_PAD if path else 0

    device = Device.get_device()
    left = 0
    if Theme.show_clock():
        clock = re.sub(r"\d", "0", Display.top_bar.get_current_time_hhmm())
        left = int(Theme.get_top_bar_initial_x_offset()) + text(clock)
    right = width - _TOP_BAR_PAD * 2
    if Theme.display_battery_percent():
        right -= text("100") + _TOP_BAR_PAD
    if Theme.display_battery_icon():
        right -= image(Theme.get_battery_icon(device.get_charge_status(), 100))
    if device.supports_wifi():
        right -= image(Theme.get_wifi_icon(WifiStatus.GREAT))
    centre = width // 2
    return max(2 * (min(centre - left, right - centre) - _TOP_BAR_PAD), 0)


def fit_text(value: str, role: Text, max_width: int) -> str:
    """Shorten text with an ellipsis so it fits ``max_width`` in the font for ``role``.

    Args:
        value: Text to fit.
        role: Text role (font).
        max_width: Available width in pixels.

    Returns:
        The text, truncated if needed.
    """
    value = displayable(value, role)
    budget = int(max_width * _FIT_MARGIN)
    advances = _font_advances(role)
    if sum(map(advances.__getitem__, value)) <= budget:
        return value
    ellipsis = _ellipsis(role)
    remaining = budget - sum(map(advances.__getitem__, ellipsis))
    for index, char in enumerate(value):
        remaining -= advances[char]
        if remaining < 0:
            return value[:index].rstrip() + ellipsis
    return value


@dataclass(frozen=True, slots=True)
class ListRoom:
    """Width a list row's text has, from the theme's layout (see :func:`list_room`).

    Attributes:
        full: Width without a right-aligned value (descriptions, titles without a value).
        gap: Space between the title and the value.
        least: Width a title keeps however wide the value is.
    """

    full: int
    gap: int
    least: int

    def title(self, value_text: str) -> int:
        """Return the width left for a title next to a right-aligned value.

        Args:
            value_text: The row's right-aligned value (may be empty).

        Returns:
            Maximum title width in pixels.
        """
        if not value_text:
            return self.full
        return max(self.full - text_width(value_text, Text.TITLE) - self.gap, self.least)


def list_room() -> ListRoom:
    """Measure the room for text in a list row; measure once per list, not once per row.

    Mirrors PyUI's descriptive list layout: the icon column is 12.5% of the row, the title
    starts a theme-defined offset after it, and the value is right-aligned with that offset.

    Returns:
        The room.
    """
    from devices.device import Device
    from themes.theme import Theme

    screen = int(Device.get_device().screen_width())
    gap = int(Theme.get_descriptive_list_text_from_icon_offset())
    used = int(Theme.get_descriptive_list_icon_offset_x()) + screen // 8 + gap * 2
    least = screen // 4
    return ListRoom(max(screen - used, least), gap, least)
