"""Sync status, button hints and the global Start action in PyUI's bottom bar.

PyUI draws the theme's bottom bar (background, A/B hints, "3/12" index) on every frame, and
we don't control its views' render loops. So for the app's lifetime the bridge wraps the
bottom bar's render method: after the theme has drawn its bar, it adds a status (icon and
text) and button hints such as "[START] Sync" or "[SELECT] Details", after the theme's own
hints (or centred when the theme hides them, as SPRUCE does). The screens layer supplies the
status through a :data:`StatusSource`; each screen sets its own hints (``choose(hints=...)``,
``begin(hints=...)``).

Start is handled here too: :func:`press_start` runs the installed action, and ``choose`` and
``wait_for`` call it on every screen, so screens need no code for it.
"""

from __future__ import annotations

import contextlib
import logging
from collections.abc import Callable, Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from cheevos.ui.pyui import glyphs
from cheevos.ui.pyui.bar_layout import HintSize, Metrics, Placement, place
from cheevos.ui.pyui.buttons import Button
from cheevos.ui.pyui.text import Text, fit_text, font_purpose, text_width

logger = logging.getLogger(__name__)

_PAD = 5  # PyUI's own bottom-bar padding (render_standard_bottom_bar)
_EDGE = 12  # from the screen edge or the theme's hints
# Theme hints that end past this share of the width were pushed off-screen on purpose
# (SPRUCE draws 640 px wide transparent A/B icons), so the whole strip is free.
_HIDDEN_HINTS_SHARE = 0.6
_INDEX_SAMPLE = "000/0000"  # room kept for PyUI's index text, bottom-right
_OPAQUE = 255  # alpha that makes PyUI draw text without caching its texture

Hint = tuple[Button, str]  # button and what it does, e.g. (Button.SELECT, "Details")


@dataclass(frozen=True, slots=True)
class BarStatus:
    """What the bottom bar says about sync.

    Attributes:
        text: Status line, e.g. "Synced 5 min ago" (shortened to fit).
        icon: Image left of the text, drawn at its natural size.
        action: Label of the Start hint, e.g. "Sync"; empty for no hint.
        live: The text changes every few frames (progress). PyUI caches a texture for every
            string it draws and never evicts them, so live text is drawn uncached.
    """

    text: str
    icon: Path | None = None
    action: str = ""
    live: bool = False


# Called on every bottom-bar draw with ``detailed`` (see :func:`detailed`). ``None``: no status.
StatusSource = Callable[[bool], BarStatus | None]


class _Bar:
    """The installed status source, Start action and hints, plus per-theme measurements.

    Args:
        source: Supplies the status on every draw.
        on_start: Runs when Start is pressed.
    """

    def __init__(self, source: StatusSource, on_start: Callable[[], None]) -> None:
        self.source = source
        self.on_start = on_start
        self.detailed = False
        self.hidden = 0
        self.hints: tuple[Hint, ...] = ()
        self._space: tuple[int, int, bool] | None = None
        self._widths: dict[Path, int] = {}

    def _measure_space(self) -> tuple[int, int, bool]:
        """Find the free part of the strip (once per theme).

        Replicates PyUI's ``render_standard_bottom_bar`` to find where its hints end.

        Returns:
            ``(left, right, centred)``.
        """
        from devices.device import Device
        from display.display import Display
        from display.font_purpose import FontPurpose
        from menus.language.language import Language
        from themes.theme import Theme

        width = int(Device.get_device().screen_width())
        ends = _PAD + int(Display.get_image_dimensions(Theme.confirm_icon())[0]) + _PAD
        if Theme.show_bottom_bar_buttons():
            font = FontPurpose.DESCRIPTIVE_LIST_TITLE
            confirm = Language.label("confirmText", Theme.confirm_text())
            back = Language.label("backText", Theme.back_text())
            ends += int(Display.get_text_dimensions(font, confirm)[0]) + _PAD
            ends += int(Display.get_image_dimensions(Theme.back_icon())[0]) + _PAD
            ends += int(Display.get_text_dimensions(font, back)[0]) + _PAD
        centred = ends > width * _HIDDEN_HINTS_SHARE
        index = int(Display.get_text_dimensions(FontPurpose.LIST_TOTAL, _INDEX_SAMPLE)[0])
        return (_EDGE if centred else ends + _EDGE), width - index - _EDGE * 2, centred

    def _width(self, path: Path | None) -> int:
        """Return an image's width (PyUI loads the file to measure it, so it's cached).

        Args:
            path: Image, or ``None``.

        Returns:
            Width in pixels (0 for ``None``).
        """
        if path is None:
            return 0
        if path not in self._widths:
            from display.display import Display

            self._widths[path] = int(Display.get_image_dimensions(str(path))[0])
        return self._widths[path]

    def draw(self, bar_height: int) -> None:
        """Draw the status and hints over the bar PyUI just drew.

        Args:
            bar_height: Height of the bar as drawn.
        """
        from devices.device import Device
        from display.display import Display
        from display.render_mode import RenderMode
        from themes.theme import Theme

        status = None if self.hidden else self.source(self.detailed)
        hints = [(Button.START, status.action)] if status and status.action else []
        hints += self.hints
        if status is None and not hints:
            return
        if self._space is None:
            self._space = self._measure_space()
        left, right, centred = self._space
        icon = status.icon if status else None
        width, height = Device.get_device().screen_width(), Device.get_device().screen_height()
        metrics = Metrics(int(width), left, right, centred, self._width(icon))
        glyph_paths = [glyphs.glyph(button) for button, _ in hints]
        sizes = [
            HintSize(self._width(path), label if path else f"{button.name.title()}: {label}")
            for (button, label), path in zip(hints, glyph_paths, strict=True)
        ]
        placement: Placement | None = place(
            status.text if status else "",
            icon=icon is not None,
            hints=sizes,
            metrics=metrics,
            measure=lambda value: text_width(value, Text.BODY),
            fit=lambda value, room: fit_text(value, Text.BODY, room),
        )
        if placement is None:
            return
        mid = int(height) - bar_height // 2
        mode = RenderMode.MIDDLE_LEFT_ALIGNED
        font = font_purpose(Text.BODY)
        color = Theme.text_color(font)
        if placement.icon_x is not None and icon is not None:
            Display.render_image(str(icon), placement.icon_x, mid, mode)
        alpha = _OPAQUE if status and status.live else None
        Display.render_text(placement.text, placement.text_x, mid, color, font, mode, alpha=alpha)
        for hint in placement.hints:
            path = glyph_paths[hint.index]
            if hint.glyph_x is not None and path is not None:
                Display.render_image(str(path), hint.glyph_x, mid, mode)
            Display.render_text(hint.label, hint.label_x, mid, color, font, mode)


