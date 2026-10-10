"""Typed drawing and input primitives on top of PyUI's ``Display``, ``Theme`` and ``Controller``.

Used for screens PyUI's standard views cannot express (profile header, achievement detail,
full-screen screenshots). Colours and fonts always come from the active theme.
"""

from __future__ import annotations

import contextlib
import math
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from cheevos.ui.pyui import generated, status_bar
from cheevos.ui.pyui.buttons import Button
from cheevos.ui.pyui.text import (
    Text,
    displayable,
    fit_text,
    fit_title,
    font_purpose,
    text_width,
)

__all__ = [
    "Align",
    "Area",
    "Button",
    "Text",
    "accent_color",
    "ask_text",
    "begin",
    "begin_bare",
    "box",
    "chart_color",
    "displayable",
    "end",
    "fit_text",
    "fit_title",
    "image",
    "line_height",
    "screen_size",
    "sharp_scaled",
    "text",
    "text_width",
    "track_color",
    "wait_for",
    "wrap",
]


class Align(Enum):
    """Anchor of the given coordinates, mapped to PyUI render modes."""

    TOP_LEFT = "TOP_LEFT_ALIGNED"
    TOP_RIGHT = "TOP_RIGHT_ALIGNED"
    TOP_CENTER = "TOP_CENTER_ALIGNED"
    MIDDLE_LEFT = "MIDDLE_LEFT_ALIGNED"
    MIDDLE_CENTER = "MIDDLE_CENTER_ALIGNED"
    BOTTOM_RIGHT = "BOTTOM_RIGHT_ALIGNED"


@dataclass(frozen=True, slots=True)
class Area:
    """Drawable region between the theme's top and bottom bars.

    Attributes:
        x: Left edge.
        y: Top edge (below the top bar).
        width: Region width.
        height: Region height.
    """

    x: int
    y: int
    width: int
    height: int


def _mode(align: Align) -> object:
    """Return PyUI's ``RenderMode`` for an alignment.

    Args:
        align: Anchor.

    Returns:
        The ``RenderMode`` instance.
    """
    from display.render_mode import RenderMode

    return getattr(RenderMode, align.value)


def screen_size() -> tuple[int, int]:
    """Return the logical screen size.

    Returns:
        ``(width, height)`` in pixels.
    """
    from devices.device import Device

    device = Device.get_device()
    return int(device.screen_width()), int(device.screen_height())


def begin(title: str, hints: Sequence[status_bar.Hint] = ()) -> Area:
    """Start a frame: draw the theme background, the top bar with ``title`` and the bottom bar.

    Args:
        title: Top-bar text.
        hints: Button hints for the bottom bar, e.g. ``[(Button.A, "Full screen")]``.

    Returns:
        The drawable area between the bars.
    """
    from devices.device import Device
    from display.display import Display

    status_bar.set_hints(hints)
    Display.clear(fit_title(title))
    top = Display.get_top_bar_height()
    device = Device.get_device()
    height = device.screen_height() - top - Display.get_bottom_bar_height()
    return Area(0, top, device.screen_width(), height)


def begin_bare() -> Area:
    """Start a frame with nothing but black: no top or bottom bar (full-screen images).

    PyUI always draws the theme's bars, so they are painted over. (A theme that draws its
    bars last, ``renderTopAndBottomBarLast``, would still show them; none on the test devices
    does.)

    Returns:
        The whole screen.
    """
    from display.display import Display

    status_bar.set_hints(())
    Display.clear("")
    width, height = screen_size()
    Display.render_box((0, 0, 0), 0, 0, width, height)
    return Area(0, 0, width, height)


def end() -> None:
    """Show the frame drawn since :func:`begin`."""
    from display.display import Display

    Display.present()


def text(
    value: str,
    x: int,
    y: int,
    role: Text = Text.BODY,
    align: Align = Align.TOP_LEFT,
    *,
    selected: bool = False,
) -> tuple[int, int]:
    """Draw one line of text in the theme's font and colour for ``role``.

    Args:
        value: Text; anything past the first line is dropped.
        x: Anchor x.
        y: Anchor y.
        role: Text role.
        align: Anchor of ``(x, y)``.
        selected: Use the theme's "selected" colour.

    Returns:
        Rendered ``(width, height)``.
    """
    from display.display import Display
    from themes.theme import Theme

    font = font_purpose(role)
    color = Theme.text_color_selected(font) if selected else Theme.text_color(font)
    width, height = Display.render_text(displayable(value, role), x, y, color, font, _mode(align))
    return int(width), int(height)


