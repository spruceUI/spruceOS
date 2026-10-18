"""A game's achievements as a list or badge grid (Select), with filter and sort options (Y)."""

from __future__ import annotations

import math
from collections.abc import Callable
from dataclasses import dataclass, replace

from cheevos.core.models import Achievement, AchievementType, GameDetail, PendingAward
from cheevos.core.sync.detail_fetch import FetchState, FetchStatus
from cheevos.core.sync.progress import Failure
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.badge_grid import Details
from cheevos.ui.pyui.primitives import Button
from cheevos.ui.pyui.title_bar import Title
from cheevos.ui.pyui.views import Layout, MenuItem, PreparedView
from cheevos.ui.screens.achievement import hides_description, show_achievement
from cheevos.ui.screens.common import message, pick, wait_while
from cheevos.ui.screens.rows import achievement_row, rarity

_KEY_TYPES = (AchievementType.PROGRESSION, AchievementType.WIN_CONDITION)

FILTERS: dict[str, Callable[[Achievement], bool]] = {
    "all": lambda _a: True,
    "locked": lambda a: not a.unlocked,
    "unlocked": lambda a: a.unlocked,
    "missable": lambda a: a.type is AchievementType.MISSABLE,
    "key": lambda a: a.type in _KEY_TYPES,
}


@dataclass(frozen=True, slots=True)
class _View:
    """Presentation choices for the achievement list.

    Attributes:
        layout: ``"list"`` or ``"grid"``.
        filter: Key of :data:`FILTERS`.
        sort: Key of ``strings.ACH_SORTS``.
    """

    layout: str = "list"
    filter: str = "all"
    sort: str = "order"


def _sorted(achievements: list[Achievement], sort: str, players: int) -> list[Achievement]:
    """Order achievements for display.

    Args:
        achievements: Filtered achievements in RA's order.
        sort: Key of ``strings.ACH_SORTS``.
        players: Distinct players, for rarity.

    Returns:
        A new, ordered list.
    """
    if sort == "unlocked":
        return sorted(achievements, key=lambda a: not a.unlocked)
    if sort == "locked":
        return sorted(achievements, key=lambda a: a.unlocked)
    if sort == "points":
        return sorted(achievements, key=lambda a: -a.points)
    if sort == "rarity":
        return sorted(achievements, key=lambda a: rarity(a, players))
    return list(achievements)


def show_game(ctx: AppContext, game_id: int, *, refresh: bool = False) -> None:
    """Show a game's achievements until B.

    Args:
        ctx: App context.
        game_id: RA game ID.
        refresh: Refresh this game in the background and update its visible rows.
    """
    detail = ctx.data.game_detail(game_id)
    if refresh and detail is not None:
        ctx.details.request(game_id, refresh=True)
    if detail is None:
        detail = _load(ctx, game_id)
        if detail is None:
            return
    if not detail.achievements:
        message(detail.title, [strings.NO_ACHIEVEMENT_SET])
        return
    game = ctx.data.game(game_id)
    pending = ctx.pending_awards()
    earned = sum(1 for a in detail.achievements if a.unlocked)
    count = f"{earned}/{len(detail.achievements)}"
    title = Title(detail.title, count, game.highest_award if game else None)
    _browse(ctx, detail, title, pending, live=refresh)


def _browse(
    ctx: AppContext, detail: GameDetail, title: Title, pending: dict, *, live: bool = False
) -> None:
    """Browse a game, optionally updating its rows after a targeted refresh."""
    _GameBrowser(ctx, detail, title, pending, live=live).run()