_bar: _Bar | None = None


def _wrap_render(bar: _Bar, original: Callable[..., Any]) -> Callable[..., Any]:
    """Wrap PyUI's ``BottomBar.render_bottom_bar`` so the status follows the theme's bar.

    Args:
        bar: Installed state.
        original: PyUI's bound method.

    Returns:
        The replacement.
    """
    from display.display import Display

    def render_bottom_bar(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401 — PyUI signature
        """Let PyUI draw the bar, then add the status unless the bar is busy or covered."""
        result = original(*args, **kwargs)
        text = args[0] if args else kwargs.get("bottom_bar_text")
        # Skip when PyUI shows its own bar text, or while a popup's frozen backdrop (which
        # already holds the status) is on screen.
        if text is None and Display.bg_canvas is None:
            height = int(Display.bottom_bar.get_bottom_bar_height())
            if height > 0:
                try:
                    bar.draw(height)
                except Exception:  # a broken status must never take the screen down
                    logger.exception("Could not draw the bottom-bar status")
        return result

    return render_bottom_bar


@contextlib.contextmanager
def installed(source: StatusSource, on_start: Callable[[], None]) -> Iterator[None]:
    """Show the status and hints on every screen and handle Start for the duration of the block.

    Args:
        source: Supplies the status on every draw.
        on_start: Runs when Start is pressed on any screen (popups excepted).

    Yields:
        Nothing.
    """
    global _bar  # noqa: PLW0603 — PyUI's display is a process-wide singleton too
    from display.display import Display

    target = Display.bottom_bar
    original = getattr(target, "render_bottom_bar", None)
    if original is None:
        logger.warning("PyUI has no bottom-bar renderer; sync status stays hidden")
        yield
        return
    glyphs.reset()
    _bar = _Bar(source, on_start)
    target.render_bottom_bar = _wrap_render(_bar, original)
    try:
        yield
    finally:
        del target.render_bottom_bar  # back to the class method
        _bar = None


@contextlib.contextmanager
def detailed(enabled: bool = True) -> Iterator[None]:  # noqa: FBT001, FBT002 — a mode switch
    """Ask the status source for the detailed status (with hints) during the block.

    Args:
        enabled: Detailed (home, settings) or progress only (every other screen).

    Yields:
        Nothing.
    """
    bar = _bar
    if bar is None:
        yield
        return
    previous, bar.detailed = bar.detailed, enabled
    try:
        yield
    finally:
        bar.detailed = previous


def set_hints(hints: Sequence[Hint]) -> None:
    """Show these button hints until a screen sets others (custom screens, every frame).

    Args:
        hints: Buttons and what they do, most important first.
    """
    if _bar is not None:
        _bar.hints = tuple(hints)


@contextlib.contextmanager
def hints(shown: Sequence[Hint]) -> Iterator[None]:
    """Show these button hints during the block (list views).

    Args:
        shown: Buttons and what they do, most important first.

    Yields:
        Nothing.
    """
    bar = _bar
    if bar is None:
        yield
        return
    previous, bar.hints = bar.hints, tuple(shown)
    try:
        yield
    finally:
        bar.hints = previous


@contextlib.contextmanager
def hidden() -> Iterator[None]:
    """Hide the status and the Start action during the block; hints still show.

    For the on-screen keyboard, where Start submits the text.

    Yields:
        Nothing.
    """
    bar = _bar
    if bar is None:
        yield
        return
    bar.hidden += 1
    try:
        yield
    finally:
        bar.hidden -= 1


def press_start() -> bool:
    """Run the Start action, if one is installed.

    Returns:
        ``True`` if the press was handled.
    """
    if _bar is None or _bar.hidden:
        return False
    _bar.on_start()
    return True
