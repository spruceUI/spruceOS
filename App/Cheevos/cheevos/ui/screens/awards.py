"""The Awards screen: the profile's game, event and site badges (.agents/product.md, "Awards").

Three views of the same awards: a carousel, a compact grid and a list. Select cycles them and
the choice is remembered (``awards_view``); Y or Menu change the view, filter and sort. A
opens a game's achievements; event and site badges have nothing more to show.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace

from cheevos.core.awards import gallery, group, site_order
from cheevos.core.models import Award, AwardGroup, AwardKind
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.badge_grid import Details
from cheevos.ui.pyui.primitives import Button
from cheevos.ui.pyui.views import Layout, MenuItem, PreparedView
from cheevos.ui.screens.award_text import AwardText, describe
from cheevos.ui.screens.common import message, pick
from cheevos.ui.screens.game_detail import show_game

Shown = tuple[Award, AwardText]

FILTERS: dict[str, Callable[[Award], bool]] = {
    "all": lambda _a: True,
    "game": lambda a: group(a) is AwardGroup.GAME,
    "mastered": lambda a: group(a) is AwardGroup.GAME and a.kind is AwardKind.MASTERED,
    "completed": lambda a: group(a) is AwardGroup.GAME and a.kind is AwardKind.COMPLETED,
    "event": lambda a: group(a) is AwardGroup.EVENT,
    "site": lambda a: group(a) is AwardGroup.SITE,
}
_NO_CONSOLES = frozenset({"event", "site"})  # console sorting is for game awards
LAYOUTS = {"carousel": Layout.CAROUSEL, "grid": Layout.BADGES, "list": Layout.LIST}
_NEXT_VIEW = {"carousel": "grid", "grid": "list", "list": "carousel"}


@dataclass(frozen=True, slots=True)
class _View:
    """Presentation choices.

    Attributes:
        layout: Key of :data:`LAYOUTS`.
        filter: Key of :data:`FILTERS`.
        sort: Key of ``strings.AWARD_SORTS``.
    """

    layout: str = "carousel"
    filter: str = "all"
    sort: str = "newest"


def next_view(layout: str) -> str:
    """Return the view Select switches to: carousel, grid, list, then the carousel again."""
    return _NEXT_VIEW.get(layout, "carousel")


def arrange(awards: Sequence[Shown], view: _View) -> list[Shown]:
    """Filter and sort the awards; every view shows the same result.

    Args:
        awards: Gallery awards with their text, in RA's order.
        view: Filter and sort (console sorting only applies to game awards).

    Returns:
        The awards to show, in order.
    """
    shown = [pair for pair in awards if FILTERS.get(view.filter, FILTERS["all"])(pair[0])]
    if view.sort == "site":  # the player's own arrangement, gallery by gallery
        order = {award.key: index for index, award in enumerate(site_order([a for a, _ in shown]))}
        return sorted(shown, key=lambda pair: order[pair[0].key])
    if view.sort == "title":
        return sorted(shown, key=lambda pair: pair[1].title.casefold())
    if view.sort == "console" and view.filter not in _NO_CONSOLES:
        return sorted(
            shown,
            key=lambda pair: (
                group(pair[0]) is not AwardGroup.GAME,
                pair[0].console_name.casefold(),
                pair[1].title.casefold(),
            ),
        )
    return sorted(shown, key=lambda pair: (-(pair[0].awarded_at or 0), pair[0].position))


def _item(ctx: AppContext, award: Award, text: AwardText) -> MenuItem:
    """Build one award's carousel tile, grid tile or list row.

    Args:
        ctx: App context.
        award: The award.
        text: Its text.

    Returns:
        The item.
    """
    key, path = text.image
    fallback = "gamepad" if award.game_id is not None else "crown"
    return MenuItem(
        text.title,
        text.description,
        icon=lambda: ctx.media.resolve(key, path or None, fallback),
        key=award.key,
        frame=text.frame,
        details=Details(text.description, text.date),
        tail=text.date,
    )


def show_awards(ctx: AppContext) -> None:
    """Show the awards until B (Select: view, Y or Menu: options, A: open).

    Args:
        ctx: App context.
    """
    _counts, visible = ctx.data.awards(gallery=True)
    events = ctx.data.events()
    awards = [(award, describe(award, events)) for award in gallery(visible)]
    if not awards:
        message(strings.AWARDS, [strings.NO_AWARDS])
        return
    _browse(ctx, awards)


def _browse(ctx: AppContext, awards: list[Shown]) -> None:
    """Show the awards in the chosen view until B.

    Args:
        ctx: App context.
        awards: Gallery awards with their text.
    """
    view = _View(layout=ctx.settings.awards_view)
    selected = 0
    shown: list[Shown] = []
    prepared: PreparedView | None = None  # kept while a game is open: back to the same page
    buttons = frozenset({Button.A, Button.Y, Button.MENU, Button.SELECT})
    while True:
        if prepared is None:
            shown = arrange(awards, view)
            if not shown:
                message(strings.AWARDS, [strings.NO_AWARDS_MATCH])
                view, selected = replace(view, filter="all"), 0
                continue
            items = [_item(ctx, award, text) for award, text in shown]
            title = strings.AWARDS_TITLE.format(count=fmt.number(len(shown)))
            selected = min(selected, len(items) - 1)
            prepared = PreparedView(title, items, selected=selected, layout=LAYOUTS[view.layout])
        toggle = strings.AWARD_VIEWS[next_view(view.layout)]
        hints = [(Button.Y, strings.HINT_FILTER), (Button.SELECT, toggle)]
        choice = prepared.show(buttons=buttons, hints=hints)
        if choice is None:
            return
        selected = choice.index
        if choice.button is Button.SELECT:  # carousel -> grid -> list, keeping the selection
            view = _remember(ctx, replace(view, layout=next_view(view.layout)))
            prepared = None
        elif choice.button in (Button.Y, Button.MENU):
            changed = _options(view, [award for award, _ in awards])
            if changed != view:
                if (changed.filter, changed.sort) != (view.filter, view.sort):
                    selected = 0  # a new filter or sort starts at the top
                view, prepared = _remember(ctx, changed), None
        else:
            award = shown[selected][0]
            # Only game awards open: event and site IDs are never game IDs, and old events'
            # masteries are event badges too.
            if group(award) is AwardGroup.GAME and award.game_id is not None:
                show_game(ctx, award.game_id)


def _remember(ctx: AppContext, view: _View) -> _View:
    """Keep the view for next time (settings are saved on exit).

    Args:
        ctx: App context.
        view: The new choices.

    Returns:
        ``view``.
    """
    if ctx.settings.awards_view != view.layout:
        ctx.update_settings(replace(ctx.settings, awards_view=view.layout))
    return view


def _options(view: _View, awards: Sequence[Award]) -> _View:
    """Let the user change the view, filter or sort through popups.

    Args:
        view: Current choices.
        awards: The gallery's awards (for the filters' counts).

    Returns:
        The updated choices (unchanged if the user backed out).
    """
    sorts = {
        key: label
        for key, label in strings.AWARD_SORTS.items()
        if key != "console" or view.filter not in _NO_CONSOLES
    }
    sort = view.sort if view.sort in sorts else "newest"
    menu = {
        "layout": strings.VIEW.format(value=strings.AWARD_VIEWS[view.layout]),
        "filter": strings.FILTER.format(value=strings.AWARD_FILTERS[view.filter]),
        "sort": strings.SORT.format(value=strings.AWARD_SORTS[sort]),
    }
    which = pick(strings.AWARDS, menu, "layout")
    if which == "layout":
        layout = pick(strings.AWARDS, strings.AWARD_VIEWS, view.layout)
        return replace(view, layout=layout) if layout else view
    if which == "filter":
        counts = {key: sum(1 for a in awards if test(a)) for key, test in FILTERS.items()}
        filters = {  # empty filters are left out, except "All" and the current one
            key: strings.AWARD_FILTER_COUNT.format(label=label, count=fmt.number(counts[key]))
            for key, label in strings.AWARD_FILTERS.items()
            if counts[key] or key in ("all", view.filter)
        }
        chosen = pick(strings.AWARDS, filters, view.filter)
        if not chosen:
            return view
        keeps_sort = view.sort != "console" or chosen not in _NO_CONSOLES
        return replace(view, filter=chosen, sort=view.sort if keeps_sort else "newest")
    if which == "sort":
        chosen = pick(strings.AWARDS, sorts, sort)
        return replace(view, sort=chosen) if chosen else view
    return view