class _GameBrowser:
    """Keep one game's view and selection across cards, options and live refreshes.

    Args:
        ctx: Shared app context.
        detail: Initial cached game details.
        title: Initial top-bar title.
        pending: Pending unlocks keyed by achievement ID.
        live: Watch for refreshed game details.
    """

    def __init__(
        self, ctx: AppContext, detail: GameDetail, title: Title, pending: dict, *, live: bool
    ) -> None:
        self.ctx, self.detail, self.title, self.pending = ctx, detail, title, pending
        self.view = _View(
            layout="grid" if ctx.settings.achievement_grid else "list",
            sort=ctx.settings.achievement_sort,
        )
        self.selected = 0
        self.shown: list[Achievement] = []
        self.prepared: PreparedView | None = None
        self.live, self.revision = live, -1

    def _achievements(self) -> list[Achievement]:
        """Filter and sort the current game with the player's current choices."""
        return _sorted(
            [a for a in self.detail.achievements if FILTERS[self.view.filter](a)],
            self.view.sort,
            self.detail.num_distinct_players,
        )

    def _items(self) -> list[MenuItem]:
        """Build rows for the current visible achievements and pending unlocks."""
        return [_row(self.ctx, a, self.detail, self.pending) for a in self.shown]

    def _refresh(self) -> list[MenuItem] | None:
        """Update changed details in place, retaining the selected achievement by key."""
        if not self.live or (version := self.ctx.data.version()) == self.revision:
            return None
        self.revision = version
        detail = self.ctx.data.game_detail(self.detail.game_id)
        if detail is None or detail == self.detail:
            return None
        self.detail, self.pending = detail, self.ctx.pending_awards()
        self.shown = self._achievements()
        if not self.shown:
            self.view = replace(self.view, filter="all")
            self.shown = self._achievements()
        if not self.shown:
            message(detail.title, [strings.NO_ACHIEVEMENT_SET])
            return []
        game = self.ctx.data.game(detail.game_id)
        count = f"{sum(a.unlocked for a in detail.achievements)}/{len(detail.achievements)}"
        self.title = Title(detail.title, count, game.highest_award if game else None)
        if self.prepared is not None:
            self.prepared.set_title(self.title)
        return self._items()

    def _prepare(self) -> None:
        """Build a view, recovering from an empty filter through the usual message."""
        self.shown = self._achievements()
        if not self.shown:
            message(self.detail.title, [strings.NO_ACHIEVEMENTS])
            self.view = replace(self.view, filter="all")
            return
        layout = Layout.BADGES if self.view.layout == "grid" else Layout.LIST
        self.prepared = PreparedView(
            self.title, self._items(), selected=self.selected, layout=layout
        )

    def _configure(self, button: Button) -> None:
        """Apply an options or layout change and remember the shared preferences."""
        changed = (
            replace(self.view, layout="list" if self.view.layout == "grid" else "grid")
            if button is Button.SELECT
            else _options(self.view)
        )
        if changed == self.view:
            return
        self.view, self.prepared = changed, None
        if button is not Button.SELECT:
            self.selected = 0
        self.ctx.update_settings(
            replace(
                self.ctx.settings,
                achievement_grid=changed.layout == "grid",
                achievement_sort=changed.sort,
            )
        )

    def run(self) -> None:
        """Show achievements and their cards until B returns to the calling screen."""
        buttons = frozenset({Button.A, Button.Y, Button.MENU, Button.SELECT})
        while True:
            if self.prepared is None:
                self._prepare()
            prepared = self.prepared
            if prepared is None:
                continue
            # A refresh may have finished while a card or popup was open.
            updated = self._refresh()
            if updated is not None:
                if not updated:
                    return
                prepared.update_items(updated)
            toggle = strings.HINT_LIST if self.view.layout == "grid" else strings.HINT_GRID
            choice = prepared.show(
                buttons=buttons,
                hints=[(Button.Y, strings.HINT_FILTER), (Button.SELECT, toggle)],
                on_tick=self._refresh,
            )
            if choice is None:
                return
            self.selected = choice.index
            if choice.button in (Button.Y, Button.MENU, Button.SELECT):
                self._configure(choice.button)
                continue
            achievement = self.shown[choice.index]
            show_achievement(
                self.ctx,
                achievement,
                game_title=self.detail.title,
                players=self.detail.num_distinct_players,
                players_hardcore=self.detail.num_players_hardcore,
                pending=self.pending.get(achievement.achievement_id),
            )


