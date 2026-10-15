"""Typed wrappers around PyUI's standard list and grid views."""

from __future__ import annotations

import contextlib
import logging
import time
from collections.abc import Callable, Iterator, Sequence
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import TYPE_CHECKING, Any

from cheevos.ui.pyui import image_frames, row_bars, status_bar, title_bar
from cheevos.ui.pyui.image_frames import Frame
from cheevos.ui.pyui.primitives import (
    Button,
    Text,
    displayable,
    fit_text,
    fit_with_tail,
    screen_size,
)
from cheevos.ui.pyui.row_bars import Progress
from cheevos.ui.pyui.status_bar import Hint
from cheevos.ui.pyui.text import ListRoom, list_room
from cheevos.ui.pyui.title_bar import Title
from cheevos.ui.pyui.visible_images import ImageDemand, VisibleImages, demanding

if TYPE_CHECKING:
    from cheevos.ui.pyui.badge_grid import Details

logger = logging.getLogger(__name__)

# The theme's list rows at its 640x480 design (SPRUCE): sizes scale like them (theme_scale).
_REFERENCE_ROW = 90
# Log list preparation times for big lists or slow builds (performance diagnostics on devices).
_SLOW_LIST_ROWS = 100
_SLOW_LIST_MS = 200

# A lazily resolved image: called when the row is drawn, so only visible rows pay for it and
# an image that arrives in the background shows up on the next frame.
IconSource = Path | Callable[[], Path | None] | None


@dataclass(frozen=True, slots=True)
class MenuItem:
    """One row of a list, or one tile of a grid.

    Attributes:
        title: Primary text.
        description: Secondary line under the title (lists only; may be empty).
        icon: Image left of the text (lists) or the tile image (grids): a path, or a callable
            returning one when the row is drawn.
        value: Right-aligned text, e.g. ``"2/138"`` (lists only; may be empty).
        key: Caller-defined identifier, returned unchanged on selection.
        progress: A progress bar shown instead of the description (lists only).
        frame: Outline outside the image (lists, grids and the carousel; RA's colours).
        details: Second line under a badge grid while the tile is selected (badge grids only;
            the first is the title and ``value``).
        tail: Kept whole after the description, e.g. a date: the description is shortened
            first (lists and the carousel).
    """

    title: str
    description: str = ""
    icon: IconSource = None
    value: str = ""
    key: str = ""
    progress: Progress | None = None
    frame: Frame | None = None
    details: Details | None = None
    tail: str = ""


@dataclass(frozen=True, slots=True)
class Choice:
    """The user's pick.

    Attributes:
        item: Selected item.
        index: Its position in the list.
        button: Button that confirmed it (A, or one of the extra buttons).
    """

    item: MenuItem
    index: int
    button: Button


class Layout(Enum):
    """Supported PyUI view types."""

    LIST = "ICON_AND_DESC"
    BADGES = "BADGES"  # compact badge grid with the selection's details (badge_grid.py)
    CAROUSEL = "CAROUSEL"  # animated carousel with the selection's details (carousel.py)
    POPUP = "POPUP"  # small menu over the current screen (options, filters)


# Called on every input timeout (~12x/s). Returning items replaces the list in place.
TickHandler = Callable[[], Sequence[MenuItem] | None]


def _lazy(source: Callable[[], Path | None]) -> Callable[[object], str | None]:
    """Adapt a lazy icon source to PyUI's searcher signature (it passes the entry value).

    Args:
        source: Callable returning the image path.

    Returns:
        A PyUI icon/image searcher.
    """

    def search(_value: object) -> str | None:
        """Resolve the image when PyUI draws the entry."""
        path = source()
        return str(path) if path else None

    return search


def _entry(item: MenuItem, *, room: ListRoom | None) -> Any:  # noqa: ANN401
    """Convert one item into a PyUI ``GridOrListEntry``.

    Args:
        item: Row or tile.
        room: A list row's room: the title is shortened so it never runs into the
            right-aligned value, and the description keeps its tail (lists only).

    Returns:
        The PyUI entry, carrying the item as its value.
    """
    from views.grid_or_list_entry import GridOrListEntry

    icon = item.icon
    static = str(icon) if isinstance(icon, Path) else None
    searcher = None if icon is None or isinstance(icon, Path) else _lazy(icon)
    if room is not None:
        title = fit_text(item.title, Text.TITLE, room.title(item.value))
        description = (
            fit_with_tail(item.description, item.tail, Text.BODY, room.full)
            if item.description or item.tail
            else ""
        )
    else:
        title = displayable(item.title, Text.TITLE)
        description = displayable(item.description, Text.BODY)
    if item.progress is not None:
        description = ""  # keeps the two-line row; the bar is drawn in its place
    return GridOrListEntry(
        primary_text=title,
        value_text=item.value or None,
        description=None if not description and item.progress is None else description,
        icon=static,
        image_path=static,
        icon_searcher=searcher,
        image_path_searcher=searcher,
        image_path_selected_searcher=searcher,
        value=item,
    )


