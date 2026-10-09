"""Domain models shared by every core module.

Plain frozen dataclasses: parsed from RA responses at the client boundary, stored in the cache,
read by screens. Times are UTC epoch seconds (``int``); ``None`` means "never" or "unknown".
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

# RA's "unsupported emulator/core" warning pseudo-achievement. It is not a real achievement:
# RetroArch still saves an unlock screenshot for it, and RAOfflineProxy strips it.
WARNING_ACHIEVEMENT_ID = 101000001


class AchievementType(Enum):
    """RA achievement type tags (``Type`` in the Web API)."""

    PROGRESSION = "progression"
    WIN_CONDITION = "win_condition"
    MISSABLE = "missable"


class AwardKind(Enum):
    """Highest award a user holds for a game (``HighestAwardKind`` in the Web API)."""

    MASTERED = "mastered"  # 100% in hardcore
    COMPLETED = "completed"  # 100% in casual
    BEATEN_HARDCORE = "beaten-hardcore"
    BEATEN_SOFTCORE = "beaten-softcore"


@dataclass(frozen=True, slots=True)
class UserProfile:
    """Account summary for the dashboard.

    Attributes:
        username: RA username as RA spells it.
        user_pic: Avatar path on the media host, e.g. ``"/UserPic/Balah.png"``.
        motto: User motto (may be empty).
        member_since: Registration time.
        hardcore_points: ``TotalPoints``.
        softcore_points: ``TotalSoftcorePoints``.
        retro_points: ``TotalTruePoints``.
        rank: Hardcore rank, ``None`` when unranked.
        total_ranked: Number of ranked users, if known.
        rich_presence: Last rich-presence message (may be empty).
        last_game_id: Last played game, if any.
        rich_presence_at: When the rich presence last changed (RA's closest thing to "last
            activity"; the API's ``LastActivity`` is always empty).
        last_game_title: Last played game's title (may be empty).
        last_game_console: Its console name (may be empty).
        last_game_icon: Its icon path on the media host (may be empty).
    """

    username: str
    user_pic: str
    motto: str
    member_since: int | None
    hardcore_points: int
    softcore_points: int
    retro_points: int
    rank: int | None
    total_ranked: int | None
    rich_presence: str
    last_game_id: int | None
    rich_presence_at: int | None = None
    last_game_title: str = ""
    last_game_console: str = ""
    last_game_icon: str = ""


@dataclass(frozen=True, slots=True)
class GameProgress:
    """A game in the user's library with their progress (list-level data).

    Attributes:
        game_id: RA game ID.
        title: Game title.
        console_id: RA console ID.
        console_name: Console name.
        image_icon: Icon path on the media host, e.g. ``"/Images/070805.png"``.
        max_possible: Achievements in the set.
        earned: Achievements earned in any mode.
        earned_hardcore: Achievements earned in hardcore.
        last_unlock_at: Most recent unlock.
        highest_award: Highest award, if any.
        highest_award_at: When the highest award was earned.
        last_played_at: Last time the user played it (recently-played games only).
    """

    game_id: int
    title: str
    console_id: int
    console_name: str
    image_icon: str
    max_possible: int
    earned: int
    earned_hardcore: int
    last_unlock_at: int | None
    highest_award: AwardKind | None
    highest_award_at: int | None
    last_played_at: int | None = None

    @property
    def fingerprint(self) -> str:
        """Summarise everything that changes when the user unlocks something or a set changes.

        The sync engine re-fetches a game's details only when this differs from the value
        stored with its last detail fetch.
        """
        award = self.highest_award.value if self.highest_award else ""
        return (
            f"{self.max_possible}:{self.earned}:{self.earned_hardcore}:"
            f"{self.last_unlock_at or 0}:{award}"
        )


@dataclass(frozen=True, slots=True)
class Achievement:
    """One achievement with the user's unlock state.

    Attributes:
        achievement_id: RA achievement ID.
        game_id: RA game ID.
        title: Title.
        description: Description.
        points: Points.
        retro_points: RetroPoints (``TrueRatio``).
        badge_name: Badge name; media path ``/Badge/<badge_name>.png`` (``_lock`` variant too).
        display_order: Position in RA's ordering.
        type: Type tag, if any.
        num_awarded: Players who unlocked it in any mode.
        num_awarded_hardcore: Players who unlocked it in hardcore.
        earned_at: When the user unlocked it in casual (or any) mode.
        earned_hardcore_at: When the user unlocked it in hardcore.
    """

    achievement_id: int
    game_id: int
    title: str
    description: str
    points: int
    retro_points: int
    badge_name: str
    display_order: int
    type: AchievementType | None
    num_awarded: int
    num_awarded_hardcore: int
    earned_at: int | None
    earned_hardcore_at: int | None

    @property
    def unlocked(self) -> bool:
        """Whether the user has unlocked it in any mode."""
        return self.earned_at is not None or self.earned_hardcore_at is not None

    @property
    def hardcore(self) -> bool:
        """Whether the user unlocked it in hardcore."""
        return self.earned_hardcore_at is not None

    @property
    def unlocked_at(self) -> int | None:
        """Earliest unlock time in any mode."""
        times = [t for t in (self.earned_hardcore_at, self.earned_at) if t is not None]
        return min(times) if times else None


@dataclass(frozen=True, slots=True)
class GameDetail:
    """A game's achievement set and statistics.

    Attributes:
        game_id: RA game ID.
        title: Game title.
        console_name: Console name.
        image_icon: Icon path on the media host.
        num_distinct_players: Players of the game (any mode).
        num_players_casual: Players in casual.
        num_players_hardcore: Players in hardcore.
        achievements: Achievements in display order.
    """

    game_id: int
    title: str
    console_name: str
    image_icon: str
    num_distinct_players: int
    num_players_casual: int
    num_players_hardcore: int
    achievements: tuple[Achievement, ...]


@dataclass(frozen=True, slots=True)
class Award:
    """A mastery/completion/beaten award shown on the awards wall.

    Attributes:
        game_id: RA game ID.
        title: Game title.
        console_name: Console name.
        image_icon: Icon path on the media host.
        kind: Award kind (mode included).
        awarded_at: When it was earned.
        console_id: RA console ID (0 when unknown).
        display_order: The user's own ordering on RA's site.
    """

    game_id: int
    title: str
    console_name: str
    image_icon: str
    kind: AwardKind
    awarded_at: int | None
    console_id: int = 0
    display_order: int = 0


@dataclass(frozen=True, slots=True)
class AwardCounts:
    """Award counters from ``API_GetUserAwards``.

    Attributes:
        mastered: Mastery awards (hardcore 100%).
        completed: Completion awards (casual 100%).
        beaten_hardcore: Beaten in hardcore.
        beaten_softcore: Beaten in casual.
    """

    mastered: int
    completed: int
    beaten_hardcore: int
    beaten_softcore: int


@dataclass(frozen=True, slots=True)
class PendingAward:
    """An unlock queued by RAOfflineProxy, waiting to be submitted to RA (always casual).

    Attributes:
        achievement_id: RA achievement ID.
        game_id: RA game ID, if the proxy has the game's data cached.
        game_title: Game title (``""`` if unknown).
        achievement_title: Achievement title (``""`` if unknown).
        points: Points, if known.
        queued_at: When it was queued.
    """

    achievement_id: int
    game_id: int | None
    game_title: str
    achievement_title: str
    points: int | None
    queued_at: int | None


@dataclass(frozen=True, slots=True)
class LocalGame:
    """A ROM on the SD card already identified as an RA game by Spruce or the proxy.

    Attributes:
        game_id: RA game ID.
        rom_path: Absolute ROM path on the device.
        system: Spruce system name (``""`` if unknown).
        source: Where the match came from, e.g. ``"raofflineproxy"``.
    """

    game_id: int
    rom_path: str
    system: str
    source: str


@dataclass(frozen=True, slots=True)
class Unlock:
    """One achievement the user unlocked, from ``API_GetAchievementsEarnedBetween``.

    Attributes:
        achievement_id: RA achievement ID.
        game_id: RA game ID.
        points: Points.
        hardcore: Unlocked in hardcore.
        unlocked_at: When (UTC epoch seconds).
        console_name: The game's console ("Events" and "Hubs" are not real games).
    """

    achievement_id: int
    game_id: int
    points: int
    hardcore: bool
    unlocked_at: int
    console_name: str


@dataclass(frozen=True, slots=True)
class UnlockWindow:
    """The user's unlocks in a time window, as fetched (for points in the last 7/30 days).

    Attributes:
        start: Window start (UTC epoch seconds).
        end: Window end, i.e. when it was fetched.
        unlocks: The unlocks, oldest first.
    """

    start: int
    end: int
    unlocks: tuple[Unlock, ...]
