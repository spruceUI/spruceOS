"""Recent unlocks across games, unlocks still waiting in RAOfflineProxy's queue first."""

from __future__ import annotations

from cheevos.core.models import RECENT_UNLOCK_COUNT, Achievement, PendingAward
from cheevos.core.storage.recent_feed import RecentFeedCache
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.views import MenuItem, choose
from cheevos.ui.screens.achievement import enrich_achievement, show_achievement
from cheevos.ui.screens.common import message
from cheevos.ui.screens.rows import achievement_row


def show_recent(ctx: AppContext) -> None:
    """Show unlocks across games, pending offline unlocks first, until B.

    Args:
        ctx: App context.
    """
    pending = ctx.pending_awards()
    unlocks = ctx.data.recent_unlocks(RECENT_UNLOCK_COUNT)
    entries: list[tuple[Achievement, PendingAward | None]] = _pending_entries(ctx, pending)
    entries += [(a, None) for a in unlocks]
    if not entries:
        message(strings.RECENT, [strings.NOTHING_UNLOCKED])
        return
    titles = ctx.data.game_titles(achievement.game_id for achievement, _ in entries)
    feed = RecentFeedCache(ctx.data).load()
    if feed is not None:
        titles.update({entry.achievement.game_id: entry.game_title for entry in feed.entries})
    selected = 0
    while True:
        items = [_recent_row(ctx, a, p, titles) for a, p in entries]
        choice = choose(strings.RECENT, items, selected=selected)
        if choice is None:
            return
        selected = choice.index
        achievement, waiting = entries[choice.index]
        _open_achievement(ctx, achievement, waiting, titles.get(achievement.game_id, ""))


def _pending_entries(
    ctx: AppContext, pending: dict[int, PendingAward]
) -> list[tuple[Achievement, PendingAward | None]]:
    """Find cached achievements for queued offline unlocks (skipping unknown ones).

    Args:
        ctx: App context.
        pending: Pending unlocks by achievement ID.

    Returns:
        ``(achievement, pending entry)`` pairs, newest queued first.
    """
    entries = []
    synced = ctx.data.unlocked_among(pending)
    for award in sorted(pending.values(), key=lambda p: -(p.queued_at or 0)):
        if award.achievement_id in synced:
            continue
        detail = ctx.data.game_detail(award.game_id) if award.game_id else None
        match = next(
            (
                a
                for a in (detail.achievements if detail else ())
                if a.achievement_id == award.achievement_id
            ),
            None,
        )
        if match is not None and not match.unlocked:
            entries.append((match, award))
    return entries


def _recent_row(
    ctx: AppContext, achievement: Achievement, pending: PendingAward | None, titles: dict[int, str]
) -> MenuItem:
    """Build a recent-unlock row with its game title.

    Args:
        ctx: App context.
        achievement: The achievement.
        pending: Queue entry, if pending.
        titles: Game titles by ID.

    Returns:
        The row.
    """
    return achievement_row(
        ctx,
        achievement,
        players=0,
        pending=pending,
        game_title=titles.get(achievement.game_id, ""),
    )


def _open_achievement(
    ctx: AppContext, achievement: Achievement, pending: PendingAward | None, game_title: str
) -> None:
    """Open an achievement card with its game's statistics.

    Args:
        ctx: App context.
        achievement: The achievement.
        pending: Queue entry, if pending.
        game_title: Game title.
    """
    detail = ctx.data.game_detail(achievement.game_id)
    if detail is not None:
        achievement = enrich_achievement(achievement, detail)
    show_achievement(
        ctx,
        achievement,
        game_title=game_title,
        players=detail.num_distinct_players if detail else None,
        players_hardcore=detail.num_players_hardcore if detail else None,
        pending=pending,
    )