def wrap(value: str, role: Text, max_width: int) -> list[str]:
    """Split ``value`` into lines that fit ``max_width`` in the font for ``role``.

    Args:
        value: Text to wrap (existing newlines are kept).
        role: Text role.
        max_width: Maximum line width in pixels.

    Returns:
        Lines in order (at least one).
    """
    from display.display import Display

    font = font_purpose(role)
    lines: list[str] = []
    for paragraph in displayable(value, role).splitlines() or [""]:
        current = ""
        for word in paragraph.split():
            candidate = f"{current} {word}".strip()
            width, _ = Display.get_text_dimensions(font, candidate)
            if current and width > max_width:
                lines.append(current)
                current = word
            else:
                current = candidate
        lines.append(current)
    return lines


def line_height(role: Text) -> int:
    """Return the line height of the font for ``role``.

    Args:
        role: Text role.

    Returns:
        Line height in pixels.
    """
    from display.display import Display

    return int(Display.get_line_height(font_purpose(role)))


def image(
    path: Path,
    x: int,
    y: int,
    width: int | None = None,
    height: int | None = None,
    align: Align = Align.TOP_LEFT,
) -> tuple[int, int]:
    """Draw an image, scaled to fit ``width``x``height`` when given.

    Args:
        path: Image file (PNG, JPG, QOI, ...).
        x: Anchor x.
        y: Anchor y.
        width: Maximum width, or ``None`` for natural size.
        height: Maximum height, or ``None`` for natural size.
        align: Anchor of ``(x, y)``.

    Returns:
        Rendered ``(width, height)``; ``(0, 0)`` if the image could not be loaded.
    """
    from display.display import Display

    rendered = Display.render_image(str(path), x, y, _mode(align), width, height)
    return int(rendered[0]), int(rendered[1])


SHARP_COPIES = 4  # enlarged copies kept in the RAM scratch: a preview and a full screen, twice
_sharp: dict[tuple[Path, int, int], Path] = {}


def sharp_scaled(path: Path, max_width: int, max_height: int, scratch: Path) -> Path:
    """Prepare pixel art to fill ``max_width`` x ``max_height`` without blurring it.

    PyUI scales images with linear filtering, which blurs pixel art such as unlock screenshots
    (240x160 on GBA). This returns a copy enlarged with nearest-neighbour by the next whole
    factor above the fit (3x for a GBA screenshot on a 640x480 screen); drawn fitted into the
    box, PyUI then only shrinks it slightly. Emulators call this "sharp bilinear": crisp
    pixels, the whole box used. An exact whole-factor fit is drawn 1:1.

    Screens call this every frame, so the answer is remembered. The copies are BMPs (every SDL
    build can save them) in ``scratch/sharp``, which is RAM on a device: only the newest
    :data:`SHARP_COPIES` are kept, and a deleted one is made again when it's needed.

    Args:
        path: Source image.
        max_width: Box width.
        max_height: Box height.
        scratch: Directory for scaled copies (RAM-backed on devices).

    Returns:
        The enlarged copy, or ``path`` itself when it already fills the box or can't be loaded.
    """
    key = (path, max_width, max_height)
    known = _sharp.get(key)
    if known is not None and (known == path or known.exists()):
        return known
    if len(_sharp) > SHARP_COPIES * 8:
        _sharp.clear()
    folder = scratch / "sharp"
    shown = _enlarge(path, max_width, max_height, folder)
    _sharp[key] = shown
    if shown != path:
        _prune(folder, keep=shown)
    return shown


def _enlarge(path: Path, max_width: int, max_height: int, folder: Path) -> Path:
    """Write the nearest-neighbour enlargement :func:`sharp_scaled` describes.

    Args:
        path: Source image.
        max_width: Box width.
        max_height: Box height.
        folder: Directory for the copy.

    Returns:
        The copy, or ``path`` when no enlargement is needed or possible.
    """
    import sdl2
    from sdl2 import sdlimage

    source = sdlimage.IMG_Load(str(path).encode())
    if not source:
        return path
    try:
        width, height = source.contents.w, source.contents.h
        fit = min(max_width / max(width, 1), max_height / max(height, 1))
        factor = math.ceil(fit - 1e-6)  # an exact fit stays exact
        if factor < 2:  # noqa: PLR2004 — 1x means no enlargement
            return path
        target = folder / f"{path.stem}@{factor}x.bmp"
        if target.exists():
            return target
        scaled = sdl2.SDL_CreateRGBSurfaceWithFormat(
            0, width * factor, height * factor, 32, sdl2.SDL_PIXELFORMAT_ARGB8888
        )
        try:
            sdl2.SDL_SetSurfaceBlendMode(source, sdl2.SDL_BLENDMODE_NONE)
            sdl2.SDL_BlitScaled(source, None, scaled, None)  # nearest-neighbour
            folder.mkdir(parents=True, exist_ok=True)
            if sdl2.SDL_SaveBMP(scaled, str(target).encode()) != 0:
                return path
        finally:
            sdl2.SDL_FreeSurface(scaled)
        return target
    finally:
        sdl2.SDL_FreeSurface(source)