def _entries(items: Sequence[MenuItem], layout: Layout = Layout.LIST) -> list[Any]:
    """Convert items into PyUI entries.

    Args:
        items: Rows or tiles.
        layout: Target view; list titles are fitted next to their values.

    Returns:
        PyUI entries in the same order.
    """
    room = list_room() if layout is Layout.LIST else None
    return [_entry(item, room=room) for item in items]


def _sample_row(entries: Sequence[Any]) -> Any:  # noqa: ANN401 — PyUI entry
    """Make one entry as tall as the tallest of ``entries`` when PyUI measures it.

    SDL_ttf sizes a line by its glyphs (in practice, the font's line height), so a title
    holding every character of the measured titles, over a description holding every
    character of their descriptions, is at least as tall as any row.

    Args:
        entries: A list's entries. PyUI measures those with a description.

    Returns:
        The sample entry.
    """
    from views.grid_or_list_entry import GridOrListEntry

    described = [entry for entry in entries if entry.get_description() is not None]
    if not described:
        return GridOrListEntry(primary_text="")
    titles = "".join(entry.get_primary_text() or "" for entry in described)
    descriptions = "".join(entry.get_description() for entry in described)
    return GridOrListEntry(
        primary_text="".join(set(titles)), description="".join(set(descriptions))
    )


@contextlib.contextmanager
def _one_sample_row() -> Iterator[None]:
    """Let PyUI measure a new list's row height on one sample row instead of every row.

    PyUI's ``_calculate_line_height`` sizes every row's title and description with SDL_ttf to
    find the tallest: 0.66 s for 2,940 games on a Mini (.agents/pyui.md, "Row height").
    Our rows share one layout, so a sample row measures the same (:func:`_sample_row`).
    Lists that measure their icons too keep PyUI's way.

    Yields:
        Nothing.
    """
    from views.list_view import ListView

    original = ListView._calculate_line_height

    def calculate(view: Any, include_description_line: bool) -> Any:  # noqa: ANN401, FBT001
        """Measure the sample row in place of the view's rows."""
        if getattr(view, "use_icons_to_calculate_line_height", True):
            return original(view, include_description_line)
        rows = view.options
        view.options = [_sample_row(rows)]
        try:
            return original(view, include_description_line)
        finally:
            view.options = rows

    ListView._calculate_line_height = calculate
    try:
        yield
    finally:
        ListView._calculate_line_height = original


def theme_scale() -> float:
    """Return how much bigger the theme draws than its 640x480 design (its list rows' height).

    Returns:
        The scale (1.0 at 640x480 in SPRUCE).
    """
    from display.display import Display
    from themes.theme import Theme

    list_row = int(Display.get_image_dimensions(Theme.get_list_large_selected_bg())[1])
    if list_row:
        return list_row / _REFERENCE_ROW
    width, height = screen_size()
    return min(width / 640, height / 480)


def choose(  # noqa: PLR0913 — keyword-only presentation options
    title: str | Title,
    items: Sequence[MenuItem],
    *,
    selected: int = 0,
    buttons: frozenset[Button] = frozenset({Button.A}),
    layout: Layout = Layout.LIST,
    on_tick: TickHandler | None = None,
    full_status: bool = False,
    hints: Sequence[Hint] = (),
) -> Choice | None:
    """Show a themed list or grid and wait for a choice.

    Start runs the global Start action (sync) and keeps the view open, unless ``buttons``
    claims it. Popups ignore it.

    Args:
        title: Top-bar text, or a :class:`Title` whose tail always shows (a game's count,
            and its award dot).
        items: Rows (list) or tiles (grid), in order. Must not be empty.
        selected: Initially highlighted index.
        buttons: Buttons that confirm a choice (B always backs out).
        layout: List with icons and descriptions, compact badge grid (``badge_grid``), carousel
            (``carousel``) or popup menu.
        on_tick: Called on each input timeout; returned items replace the current ones.
        full_status: Show the detailed sync status in the bottom bar (home, settings), not
            only progress.
        hints: Button hints for the bottom bar, e.g. ``[(Button.SELECT, "Details")]``.

    Returns:
        The choice, or ``None`` when B is pressed.
    """
    view = PreparedView(title, items, selected=selected, layout=layout)
    return view.show(buttons=buttons, on_tick=on_tick, full_status=full_status, hints=hints)


