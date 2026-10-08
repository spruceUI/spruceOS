"""Keep image downloads on the rows a list or grid shows (.agents/sync-and-storage.md).

The views ask the app's ``MediaResolver`` for images through lazy searchers. This module tells
it how much each request matters (:class:`ImageDemand`) and re-targets downloads when the
visible rows change (:class:`VisibleImages`).
"""

from __future__ import annotations

import contextlib
import logging
from collections.abc import Callable, Iterator, Sequence
from dataclasses import dataclass
from enum import Enum
from typing import Any

logger = logging.getLogger(__name__)


class ImageDemand(Enum):
    """How much the screen needs the image it's asking for (``MediaResolver.resolve``)."""

    SHOWN = "shown"  # drawn now: download it ahead of anything waiting
    NEXT = "next"  # the next page: download it after what's on screen
    MEASURED = "measured"  # PyUI scanning rows it won't draw yet: no download, no extraction


@dataclass(slots=True)
class _ImageHooks:
    """How the views reach the app's images (set with :func:`track_images`).

    Attributes:
        version: Changes whenever a new image becomes available.
        new_window: Drops downloads waiting for rows that scrolled away.
        demand: What image requests are for right now (UI thread only).
    """

    version: Callable[[], int] = lambda: 0
    new_window: Callable[[], None] = lambda: None
    demand: ImageDemand = ImageDemand.SHOWN


_hooks = _ImageHooks()


def track_images(version: Callable[[], int], new_window: Callable[[], None]) -> None:
    """Connect the views to the app's images.

    Args:
        version: Returns a number that changes whenever a new image becomes available
            (``MediaResolver.version``).
        new_window: Drops downloads queued for rows no longer shown
            (``MediaResolver.new_window``).
    """
    _hooks.version = version
    _hooks.new_window = new_window


def image_demand() -> ImageDemand:
    """Return what image requests are for right now (passed to ``MediaResolver``)."""
    return _hooks.demand


@contextlib.contextmanager
def demanding(demand: ImageDemand) -> Iterator[None]:
    """Mark the image requests made during the block.

    Args:
        demand: What they are for.

    Yields:
        Nothing.
    """
    previous, _hooks.demand = _hooks.demand, demand
    try:
        yield
    finally:
        _hooks.demand = previous


class VisibleImages:
    """Keeps a view's image downloads on the rows it shows (.agents/sync-and-storage.md).

    PyUI asks every row for its image when it builds a list (to pick the selection style), so
    opening a list used to queue downloads for all its rows, top to bottom, and a jump to the
    end waited for everything above. Now ``choose`` marks that scan ``MEASURED`` (no
    downloads), and after each frame this:

    - when the visible window moved, drops the downloads queued for the old one, asks for the
      visible rows' images again (ahead of anything else) and queues the next page in the
      scroll direction behind them;
    - lets a grid's visible tiles ask again when images arrive: PyUI keeps a tile's image path
      from the first time it draws the tile (``GridOrListEntry`` drops its searcher).

    Args:
        view: The list or grid; its ``_render`` is wrapped.
        entries: Its entries.
        grid: The view is a grid.
    """

    def __init__(self, view: Any, entries: Sequence[Any], *, grid: bool) -> None:  # noqa: ANN401
        self._view = view
        self._grid = grid
        self.reset(entries)
        original = view._render

        def render(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401 — PyUI's signature
            """Draw the frame, then follow the visible rows."""
            result = original(*args, **kwargs)
            try:
                self._follow()
            except Exception:  # downloads are an optimisation; never take the view down
                logger.exception("Could not queue images for the visible rows")
            return result

        view._render = render

    def reset(self, entries: Sequence[Any]) -> None:
        """Remember new entries' searchers (before PyUI drops them).

        Args:
            entries: The view's new entries.
        """
        self._searchers = [entry.icon_searcher for entry in entries]
        self._shown: range | None = None
        self._version = _hooks.version()

    def resume(self) -> None:
        """Ask for the visible rows' images again on the next frame (the view is shown again).

        The screens shown in between moved the downloads to their own rows.
        """
        self._shown = None

    def _visible(self) -> range:
        """Return the indices on screen."""
        view, count = self._view, len(self._searchers)
        if self._grid:
            start, stop = int(view.current_left), int(view.current_right)
        else:
            start, stop = int(view.current_top), int(view.current_bottom)
        return range(max(start, 0), min(stop, count))

    def _follow(self) -> None:
        """Re-target downloads when the window moved; refresh grid tiles when images arrived."""
        shown = self._visible()
        if shown != self._shown:
            forward = self._shown is None or shown.start >= self._shown.start
            self._shown = shown
            _hooks.new_window()
            self._ask(shown)
            with demanding(ImageDemand.NEXT):
                self._ask(next_page(shown, len(self._searchers), forward=forward))
        if self._grid:
            self._rearm(shown)

    def _ask(self, rows: range) -> None:
        """Ask the rows for their images (missing ones get requested).

        Args:
            rows: Entry indices.
        """
        for index in rows:
            searcher = self._searchers[index]
            if searcher is not None:
                searcher(None)

    def _rearm(self, shown: range) -> None:
        """Let visible grid tiles ask for their image again if images arrived since last time.

        Args:
            shown: Indices on screen.
        """
        version = _hooks.version()
        if version == self._version:
            return
        self._version = version
        for index in shown:
            searcher = self._searchers[index]
            if searcher is None:
                continue
            entry = self._view.options[index]
            entry.image_path = None
            entry.image_path_searcher = searcher
            entry.image_path_selected = None
            entry.image_path_selected_searcher = searcher


def next_page(shown: range, count: int, *, forward: bool) -> range:
    """Return the page after ``shown`` in the scroll direction (the other way at an end).

    Args:
        shown: Indices on screen.
        count: Number of entries.
        forward: The last move went down the list.

    Returns:
        Up to one screenful of indices.
    """
    size = len(shown)
    below = range(shown.stop, min(shown.stop + size, count))
    above = range(max(shown.start - size, 0), shown.start)
    first, second = (below, above) if forward else (above, below)
    return first or second
