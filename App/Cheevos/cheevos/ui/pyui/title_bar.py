"""A game's top-bar title: its name shortened around the count, and RA's award dot.

PyUI draws one title string, centred in the top bar. A :class:`Title` keeps its tail (a game's
"90/138") whole and shortens only the name, so the count always shows. With an award, the string
leaves a run of spaces between the two, and a hook on the top bar's render method draws a
scaled bundled award PNG there (.agents/pyui.md). The gap includes its halo. PyUI always gets
the whole readable title, so when the hook draws nothing (a theme hides the title or shows tabs),
only the dot is missing.

A dot belongs to one exact title string. The hook forgets it the first time the top bar shows
any other title (the next screen), so no other screen gets a stale dot. Popups over the screen
redraw the same title over their frozen backdrop, so the dot stays under them.
"""

from __future__ import annotations

import contextlib
import logging
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from typing import Any

from cheevos.core.models import AwardKind
from cheevos.ui.pyui import award_images, row_bars
from cheevos.ui.pyui.text import Text, displayable, fit_text, fit_title, text_width, title_room

logger = logging.getLogger(__name__)

_DOT_PAD = 8  # between the award dot and the text on each side
_DOT_SHARE = 0.45  # circle diameter per title font height


@dataclass(frozen=True, slots=True)
class Title:
    """A top-bar title whose tail must stay visible.

    Attributes:
        name: Shortened with an ellipsis when the whole title doesn't fit (a game's title).
        tail: Always shown in full after the name, e.g. ``"90/138"``.
        award: RA's award dot, drawn between the two; without one, a space separates them.
    """

    name: str
    tail: str
    award: AwardKind | None = None


@dataclass(slots=True)
class _Dot:
    """An award dot to draw under one exact title.

    Attributes:
        text: The title string PyUI draws.
        name: Its part before the gap.
        tail: Its part after the gap.
        award: Which dot.
        size: Diameter.
        x: Left edge, measured on the first draw.
        image: Static image path, picked on the first draw.
        canvas: Scaled image width, including the halo.
    """

    text: str
    name: str
    tail: str
    award: AwardKind
    size: int
    x: int | None = None
    image: str | None = None
    canvas: int = 0


_dot: _Dot | None = None