class PreparedView:
    """A list, grid or carousel, prepared once and shown as often as needed (see :func:`choose`).

    Preparing a big list is the slow part: 0.9 s for 2,940 games on a Mini, against 60 ms to
    show it again. A screen that comes back to the same rows (the games list, back from a game)
    keeps its view and shows it again, with the selection and scroll position it had. A popup
    can be shown only once: its backdrop is the frame under it when it was prepared.

    Args:
        title: Top-bar text, or a :class:`Title` whose tail always shows (a game's count,
            and its award dot).
        items: Rows (list) or tiles (grid), in order. Must not be empty.
        selected: Initially highlighted index.
        layout: List with icons and descriptions, compact badge grid (``badge_grid``), carousel
            (``carousel``) or popup menu.
    """

    def __init__(
        self,
        title: str | Title,
        items: Sequence[MenuItem],
        *,
        selected: int = 0,
        layout: Layout = Layout.LIST,
    ) -> None:
        from views.view_creator import ViewCreator
        from views.view_type import ViewType

        started = time.monotonic()
        self._title = title
        self._layout = layout
        self._count = len(items)
        self._entries = _entries(items, layout)
        top = title_bar.top_title(title)
        # The grid and the carousel load when first shown: Home doesn't need them.
        if layout is Layout.BADGES:
            from cheevos.ui.pyui import badge_grid

            self._view = badge_grid.create(top, self._entries, selected, theme_scale())
        elif layout is Layout.CAROUSEL:
            from cheevos.ui.pyui import carousel

            self._view = carousel.create(top, self._entries, selected, theme_scale())
        else:
            # PyUI asks every row for its image and measures every row's text here.
            with demanding(ImageDemand.MEASURED), _one_sample_row():
                self._view = ViewCreator.create_view(
                    view_type=ViewType[layout.value],
                    top_bar_text=top,
                    options=self._entries,
                    selected_index=selected,
                )
        if layout is Layout.LIST and any(item.progress is not None for item in items):
            row_bars.attach(self._view)
        if layout is Layout.LIST:
            image_frames.attach_list(self._view)
        # The carousel follows its own images (its window wraps around the list).
        tracked = layout not in (Layout.POPUP, Layout.CAROUSEL)
        grid = layout is Layout.BADGES
        self._images = VisibleImages(self._view, self._entries, grid=grid) if tracked else None
        self._shown = False
        elapsed_ms = (time.monotonic() - started) * 1000
        if len(self._entries) > _SLOW_LIST_ROWS or elapsed_ms > _SLOW_LIST_MS:
            logger.info("Prepared %d rows in %.0f ms", len(self._entries), elapsed_ms)

    def show(
        self,
        *,
        buttons: frozenset[Button] = frozenset({Button.A}),
        on_tick: TickHandler | None = None,
        full_status: bool = False,
        hints: Sequence[Hint] = (),
    ) -> Choice | None:
        """Show the view and wait for a choice (see :func:`choose`).

        Args:
            buttons: Buttons that confirm a choice (B always backs out).
            on_tick: Called on each input timeout; returned items replace the current ones.
            full_status: Show the detailed sync status in the bottom bar, not only progress.
            hints: Button hints for the bottom bar.

        Returns:
            The choice, or ``None`` when B is pressed.
        """
        from controller.controller_inputs import ControllerInput

        accepted = [ControllerInput[button.value] for button in buttons] + [ControllerInput.B]
        global_start = self._layout is not Layout.POPUP and Button.START not in buttons
        if global_start:
            accepted.append(ControllerInput.START)
        if self._shown:
            # The top bar forgot this title's award dot when other screens drew theirs, and
            # those screens moved the image downloads to their own rows.
            self._view.top_bar_text = title_bar.top_title(self._title)
            if self._images is not None:
                self._images.resume()
        self._shown = True
        try:
            with status_bar.detailed(full_status), status_bar.hints(hints):
                return self._select(accepted, on_tick, global_start=global_start)
        finally:
            # Popups freeze the frame underneath as their backdrop until told they're done;
            # without this, every later screen is drawn over that frozen frame.
            finished = getattr(self._view, "view_finished", None)
            if finished is not None:
                finished()

    def _select(
        self, accepted: list[Any], on_tick: TickHandler | None, *, global_start: bool
    ) -> Choice | None:
        """Run PyUI's selection loop until a confirming button or B.

        Args:
            accepted: Controller inputs that end the loop (B included).
            on_tick: Called on each input timeout; returned items replace the current ones.
            global_start: Start runs the global Start action instead of ending the loop.

        Returns:
            The choice, or ``None`` when B is pressed.
        """
        from controller.controller_inputs import ControllerInput

        view = self._view
        while True:
            selection = view.get_selection(accepted)
            # PyUI returns a Selection with no input after a timeout or a cursor move.
            if selection is None or selection.get_input() is None:
                if on_tick is not None and (updated := on_tick()) is not None:
                    self._entries = _entries(updated, self._layout)
                    view.set_options(self._entries)
                    if self._images is not None:
                        self._images.reset(self._entries)
                continue
            if selection.get_input() == ControllerInput.B:
                return None
            if global_start and selection.get_input() == ControllerInput.START:
                status_bar.press_start()
                continue
            item = selection.get_selection().get_value()
            # A short carousel repeats its entries: map the selection back to the items.
            index = selection.get_index() % max(self._count, 1)
            return Choice(item, index, Button(selection.get_input().name))
