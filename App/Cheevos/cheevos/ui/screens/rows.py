"""Row builders shared by the game and achievement lists."""

from __future__ import annotations

import functools

from cheevos.core.models import Achievement, GameProgress, PendingAward
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.row_bars import Progress
from cheevos.ui.pyui.views import MenuItem


def rarity(achievement: Achievement, players: int) -> float:
    """Share of a game's players who unlocked an achievement.

    Args:
        achievement: The achievement.
        players: Distinct players of the game.

    Returns:
        A fraction between 0 and 1 (0 when the player count is unknown).
    """
    return achievement.num_awarded / players if players > 0 else 0.0


def unlock_label(achievement: Achievement, pending: PendingAward | None) -> str:
    """Describe the user's unlock state: mode and date, pending sync, or nothing.

    Args:
        achievement: The achievement.
        pending: Its entry in RAOfflineProxy's queue, if any.

    Returns:
        The label, or ``""`` when locked.
    """
    if achievement.hardcore:
        return strings.UNLOCKED_HARDCORE.format(when=fmt.local_date(achievement.earned_hardcore_at))
    if achievement.unlocked:
        return strings.UNLOCKED_CASUAL.format(when=fmt.local_date(achievement.earned_at))
    if pending is not None:
        return strings.PENDING.format(when=fmt.local_date(pending.queued_at))
    return ""


def achievement_row(
    ctx: AppContext,
    achievement: Achievement,
    *,
    players: int,
    pending: PendingAward | None = None,
    game_title: str = "",
) -> MenuItem:
    """Build an achievement row: badge, title, tags and unlock state, points.

    Args:
        ctx: App context.
        achievement: The achievement.
        players: Distinct players of the game (for rarity).
        pending: Its RAOfflineProxy queue entry, if any.
        game_title: Prefix the description with the game (cross-game lists).

    Returns:
        The row.
    """
    parts = [game_title] if game_title else []
    if achievement.type is not None:
        parts.append(strings.TYPE_LABELS[achievement.type.value])
    unlocked = unlock_label(achievement, pending)
    rate = strings.RARITY.format(percent=fmt.percent(rarity(achievement, players)))
    parts.append(unlocked or rate)
    if ctx.screenshots.lookup(achievement.achievement_id) is not None:
        parts.append(strings.HAS_SCREENSHOT)
    return MenuItem(
        achievement.title,
        " · ".join(parts),
        lambda: ctx.media.badge(achievement, unlocked=achievement.unlocked or pending is not None),
        fmt.points(achievement.points),
        str(achievement.achievement_id),
    )


def completion(game: GameProgress, pending: int = 0) -> Progress:
    """Build a game's progress bar the way RA draws it: hardcore gold, casual-only grey.

    Hardcore unlocks count towards the total too, so 30% hardcore plus 35% casual-only is 65%.
    Unlocks still waiting in RAOfflineProxy's queue are casual (the proxy refuses hardcore), so
    they join the grey part.

    Args:
        game: The game.
        pending: Unlocks waiting to sync.

    Returns:
        The bar, with the percentage and the award (shown as a dot).
    """
    total = game.max_possible
    earned = min(game.earned + pending, total) if total else game.earned
    hardcore = game.earned_hardcore / total if total else 0.0
    casual = max(earned - game.earned_hardcore, 0) / total if total else 0.0
    percent = earned * 100 // total if total else 0
    if earned:  # never 100% before the end, never 0% after the first unlock
        percent = max(percent, 1)
    label = strings.PERCENT.format(percent=percent)
    return Progress(hardcore, casual, label, game.highest_award)


def game_row(
    ctx: AppContext, game: GameProgress, *, details: bool = False, pending: int = 0
) -> MenuItem:
    """Build a game row: icon, title, a progress bar (or console and activity), and the count.

    Args:
        ctx: App context.
        game: The game.
        details: Show the console with the award or last activity instead of the bar.
        pending: Unlocks waiting in RAOfflineProxy's queue: counted, and flagged as "+N".

    Returns:
        The row.
    """
    icon = functools.partial(ctx.media.game_icon, game.game_id, game.image_icon)
    count = f"{game.earned}/{game.max_possible}"
    if pending:
        count = strings.COUNT_PENDING.format(
            earned=game.earned, pending=pending, total=game.max_possible
        )
    if not details:
        progress = completion(game, pending)
        return MenuItem(game.title, "", icon, count, str(game.game_id), progress)
    if game.highest_award is not None:
        status = strings.AWARD_LABELS[game.highest_award.value]
        detail = strings.GAME_NEVER_PLAYED.format(console=game.console_name, status=status)
    else:
        when = max(game.last_unlock_at or 0, game.last_played_at or 0)
        ago = fmt.ago(when, ctx.clock()) if when else strings.NOT_STARTED
        detail = strings.LAST_ACTIVITY.format(console=game.console_name, ago=ago)
    if pending:
        detail = strings.NOT_SYNCED.format(detail=detail, count=pending)
    return MenuItem(game.title, detail, icon, count, str(game.game_id))