def _load(ctx: AppContext, game_id: int) -> GameDetail | None:
    """Fetch the achievements of a game that isn't cached, behind a loading page.

    Args:
        ctx: App context.
        game_id: RA game ID.

    Returns:
        The game's details, or ``None`` if the user backed out (the fetch carries on, and its
        result is kept) or it failed (after saying why).
    """
    game = ctx.data.game(game_id)
    title = game.title if game else strings.GAMES

    def loading() -> bool:
        """Whether the game is still being fetched."""
        status = ctx.details.status(game_id)
        return status is not None and status.state is FetchState.WAITING

    ctx.details.request(game_id)
    while True:
        if not wait_while(title, strings.LOADING_ACHIEVEMENTS, loading):
            return None
        detail = ctx.data.game_detail(game_id)
        status = ctx.details.status(game_id)
        if detail is not None:
            return detail
        if status is not None and status.state is FetchState.CANCELLED:
            return None
        message(title, _why_not(status, ctx.clock()))
        # Start can replace a rejected key or retry while the failure is on screen.
        detail = ctx.data.game_detail(game_id)
        if detail is not None:
            return detail
        if not loading():
            return None


def _why_not(status: FetchStatus | None, now: float) -> list[str]:
    """Explain why a game's achievements couldn't be loaded.

    Args:
        status: How the fetch ended.
        now: Current time (for RA's pause).

    Returns:
        The paragraphs.
    """
    failure = status.failure if status is not None else None
    if failure is Failure.NETWORK:
        return [strings.NO_DETAILS, strings.LOAD_NETWORK, strings.NO_DETAILS_HINT]
    if failure is Failure.AUTH:
        return [strings.NO_DETAILS, strings.SYNC_AUTH]
    if failure is Failure.RATE_LIMITED and status is not None and status.retry_at is not None:
        minutes = max(math.ceil((status.retry_at - now) / 60), 1)
        return [strings.NO_DETAILS, strings.SYNC_RATE_LIMITED.format(minutes=minutes)]
    return [strings.NO_DETAILS, strings.LOAD_ERROR]


def _row(ctx: AppContext, achievement: Achievement, detail: GameDetail, pending: dict) -> MenuItem:
    """Build one achievement row (list) or tile (badge grid) for this game.

    Args:
        ctx: App context.
        achievement: The achievement.
        detail: Its game.
        pending: Pending unlocks by achievement ID.

    Returns:
        The row.
    """
    waiting = pending.get(achievement.achievement_id)
    row = achievement_row(ctx, achievement, players=detail.num_distinct_players, pending=waiting)
    return replace(row, details=_details(ctx, achievement, waiting))


def _details(ctx: AppContext, achievement: Achievement, pending: PendingAward | None) -> Details:
    """Describe a badge under the grid: description, unlock mode and type.

    The description follows the card's spoiler setting.

    Args:
        ctx: App context.
        achievement: The achievement.
        pending: Its RAOfflineProxy queue entry, if any.

    Returns:
        The details.
    """
    hidden = hides_description(ctx.settings.hide_descriptions, achievement, pending=pending)
    if achievement.hardcore:
        tags = [strings.MODE_HARDCORE]
    elif achievement.unlocked:
        tags = [strings.MODE_CASUAL]
    elif pending is not None:
        tags = [strings.MODE_PENDING]
    else:
        tags = [strings.DETAIL_LOCKED]
    if achievement.type is not None:
        tags.append(strings.TYPE_LABELS[achievement.type.value])
    text = strings.HIDDEN_DESCRIPTION if hidden else achievement.description
    return Details(text, " · ".join(tags))


def _options(view: _View) -> _View:
    """Let the user change the view, filter or sort through popups.

    Args:
        view: Current choices.

    Returns:
        The updated choices (unchanged if the user backed out).
    """
    menu = {
        "layout": strings.VIEW.format(value=strings.VIEWS[view.layout]),
        "filter": strings.FILTER.format(value=strings.ACH_FILTERS[view.filter]),
        "sort": strings.SORT.format(value=strings.ACH_SORTS[view.sort]),
    }
    which = pick(strings.APP_TITLE, menu, "layout")
    if which == "layout":
        layout = pick(strings.APP_TITLE, strings.VIEWS, view.layout)
        return replace(view, layout=layout) if layout else view
    if which == "filter":
        chosen = pick(strings.APP_TITLE, strings.ACH_FILTERS, view.filter)
        return replace(view, filter=chosen) if chosen else view
    if which == "sort":
        chosen = pick(strings.APP_TITLE, strings.ACH_SORTS, view.sort)
        return replace(view, sort=chosen) if chosen else view
    return view