def _prune(folder: Path, *, keep: Path) -> None:
    """Delete all but the newest :data:`SHARP_COPIES` copies in ``folder``.

    Args:
        folder: The copies' directory.
        keep: The copy just made (always kept).
    """
    try:
        copies = sorted(folder.glob("*.bmp"), key=lambda copy: copy.stat().st_mtime, reverse=True)
    except OSError:
        return
    for old in [copy for copy in copies if copy != keep][SHARP_COPIES - 1 :]:
        old.unlink(missing_ok=True)


def box(color: tuple[int, int, int], x: int, y: int, width: int, height: int) -> None:
    """Fill a rectangle.

    Args:
        color: RGB colour.
        x: Left edge.
        y: Top edge.
        width: Width.
        height: Height.
    """
    from display.display import Display

    Display.render_box(color, x, y, width, height)


def accent_color() -> tuple[int, int, int]:
    """Return the theme's colour for selected list text (used for highlights and bars).

    Returns:
        RGB colour.
    """
    from display.font_purpose import FontPurpose
    from themes.theme import Theme

    red, green, blue = tuple(Theme.text_color_selected(FontPurpose.LIST))[:3]
    return int(red), int(green), int(blue)


def chart_color() -> tuple[int, int, int]:
    """Return the colour for chart bars: RA's hardcore gold, unless the theme fights it.

    Returns:
        RGB colour (the theme's text colour where gold wouldn't read).
    """
    from cheevos.ui.pyui.row_bars import page_palette

    return page_palette().hardcore.color


def track_color() -> tuple[int, int, int]:
    """Return the theme's body text colour (chart baselines and other quiet lines).

    Returns:
        RGB colour.
    """
    from display.font_purpose import FontPurpose
    from themes.theme import Theme

    red, green, blue = tuple(Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION))[:3]
    return int(red), int(green), int(blue)


def wait_for(buttons: set[Button]) -> Button | None:
    """Wait one input tick (~1/12 s) for one of ``buttons``.

    Returns ``None`` on timeout so callers can redraw (e.g. live sync progress). Start runs the
    global Start action (sync) unless ``buttons`` claims it.

    Args:
        buttons: Buttons to accept; other presses are ignored.

    Returns:
        The pressed button, or ``None``.
    """
    from controller.controller import Controller

    if not Controller.get_input():
        return None
    pressed = Controller.last_input()
    if pressed is not None and pressed.name == Button.START.value and Button.START not in buttons:
        status_bar.press_start()
        return None
    for button in buttons:
        if pressed is not None and pressed.name == button.value:
            return button
    return None


def ask_text(
    title: str,
    initial: str = "",
    *,
    secret: bool = False,
    hints: Sequence[status_bar.Hint] = (),
) -> str | None:
    """Ask for text with PyUI's on-screen keyboard.

    Args:
        title: Prompt shown above the keyboard.
        initial: Text to start with.
        secret: The text is a secret (the API key). PyUI logs any text it fails to draw, which
            happens when memory runs low, so its log is muted while the keyboard is open.
        hints: Button hints for the bottom bar (PyUI's keyboard shows none).

    Returns:
        The entered text, or ``None`` if the user cancelled.
    """
    from display.on_screen_keyboard import OnScreenKeyboard
    from utils.logger import PyUiLogger

    pyui_log = PyUiLogger.get_logger()
    was_disabled = pyui_log.disabled
    pyui_log.disabled = was_disabled or secret
    try:
        # Start submits the text here, so the status and its Start action step aside.
        with status_bar.hidden(), status_bar.hints(hints), _full_width_entry():
            result = OnScreenKeyboard().get_input(title, initial)
    finally:
        pyui_log.disabled = was_disabled
    return None if result is None else str(result)


@contextlib.contextmanager
def _full_width_entry() -> Iterator[None]:
    """Stretch the keyboard's text field across the screen while the keyboard is open.

    PyUI draws the field with the theme's list highlight (640x90 in SPRUCE at 640x480), a
    sixteenth of the screen width tall at its natural aspect, so the field covers only 44% of
    the width and a 32-character key runs past it. A swatch in the field's colour, 16:1 like
    that height, scales to the full width. Every tested theme's highlight is a flat colour.

    Yields:
        Nothing.
    """
    from display.display import Display
    from themes.theme import Theme

    original = vars(Theme).get("keyboard_entry_bg")
    image = Theme.keyboard_entry_bg()
    if original is None or not image:
        yield
        return
    page_image = Display.bg_path or Theme.background()
    page = generated.average_color(str(page_image)) if page_image else (0, 0, 0)
    field = str(generated.swatch(generated.average_color(str(image), page), 255))
    Theme.keyboard_entry_bg = staticmethod(lambda: field)
    try:
        yield
    finally:
        Theme.keyboard_entry_bg = original
