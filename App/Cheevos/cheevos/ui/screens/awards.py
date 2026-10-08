"""The awards wall: each game's highest award, framed in RA's colours, with filter and sort (Y).

RA's own showcase lists mastered games (gold border) and completed ones; this wall also shows
beaten games, since beating a game is a milestone on a handheld too. A game that holds both a
Beaten and a Mastered award appears once, with the higher one. A opens the game.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, replace

from cheevos.core.models import Award, AwardKind
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.primitives import Button
from cheevos.ui.pyui.views import ICON_TILE, Layout, MenuItem, choose
from cheevos.ui.screens.common import message, pick
from cheevos.ui.screens.game_detail import show_game

# Higher wins when a game holds several awards (RA's own HighestAwardKind order).
RANK = {
    AwardKind.MASTERED: 3,
    AwardKind.COMPLETED: 2,
    AwardKind.BEATEN_HARDCORE: 1,
    AwardKind.BEATEN_SOFTCORE: 0,
}
MASTERY = frozenset({AwardKind.MASTERED, AwardKind.COMPLETED})


@dataclass(frozen=True, slots=True)
class _View:
    """Filter and sort choices.

    Attributes:
        filter: Key of ``strings.AWARD_FILTERS``.
        sort: Key of ``strings.AWARD_SORTS``.
    """

    filter: str = "all"
    sort: str = "newest"


def highest_per_game(awards: Sequence[Award]) -> list[Award]:
    """Keep each game's highest award, in the order the games first appear.

    Args:
        awards: All visible game awards.

    Returns:
        One award per game.
    """
    best: dict[int, Award] = {}
    for award in awards:
        known = best.get(award.game_id)
        if known is None or RANK[award.kind] > RANK[known.kind]:
            best[award.game_id] = award
    return list(best.values())


def arrange(awards: Sequence[Award], view: _View) -> list[Award]:
    """Filter and sort awards for the wall.

    Args:
        awards: One award per game.
        view: Filter and sort.

    Returns:
        The awards to show, in order.
    """
    if view.filter == "mastery":
        awards = [award for award in awards if award.kind in MASTERY]
    elif view.filter == "beaten":
        awards = [award for award in awards if award.kind not in MASTERY]
    if view.sort == "site":  # the user's own arrangement on RA's site
        return sorted(awards, key=lambda a: (a.display_order, -(a.awarded_at or 0)))
    if view.sort == "title":
        return sorted(awards, key=lambda a: a.title.lower())
    if view.sort == "console":
        return sorted(awards, key=lambda a: (a.console_name.lower(), a.title.lower()))
    return sorted(awards, key=lambda a: -(a.awarded_at or 0))


def _tiles(ctx: AppContext, awards: Sequence[Award]) -> list[MenuItem]:
    """Build the wall's tiles: game icon, title caption, award frame.

    Args:
        ctx: App context.
        awards: Awards to show.

    Returns:
        The tiles.
    """
    return [
        MenuItem(
            award.title,
            icon=lambda award=award: ctx.media.game_icon(award.game_id, award.image_icon),
            key=str(award.game_id),
            frame=award.kind,
        )
        for award in awards
    ]


def show_awards(ctx: AppContext) -> None:
    """Show the awards wall until B; A opens the game, Y filters and sorts.

    Args:
        ctx: App context.
    """
    _counts, awards = ctx.data.awards()
    best = highest_per_game(awards)
    if not best:
        message(strings.AWARDS, [strings.NO_AWARDS])
        return
    view = _View()
    shown = arrange(best, view)
    items = _tiles(ctx, shown)
    selected = 0
    while True:
        if not shown:
            message(strings.AWARDS, [strings.NO_AWARDS_MATCH])
            view = _View()
            shown = arrange(best, view)
            items = _tiles(ctx, shown)
            continue
        title = strings.AWARDS_TITLE.format(count=fmt.number(len(shown)))
        choice = choose(
            title,
            items,
            selected=selected,
            buttons=frozenset({Button.A, Button.Y}),
            layout=Layout.GRID,
            tile=ICON_TILE,
            hints=[(Button.Y, strings.HINT_FILTER)],
        )
        if choice is None:
            return
        if choice.button is Button.Y:
            changed = _options(view)
            if changed != view:
                view, selected = changed, 0
                shown = arrange(best, view)
                items = _tiles(ctx, shown)
            continue
        selected = choice.index
        show_game(ctx, shown[choice.index].game_id)


def _options(view: _View) -> _View:
    """Let the user change the filter or sort through popups.

    Args:
        view: Current choices.

    Returns:
        The updated choices (unchanged if the user backed out).
    """
    menu = {
        "filter": strings.FILTER.format(value=strings.AWARD_FILTERS[view.filter]),
        "sort": strings.SORT.format(value=strings.AWARD_SORTS[view.sort]),
    }
    which = pick(strings.AWARDS, menu, "filter")
    if which == "filter":
        chosen = pick(strings.AWARDS, strings.AWARD_FILTERS, view.filter)
        return replace(view, filter=chosen) if chosen else view
    if which == "sort":
        chosen = pick(strings.AWARDS, strings.AWARD_SORTS, view.sort)
        return replace(view, sort=chosen) if chosen else view
    return view
