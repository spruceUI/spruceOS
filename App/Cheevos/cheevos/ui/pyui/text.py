"""Text handling for the PyUI bridge: glyph coverage and fitting.

Theme fonts vary a lot (the Pico-8 theme's pixel font lacks "·" and "…"). Widths come from
PyUI's per-font glyph advances (``Display.get_text_width_from_glyphs``, SpruceOS #1900): measuring
every row with SDL_ttf is too slow on a Miyoo Mini for big lists.
"""

from __future__ import annotations

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
_ELLIPSIS = "..."  # as PyUI ends the list titles it shortens
# Share of the screen width the top-bar title may use if PyUI's top bar can't be measured.
_TITLE_WIDTH_SHARE = 0.44
_TOP_BAR_PAD = 10  # PyUI's spacing in the top bar (TopBar.render_top_bar_menu_not_skipped)
_ICON_SHARE = 0.125  # PyUI's icon column: 1/8 of the selected-row background's width
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


def _has_glyph(role: Text, char: str) -> bool:
    """Whether the active theme's font for ``role`` can draw ``char``.

    Args:
        role: Text role.
        char: One character.

    Returns:
        ``True`` if the font has a glyph (or no fonts are loaded yet).
    """
    from display.display import Display

    if not getattr(Display, "fonts", None):
        return True
    return not Display.requires_fallback_font(char, font_purpose(role))


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
        if not char.isascii() and not _has_glyph(role, char):
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


def text_width(value: str, role: Text) -> int:
    """Estimate the rendered width of ``value`` from PyUI's cached glyph advances.

    Kerning is left out, so the estimate comes out a few pixels wider than SDL_ttf's.

    Args:
        value: Text (already passed through :func:`displayable`).
        role: Text role (font).

    Returns:
        Width in pixels.
    """
    from display.display import Display

    return int(Display.get_text_width_from_glyphs(font_purpose(role), value))


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
    from display.display import Display

    value = displayable(value, role)
    if text_width(value, role) <= max_width:
        return value
    room = max_width - text_width(_ELLIPSIS, role)
    return (
        value[: Display.count_chars_that_fit(font_purpose(role), value, room)].rstrip() + _ELLIPSIS
    )


def fit_with_tail(value: str, tail: str, role: Text, max_width: int) -> str:
    """Fit ``"value · tail"``, shortening ``value`` first so ``tail`` (a date) stays whole.

    Args:
        value: Text that may be shortened.
        tail: Text kept whole when there is room for it (may be empty).
        role: Text role (font).
        max_width: Available width in pixels.

    Returns:
        The joined text, shortened if needed.
    """
    if not tail or not value:
        return fit_text(value or tail, role, max_width)
    joined = displayable(f"{value} · {tail}", role)
    if text_width(joined, role) <= max_width:
        return joined
    end = " " + displayable(f"· {tail}", role)  # displayable() strips a leading space
    room = max_width - text_width(end, role)
    if room < text_width(_ELLIPSIS, role) * 4:
        return fit_text(joined, role, max_width)
    return fit_text(value, role, room) + end


def description_room() -> int:
    """Measure the width a list row's description has; measure once per list, not per row.

    PyUI fits list titles itself, but not descriptions. Mirrors its descriptive list layout:
    the icon column is 12.5% of the selected-row background's width, and the text starts a
    theme-defined offset after it and ends that offset before the screen edge. The background
    isn't always as wide as the screen: most themes have a 640 px one at every resolution, and
    SPRUCE's is 640 px at 480x800.

    Returns:
        Width in pixels.
    """
    from devices.device import Device
    from display.display import Display
    from themes.theme import Theme

    screen = int(Device.get_device().screen_width())
    row = int(Display.get_image_dimensions(Theme.get_list_large_selected_bg())[0]) or screen
    gap = int(Theme.get_descriptive_list_text_from_icon_offset())
    used = int(Theme.get_descriptive_list_icon_offset_x()) + int(row * _ICON_SHARE) + gap * 2
    return max(screen - used, screen // 4)