def gap_spaces(dot: int, space: int) -> int:
    """Return how many spaces leave room for the award dot and its padding.

    Args:
        dot: Image width, including any halo.
        space: Width of a space in the title font.

    Returns:
        Number of spaces.
    """
    return -(-(dot + 2 * _DOT_PAD) // max(space, 1))


def compose(
    title: Title,
    *,
    room: int,
    dot: int,
    measure: Callable[[str], int],
    fit: Callable[[str, int], str],
) -> tuple[str, str, str]:
    """Lay out a title in the room the top bar leaves it, shortening only the name.

    Args:
        title: Name, tail and award (the tail already drawable).
        room: Width the top bar leaves the title.
        dot: Award image width, including any halo.
        measure: Text width in pixels.
        fit: Shortens text to a pixel width.

    Returns:
        ``(name, gap, tail)``: the shortened name, the spaces between, and the tail.
    """
    gap = " " * gap_spaces(dot, measure(" ")) if title.award is not None else " "
    return fit(title.name, room - measure(gap + title.tail)), gap, title.tail


def dot_x(screen_width: int, text: int, name: int, tail: int, dot: int) -> int:
    """Return the left edge of a dot centred in the gap of a title PyUI centres on screen.

    PyUI draws the title ``MIDDLE_CENTER_ALIGNED`` at ``int(screen_width / 2)``
    (``TopBar.render_top_bar_menu_not_skipped``), so it starts half its width left of that.

    Args:
        screen_width: Screen width.
        text: Width of the whole title.
        name: Width of its name.
        tail: Width of its tail.
        dot: Dot diameter.

    Returns:
        X of the dot's left edge.
    """
    left = int(screen_width / 2) - text // 2
    return (2 * left + name + text - tail) // 2 - dot // 2


def top_title(title: str | Title) -> str:
    """Return the string PyUI should draw as the title; an award's dot is drawn under it.

    The dot is drawn while the top bar shows exactly this string (see the module docstring).

    Args:
        title: Plain text (shortened at its end), or a :class:`Title`.

    Returns:
        The title text.
    """
    global _dot  # noqa: PLW0603 — one top bar, one title at a time
    text, dot = _prepare(title)
    if dot is not None:
        _dot = dot
    return text


def _prepare(title: str | Title) -> tuple[str, _Dot | None]:
    """Turn a title into the string PyUI draws, plus the award dot to draw under it.

    Args:
        title: Plain text (shortened at its end), or a :class:`Title`.

    Returns:
        ``(text, dot)``; ``dot`` is ``None`` without an award.
    """
    if isinstance(title, str) or not title.tail:
        return fit_title(title if isinstance(title, str) else title.name), None
    from display.display import Display
    from display.font_purpose import FontPurpose

    line = int(Display.get_text_dimensions(FontPurpose.TOP_BAR_TEXT, "A")[1])
    size = max(round(line * _DOT_SHARE), 6)
    canvas = award_images.canvas_size(title.award, size) if title.award is not None else size
    tail = displayable(title.tail, Text.HEADING)
    name, gap, tail = compose(
        Title(title.name, tail, title.award),
        room=title_room(),
        dot=canvas,
        measure=lambda value: text_width(value, Text.HEADING),
        fit=lambda value, width: fit_text(value, Text.HEADING, width),
    )
    text = name + gap + tail
    if title.award is None:
        return text, None
    return text, _Dot(text, name, tail, title.award, size, canvas=canvas)


@contextlib.contextmanager
def installed() -> Iterator[None]:
    """Draw award dots under their titles for the duration of the block (the app's lifetime).

    Yields:
        Nothing.
    """
    global _dot  # noqa: PLW0603 — PyUI's display is a process-wide singleton too
    from display.display import Display

    target = Display.top_bar
    original = getattr(target, "render_top_bar", None)
    if original is None:
        logger.warning("PyUI has no top-bar renderer; award dots stay hidden")
        yield
        return
    target.render_top_bar = _wrap_render(target, original)
    try:
        yield
    finally:
        del target.render_top_bar  # back to the class method
        _dot = None


def _wrap_render(bar: Any, original: Callable[..., Any]) -> Callable[..., Any]:  # noqa: ANN401
    """Wrap PyUI's ``TopBar.render_top_bar`` so a dot follows its title.

    Args:
        bar: PyUI's top bar.
        original: Its bound render method.

    Returns:
        The replacement.
    """

    def render_top_bar(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401 — PyUI signature
        """Let PyUI draw the bar and title, then add the dot if this is still its title."""
        global _dot  # noqa: PLW0603 — forgotten once another title shows, or after a failure
        result = original(*args, **kwargs)
        dot = _dot
        if dot is None:
            return result
        title = args[0] if args else kwargs.get("title")
        if title != dot.text:  # another screen: the dot isn't needed any more
            _dot = None
            return result
        try:
            _draw(bar, dot)
        except Exception:  # the dot is decoration; never take the screen down
            logger.exception("Could not draw the award dot; hiding it on this screen")
            _dot = None
        return result

    return render_top_bar


def _draw(bar: Any, dot: _Dot) -> None:  # noqa: ANN401 — PyUI's top bar
    """Draw the dot in its title's gap, unless PyUI didn't draw the title this frame.

    Args:
        bar: PyUI's top bar, just rendered (``top_bar_h`` is its height).
        dot: The dot.
    """
    from devices.device import Device
    from display.display import Display
    from display.font_purpose import FontPurpose
    from display.render_mode import RenderMode
    from themes.theme import Theme

    if Theme.skip_main_menu() or not Theme.show_top_bar_text():  # tabs, or no title drawn
        return
    height = int(getattr(bar, "top_bar_h", 0) or 0)
    if height <= 0:
        return
    if dot.x is None:  # measured once per screen, with SDL_ttf as PyUI does

        def measure(value: str) -> int:
            """Width of top-bar text as PyUI draws it."""
            return int(Display.get_text_dimensions(FontPurpose.TOP_BAR_TEXT, value)[0])

        width = int(Device.get_device().screen_width())
        dot.x = dot_x(width, measure(dot.text), measure(dot.name), measure(dot.tail), dot.size)
        dot.image = award_images.images(row_bars.top_bar_palette()).get(dot.award)
        dot.canvas = award_images.canvas_size(dot.award, dot.size)
    if dot.image is not None:
        Display.render_image(
            dot.image,
            dot.x + dot.size // 2,
            height // 2,
            RenderMode.MIDDLE_CENTER_ALIGNED,
            dot.canvas,
            dot.canvas,
        )
