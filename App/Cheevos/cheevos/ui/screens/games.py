"""The game library: progress bars or details (Select), with filter and sort options (Y)."""

from __future__ import annotations

import dataclasses
import logging
import time
from collections.abc import Callable
from dataclasses import dataclass, replace

from cheevos.core.models import AwardKind, GameProgress
from cheevos.core.storage.data_cache import DataCache
from cheevos.core.sync.planner import activity
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.primitives import Button
from cheevos.ui.pyui.views import PreparedView
from cheevos.ui.screens.common import busy, message, pick
from cheevos.ui.screens.game_detail import show_game
from cheevos.ui.screens.rows import game_row

logger = logging.getLogger(__name__)

FINISHED = frozenset(AwardKind)
# Above this many rows, preparing the list takes a noticeable moment on a Miyoo Mini
# (about 0.3 s per 1,000 games), so show a loading frame first.
LOADING_FRAME_ROWS = 1000
_BUTTONS = frozenset({Button.A, Button.Y, Button.SELECT})


@dataclass(frozen=True, slots=True)
class _View:
    """Filter and sort choices.

    Attributes:
        filter: Key of ``strings.GAME_FILTERS``.
        sort: Key of ``strings.GAME_SORTS``.
    """

    filter: str = "all"
    sort: str = "recent"


def _filters(ctx: AppContext) -> dict[str, Callable[[GameProgress], bool]]:
    """Build the filter predicates (the on-device one needs the context).

    Args:
        ctx: App context.

    Returns:
        Filter key to predicate.
    """
    return {
        "all": lambda _g: True,
        "device": lambda g: g.game_id in ctx.on_device_ids(),
        "progress": lambda g: 0 < g.earned < g.max_possible and g.highest_award is None,
        "finished": lambda g: g.highest_award in FINISHED,
        "unstarted": lambda g: g.earned == 0,
    }


def _completion(game: GameProgress) -> float:
    """Return a game's completion as a fraction.

    Args:
        game: The game.

    Returns:
        Earned over total (0 for games without achievements).
    """
    return game.earned / game.max_possible if game.max_possible else 0.0


def _sorted(games: list[GameProgress], sort: str) -> list[GameProgress]:
    """Order games for display.

    Args:
        games: Filtered games (already in activity order).
        sort: Key of ``strings.GAME_SORTS``.

    Returns:
        A new, ordered list.
    """
    if sort == "title":
        return sorted(games, key=lambda g: g.title.lower())
    if sort == "console":
        return sorted(games, key=lambda g: (g.console_name.lower(), g.title.lower()))
    if sort == "completion":
        return sorted(games, key=lambda g: (-_completion(g), -activity(g)))
    return list(games)


class _Library:
    """Every game in the data cache, read again only after the cache changed.

    Args:
        data: The data cache.
    """

    def __init__(self, data: DataCache) -> None:
        self._data = data
        self._version: tuple[int, int] | None = None
        self._games: list[GameProgress] = []

    def games(self) -> list[GameProgress]:
        """Return the games, most recent activity first (the same objects while unchanged)."""
        version = self._data.version()
        if version != self._version:
            self._games = self._data.games()
            self._version = version
        return self._games


@dataclass(frozen=True, slots=True)
class _Shown:
    """The list on screen and what its rows were built from.

    Attributes:
        view: The prepared list, shown again while neither of the others changes.
        games: Its games, in order.
        key: What else the rows show: filter and sort, details or bars, unlocks waiting to sync.
    """

    view: PreparedView
    games: list[GameProgress]
    key: tuple[object, ...]


def show_games(ctx: AppContext) -> None:
    """Show the library until B.

    Preparing thousands of rows takes a moment on a Mini, so the list is kept and shown again
    while nothing it shows changes (back from a game), with its selection and scroll position.

    Args:
        ctx: App context.
    """
    view = _View()
    filters = _filters(ctx)
    library = _Library(ctx.data)
    shown: _Shown | None = None
    selected_id: int | None = None  # the game to select when the list is rebuilt
    while True:
        details = ctx.settings.game_list_details
        pending = ctx.pending_by_game()
        key = (view, details, pending)
        games = _sorted([g for g in library.games() if filters[view.filter](g)], view.sort)
        if not games:
            message(strings.GAMES, [strings.NO_GAMES])
            if view == _View():
                return
            view = _View()
            continue
        # Unchanged games are the very same objects, so comparing the lists is quick.
        if shown is None or shown.key != key or shown.games != games:
            shown = _Shown(_prepare(ctx, view, games, pending, selected_id), games, key)
        toggle = strings.HINT_PROGRESS if details else strings.HINT_DETAILS
        hints = [(Button.Y, strings.HINT_FILTER), (Button.SELECT, toggle)]
        choice = shown.view.show(buttons=_BUTTONS, hints=hints)
        if choice is None:
            return
        if choice.button is Button.Y:
            view = _options(view)
            selected_id = None
            continue
        selected_id = games[choice.index].game_id
        if choice.button is Button.SELECT:  # progress bars <-> console and last activity
            ctx.update_settings(dataclasses.replace(ctx.settings, game_list_details=not details))
            continue
        show_game(ctx, selected_id)


def _prepare(
    ctx: AppContext,
    view: _View,
    games: list[GameProgress],
    pending: dict[int, int],
    selected_id: int | None,
) -> PreparedView:
    """Build the rows and prepare the list (behind a loading frame for big libraries).

    Args:
        ctx: App context.
        view: Filter and sort (for the title).
        games: The games to show, in order.
        pending: Unlocks waiting to sync, per game.
        selected_id: The game to select (the first one if it isn't shown).

    Returns:
        The list, ready to show.
    """
    title = f"{strings.GAMES} · {strings.GAME_FILTERS[view.filter]}"
    if len(games) > LOADING_FRAME_ROWS:
        busy(title, strings.LOADING)
    started = time.monotonic()
    details = ctx.settings.game_list_details
    items = [
        game_row(ctx, game, details=details, pending=pending.get(game.game_id, 0)) for game in games
    ]
    logger.info("Built %d game rows in %.0f ms", len(items), (time.monotonic() - started) * 1000)
    selected = next((i for i, game in enumerate(games) if game.game_id == selected_id), 0)
    return PreparedView(title, items, selected=selected)


def _options(view: _View) -> _View:
    """Let the user change the filter or sort through popups.

    Args:
        view: Current choices.

    Returns:
        The updated choices.
    """
    menu = {
        "filter": strings.FILTER.format(value=strings.GAME_FILTERS[view.filter]),
        "sort": strings.SORT.format(value=strings.GAME_SORTS[view.sort]),
    }
    which = pick(strings.GAMES, menu, "filter")
    if which == "filter":
        chosen = pick(strings.GAMES, strings.GAME_FILTERS, view.filter)
        return replace(view, filter=chosen) if chosen else view
    if which == "sort":
        chosen = pick(strings.GAMES, strings.GAME_SORTS, view.sort)
        return replace(view, sort=chosen) if chosen else view
    return view
