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


def show_game(ctx: AppContext, game_id: int) -> None:
    """Show a game's achievements until B.

    Args:
        ctx: App context.
        game_id: RA game ID.
    """
    detail = ctx.data.game_detail(game_id)
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
    _browse(ctx, detail, title, pending)


def _browse(ctx: AppContext, detail: GameDetail, title: Title, pending: dict) -> None:
    """Show a game's achievements as a list or grid, and their cards, until B.

    Args:
        ctx: App context.
        detail: The game, with achievements.
        title: Top-bar title.
        pending: Pending unlocks by achievement ID.
    """
    view = _View(
        layout="grid" if ctx.settings.achievement_grid else "list",
        sort=ctx.settings.achievement_sort,
    )
    selected = 0
    shown: list[Achievement] = []
    prepared: PreparedView | None = None  # kept while the card is open: back to the same page
    while True:
        if prepared is None:
            shown = _sorted(
                [a for a in detail.achievements if FILTERS[view.filter](a)],
                view.sort,
                detail.num_distinct_players,
            )
            if not shown:
                message(detail.title, [strings.NO_ACHIEVEMENTS])
                view = replace(view, filter="all")
                continue
            items = [_row(ctx, a, detail, pending) for a in shown]
            layout = Layout.BADGES if view.layout == "grid" else Layout.LIST
            prepared = PreparedView(title, items, selected=selected, layout=layout)
        buttons = frozenset({Button.A, Button.Y, Button.SELECT})
        toggle = strings.HINT_LIST if view.layout == "grid" else strings.HINT_GRID
        hints = [(Button.Y, strings.HINT_FILTER), (Button.SELECT, toggle)]
        choice = prepared.show(buttons=buttons, hints=hints)
        if choice is None:
            return
        if choice.button is Button.Y:
            changed = _options(view)
            if changed != view:
                view, selected, prepared = changed, 0, None
                ctx.update_settings(
                    replace(
                        ctx.settings,
                        achievement_grid=view.layout == "grid",
                        achievement_sort=view.sort,
                    )
                )
            continue
        selected = choice.index
        if choice.button is Button.SELECT:  # list <-> grid, like PyUI's game lists
            view = replace(view, layout="list" if view.layout == "grid" else "grid")
            ctx.update_settings(replace(ctx.settings, achievement_grid=view.layout == "grid"))
            prepared = None
            continue
        achievement = shown[choice.index]
        show_achievement(
            ctx,
            achievement,
            game_title=detail.title,
            players=detail.num_distinct_players,
            players_hardcore=detail.num_players_hardcore,
            pending=pending.get(achievement.achievement_id),
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
    if not wait_while(title, strings.LOADING_ACHIEVEMENTS, loading):
        return None
    detail = ctx.data.game_detail(game_id)
    if detail is None:
        message(title, _why_not(ctx.details.status(game_id), ctx.clock()))
    return detail


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
