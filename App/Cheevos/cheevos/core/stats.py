"""Player statistics from the cache, computed the way RA's profile page computes them.

RA's site (RAWeb) derives most profile numbers from the same data the sync stores: completion
progress per game, award counts and the visible awards. Its rules are mirrored here:
- subsets ("[Subset" in the title) and test kits ("~Test Kit~") never count as games;
- averages only consider sets of 6+ achievements, and never Hubs or Events;
- "retail" games have no ~Demo~/~Prototype~/~Homebrew~/~Hack~ tag and run on a commercial
  console (not Arduboy, WASM-4 or Uzebox).

Points in the last 7/30 days need the unlocks themselves (``API_GetAchievementsEarnedBetween``),
fetched on demand ("See more") and passed in as an :class:`UnlockWindow`.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass

from cheevos.core.models import (
    Award,
    AwardCounts,
    AwardKind,
    GameProgress,
    UnlockWindow,
    UserProfile,
)
from cheevos.core.sync.planner import activity

DAY = 86_400
WEEK = 7 * DAY
WINDOW_DAYS = 30  # the unlock window fetched for "See more"
SHORT_WINDOW_DAYS = 7
MIN_SET_SIZE = 6
NON_GAME_CONSOLES = frozenset({100, 101})  # Hubs, Events
NON_RETAIL_CONSOLES = frozenset({71, 72, 80})  # Arduboy, WASM-4, Uzebox
NON_RETAIL_TAGS = ("~Demo~", "~Prototype~", "~Homebrew~", "~Hack~")
NON_GAME_CONSOLE_NAMES = frozenset({"Events", "Hubs"})
BEATEN_OR_BETTER = frozenset(AwardKind)
MASTERY = frozenset({AwardKind.MASTERED, AwardKind.COMPLETED})


def is_subset(title: str) -> bool:
    """Whether a set is a subset or a test kit (never counted as a game).

    Args:
        title: Game title.

    Returns:
        ``True`` for subsets and test kits.
    """
    return "[Subset" in title or title.startswith("~Test Kit~")


def is_retail(award: Award) -> bool:
    """Whether an award's game is a retail release.

    Args:
        award: The award.

    Returns:
        ``True`` unless the title is tagged or the console is a homebrew platform.
    """
    tagged = any(tag in award.title for tag in NON_RETAIL_TAGS)
    return not tagged and award.console_id not in NON_RETAIL_CONSOLES


@dataclass(frozen=True, slots=True)
class PlayerStats:
    """RA's "Player Stats" box.

    Attributes:
        unlocks_hardcore: Achievements unlocked in hardcore.
        unlocks_casual: Achievements unlocked in casual only.
        retro_ratio: RetroPoints per hardcore point (``None`` without points).
        games_beaten: Games beaten in hardcore (subsets excluded).
        games_beaten_retail: Of those, retail games (visible awards only).
        started_beaten: Share of started games with an award (``None`` without games).
        average_completion: Mean completion of started sets (``None`` without games).
        points_per_week: Hardcore points per week since the first hardcore unlock.
    """

    unlocks_hardcore: int
    unlocks_casual: int
    retro_ratio: float | None
    games_beaten: int
    games_beaten_retail: int
    started_beaten: float | None
    average_completion: float | None
    points_per_week: float | None


def _started(games: Iterable[GameProgress]) -> list[GameProgress]:
    """Games with at least one unlock, subsets and test kits excluded.

    Args:
        games: Library.

    Returns:
        The started games.
    """
    return [game for game in games if game.earned > 0 and not is_subset(game.title)]


def player_stats(
    profile: UserProfile,
    games: Sequence[GameProgress],
    counts: AwardCounts | None,
    awards: Sequence[Award],
    first_hardcore_unlock: int | None,
    now: float,
) -> PlayerStats:
    """Compute the player stats.

    Args:
        profile: Account summary (points).
        games: Library (completion progress plus recently played).
        counts: Award counters (hidden awards included).
        awards: Visible awards (only beaten-hardcore ones count, so these are enough).
        first_hardcore_unlock: Earliest hardcore unlock, if known.
        now: Current time.

    Returns:
        The stats.
    """
    sets = [game for game in games if game.max_possible >= MIN_SET_SIZE]
    hardcore = sum(game.earned_hardcore for game in sets)
    casual = sum(max(game.earned - game.earned_hardcore, 0) for game in sets)
    ratio = profile.retro_points / profile.hardcore_points if profile.hardcore_points else None
    beaten = [a for a in awards if a.kind is AwardKind.BEATEN_HARDCORE]
    subsets = sum(1 for award in beaten if is_subset(award.title))
    total_beaten = max((counts.beaten_hardcore if counts else len(beaten)) - subsets, 0)
    retail = sum(1 for award in beaten if not is_subset(award.title) and is_retail(award))
    started = _started(games)
    awarded = sum(1 for game in started if game.highest_award in BEATEN_OR_BETTER)
    measured = [
        game
        for game in started
        if game.max_possible >= MIN_SET_SIZE and game.console_id not in NON_GAME_CONSOLES
    ]
    average = (
        sum(game.earned / game.max_possible for game in measured) / len(measured)
        if measured
        else None
    )
    per_week = None
    if first_hardcore_unlock is not None and profile.hardcore_points:
        weeks = max(int((now - first_hardcore_unlock) // WEEK), 1)
        per_week = profile.hardcore_points / weeks
    return PlayerStats(
        unlocks_hardcore=hardcore,
        unlocks_casual=casual,
        retro_ratio=ratio,
        games_beaten=total_beaten,
        games_beaten_retail=retail,
        started_beaten=awarded / len(started) if started else None,
        average_completion=average,
        points_per_week=per_week,
    )


@dataclass(frozen=True, slots=True)
class ConsoleProgress:
    """Games played, beaten and mastered on one console (cumulative: mastered games are beaten).

    Attributes:
        console_name: Console name.
        played: Games with at least one unlock.
        beaten: Of those, games with any award (beaten, completed or mastered).
        mastered: Of those, games mastered or completed (100%, hardcore or casual).
        last_activity: Latest unlock or play on this console (epoch seconds; 0 if unknown).
    """

    console_name: str
    played: int
    beaten: int
    mastered: int
    last_activity: int = 0


def console_progress(games: Iterable[GameProgress]) -> list[ConsoleProgress]:
    """Count started games per console, the most recently played console first.

    Args:
        games: Library.

    Returns:
        One row per console with started games (Hubs and Events left out).
    """
    by_console: dict[str, list[GameProgress]] = {}
    for game in _started(games):
        if game.console_id not in NON_GAME_CONSOLES:
            by_console.setdefault(game.console_name, []).append(game)
    rows = [
        ConsoleProgress(
            console_name=name,
            played=len(members),
            beaten=sum(1 for game in members if game.highest_award is not None),
            mastered=sum(1 for game in members if game.highest_award in MASTERY),
            last_activity=max(activity(game) for game in members),
        )
        for name, members in by_console.items()
    ]
    return sorted(rows, key=lambda row: (-row.last_activity, -row.played, row.console_name.lower()))


@dataclass(frozen=True, slots=True)
class RecentPoints:
    """Points earned recently, from an unlock window.

    Attributes:
        last_7_days: Points in the last 7 days (today included).
        last_30_days: Points in the last 30 days.
        per_day: Points per day for the last 30 days, oldest first.
        hardcore: Only hardcore unlocks were counted (casual players count everything).
        fetched_at: When the window was fetched.
    """

    last_7_days: int
    last_30_days: int
    per_day: tuple[int, ...]
    hardcore: bool
    fetched_at: int


def window_start(now: float) -> int:
    """Return the start of the unlock window: midnight (UTC) 29 days before today.

    Args:
        now: Current time.

    Returns:
        Epoch seconds.
    """
    today = int(now) // DAY * DAY
    return today - (WINDOW_DAYS - 1) * DAY


def recent_points(window: UnlockWindow, *, casual_player: bool) -> RecentPoints:
    """Sum the points of a window, per day and for the last 7 and 30 days.

    Like RA's site: hardcore unlocks only (everything for a mostly casual player), and no
    Hubs or Events.

    Args:
        window: Unlocks fetched from :func:`window_start` until ``window.end``.
        casual_player: The player has more casual than hardcore points.

    Returns:
        The points.
    """
    first_day = window_start(window.end)
    per_day = [0] * WINDOW_DAYS
    for unlock in window.unlocks:
        if unlock.console_name in NON_GAME_CONSOLE_NAMES:
            continue
        if not (unlock.hardcore or casual_player):
            continue
        day = (unlock.unlocked_at - first_day) // DAY
        if 0 <= day < WINDOW_DAYS:
            per_day[day] += unlock.points
    return RecentPoints(
        last_7_days=sum(per_day[-SHORT_WINDOW_DAYS:]),
        last_30_days=sum(per_day),
        per_day=tuple(per_day),
        hardcore=not casual_player,
        fetched_at=window.end,
    )
