"""Turn decoded RetroAchievements Web API JSON into domain models.

Pure functions, tolerant by design: RA sends numbers as ints or strings and omits or nulls
fields freely, so missing values get safe defaults. Only payloads with the wrong overall shape
(e.g. a list where an object is expected) raise :class:`ApiPayloadError`.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime, timezone
from typing import Any

from cheevos.core.errors import ApiPayloadError
from cheevos.core.models import (
    WARNING_ACHIEVEMENT_ID,
    Achievement,
    AchievementType,
    Award,
    AwardCounts,
    AwardKind,
    GameDetail,
    GameProgress,
    RecentUnlock,
    Unlock,
    UserProfile,
)

# VisibleUserAwards.AwardType -> award kind for (hardcore, casual) via AwardDataExtra.
_AWARD_TYPES: dict[str, tuple[AwardKind, AwardKind]] = {
    "Mastery/Completion": (AwardKind.MASTERED, AwardKind.COMPLETED),
    "Game Beaten": (AwardKind.BEATEN_HARDCORE, AwardKind.BEATEN_SOFTCORE),
}


def parse_time(value: object) -> int | None:
    """Parse an RA timestamp into UTC epoch seconds.

    RA uses ``"2026-08-21 17:02:50"`` (UTC, no zone) and ``"2026-08-22T11:42:13+00:00"``.

    Args:
        value: Timestamp string, or ``None``/``""``.

    Returns:
        Epoch seconds, or ``None`` when empty or unparseable.
    """
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip().replace("Z", "+00:00")
    try:
        moment = datetime.fromisoformat(text)
    except ValueError:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return int(moment.timestamp())


def _int(value: object, default: int = 0) -> int:
    """Read an integer RA may send as int, float or numeric string.

    Args:
        value: Raw value.
        default: Result for missing or non-numeric values.

    Returns:
        The integer.
    """
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        try:
            return int(float(value.strip()))
        except ValueError:
            return default
    return default


def _optional_id(value: object) -> int | None:
    """Read an optional positive ID or rank (``None``, ``0`` and garbage mean "none").

    Args:
        value: Raw value.

    Returns:
        The positive integer, or ``None``.
    """
    number = _int(value)
    return number if number > 0 else None


def _str(value: object) -> str:
    """Read a string field (``None`` becomes ``""``).

    Args:
        value: Raw value.

    Returns:
        The string.
    """
    return "" if value is None else str(value)


def _object(data: object, what: str) -> Mapping[str, Any]:
    """Check that a payload is a JSON object.

    Args:
        data: Decoded JSON.
        what: Payload name for the error message.

    Returns:
        The object.

    Raises:
        ApiPayloadError: If ``data`` is not an object.
    """
    if not isinstance(data, Mapping):
        raise ApiPayloadError(f"{what}: expected a JSON object, got {type(data).__name__}")
    return data


def _award_kind(value: object) -> AwardKind | None:
    """Read ``HighestAwardKind``.

    Args:
        value: Raw value, e.g. ``"beaten-hardcore"`` or ``None``.

    Returns:
        The award kind, or ``None`` (also for unknown values).
    """
    try:
        return AwardKind(value) if value else None
    except ValueError:
        return None


def parse_user_summary(data: object) -> UserProfile:
    """Parse ``API_GetUserSummary`` (``API_GetUserProfile`` works too; it lacks the rank).

    Args:
        data: Decoded JSON.

    Returns:
        The profile.

    Raises:
        ApiPayloadError: If the payload is not an object or has no username.
    """
    summary = _object(data, "user summary")
    last_game = summary.get("LastGame")  # present when asked for recent games (g >= 1)
    last_game = last_game if isinstance(last_game, Mapping) else {}
    username = _str(summary.get("User"))
    if not username:
        raise ApiPayloadError("user summary: missing 'User'")
    return UserProfile(
        username=username,
        user_pic=_str(summary.get("UserPic")) or f"/UserPic/{username}.png",
        motto=_str(summary.get("Motto")),
        member_since=parse_time(summary.get("MemberSince")),
        hardcore_points=_int(summary.get("TotalPoints")),
        softcore_points=_int(summary.get("TotalSoftcorePoints")),
        retro_points=_int(summary.get("TotalTruePoints")),
        rank=_optional_id(summary.get("Rank")),
        total_ranked=_optional_id(summary.get("TotalRanked")),
        rich_presence=_str(summary.get("RichPresenceMsg")),
        last_game_id=_optional_id(summary.get("LastGameID")),
        rich_presence_at=parse_time(summary.get("RichPresenceMsgDate")),
        last_game_title=_str(last_game.get("Title")),
        last_game_console=_str(last_game.get("ConsoleName")),
        last_game_icon=_str(last_game.get("ImageIcon")),
    )


def parse_completion_progress(data: object) -> tuple[list[GameProgress], int]:
    """Parse one page of ``API_GetUserCompletionProgress``.

    Args:
        data: Decoded JSON.

    Returns:
        The page's games and the total number of games across all pages.

    Raises:
        ApiPayloadError: If the payload or its ``Results`` has the wrong shape.
    """
    page = _object(data, "completion progress")
    results = page.get("Results") or []
    if not isinstance(results, list):
        raise ApiPayloadError("completion progress: 'Results' is not a list")
    games = [
        GameProgress(
            game_id=_int(row.get("GameID")),
            title=_str(row.get("Title")),
            console_id=_int(row.get("ConsoleID")),
            console_name=_str(row.get("ConsoleName")),
            image_icon=_str(row.get("ImageIcon")),
            max_possible=_int(row.get("MaxPossible")),
            earned=_int(row.get("NumAwarded")),
            earned_hardcore=_int(row.get("NumAwardedHardcore")),
            last_unlock_at=parse_time(row.get("MostRecentAwardedDate")),
            highest_award=_award_kind(row.get("HighestAwardKind")),
            highest_award_at=parse_time(row.get("HighestAwardDate")),
        )
        for row in (_object(item, "completion progress row") for item in results)
    ]
    return games, _int(page.get("Total"), default=len(games))


def parse_recently_played(data: object) -> list[GameProgress]:
    """Parse ``API_GetUserRecentlyPlayedGames``.

    This endpoint also lists games played without any unlock, which completion progress omits.

    Args:
        data: Decoded JSON (a list).

    Returns:
        The games, with ``last_played_at`` set.

    Raises:
        ApiPayloadError: If the payload is not a list of objects.
    """
    if not isinstance(data, list):
        raise ApiPayloadError("recently played: expected a JSON list")
    games = []
    for item in data:
        row = _object(item, "recently played row")
        total = row.get("NumPossibleAchievements")
        games.append(
            GameProgress(
                game_id=_int(row.get("GameID")),
                title=_str(row.get("Title")),
                console_id=_int(row.get("ConsoleID")),
                console_name=_str(row.get("ConsoleName")),
                image_icon=_str(row.get("ImageIcon")),
                max_possible=_int(total if total is not None else row.get("AchievementsTotal")),
                earned=_int(row.get("NumAchieved")),
                earned_hardcore=_int(row.get("NumAchievedHardcore")),
                last_unlock_at=None,
                highest_award=None,
                highest_award_at=None,
                last_played_at=parse_time(row.get("LastPlayed")),
            )
        )
    return games


def _achievement(game_id: int, row: Mapping[str, Any]) -> Achievement:
    """Parse one entry of ``GetGameInfoAndUserProgress.Achievements``.

    Args:
        game_id: The game the achievement belongs to.
        row: The raw entry.

    Returns:
        The achievement.
    """
    try:
        kind = AchievementType(row.get("Type")) if row.get("Type") else None
    except ValueError:
        kind = None
    return Achievement(
        achievement_id=_int(row.get("ID")),
        game_id=game_id,
        title=_str(row.get("Title")),
        description=_str(row.get("Description")),
        points=_int(row.get("Points")),
        retro_points=_int(row.get("TrueRatio")),
        badge_name=_str(row.get("BadgeName")),
        display_order=_int(row.get("DisplayOrder")),
        type=kind,
        num_awarded=_int(row.get("NumAwarded")),
        num_awarded_hardcore=_int(row.get("NumAwardedHardcore")),
        earned_at=parse_time(row.get("DateEarned")),
        earned_hardcore_at=parse_time(row.get("DateEarnedHardcore")),
    )


def parse_game_detail(data: object) -> GameDetail:
    """Parse ``API_GetGameInfoAndUserProgress``.

    Achievements come sorted by display order, then ID. RA's warning pseudo-achievement is
    dropped.

    Args:
        data: Decoded JSON.

    Returns:
        The game detail.

    Raises:
        ApiPayloadError: If the payload has the wrong shape or no game ID.
    """
    game = _object(data, "game detail")
    game_id = _int(game.get("ID"))
    if game_id <= 0:
        raise ApiPayloadError("game detail: missing 'ID'")
    raw = game.get("Achievements") or {}
    if isinstance(raw, Mapping):
        raw = list(raw.values())
    if not isinstance(raw, list):
        raise ApiPayloadError("game detail: 'Achievements' has the wrong shape")
    achievements = [_achievement(game_id, _object(item, "achievement")) for item in raw]
    achievements = [a for a in achievements if a.achievement_id != WARNING_ACHIEVEMENT_ID]
    achievements.sort(key=lambda a: (a.display_order, a.achievement_id))
    return GameDetail(
        game_id=game_id,
        title=_str(game.get("Title")),
        console_name=_str(game.get("ConsoleName")),
        image_icon=_str(game.get("ImageIcon")),
        num_distinct_players=_int(game.get("NumDistinctPlayers")),
        num_players_casual=_int(game.get("NumDistinctPlayersCasual")),
        num_players_hardcore=_int(game.get("NumDistinctPlayersHardcore")),
        achievements=tuple(achievements),
    )


def _award(row: Mapping[str, Any]) -> Award | None:
    """Parse one ``VisibleUserAwards`` entry; only game awards are kept.

    Args:
        row: The raw entry.

    Returns:
        The award, or ``None`` for site/event awards.
    """
    kinds = _AWARD_TYPES.get(_str(row.get("AwardType")))
    game_id = _int(row.get("AwardData"))
    if kinds is None or game_id <= 0:
        return None
    hardcore = _int(row.get("AwardDataExtra")) == 1
    return Award(
        game_id=game_id,
        title=_str(row.get("Title")),
        console_name=_str(row.get("ConsoleName")),
        image_icon=_str(row.get("ImageIcon")),
        kind=kinds[0] if hardcore else kinds[1],
        awarded_at=parse_time(row.get("AwardedAt")),
        console_id=_int(row.get("ConsoleID")),
        display_order=_int(row.get("DisplayOrder")),
    )


def parse_awards(data: object) -> tuple[AwardCounts, list[Award]]:
    """Parse ``API_GetUserAwards``.

    Args:
        data: Decoded JSON.

    Returns:
        The counters and the visible game awards (mastery, completion, beaten).

    Raises:
        ApiPayloadError: If the payload has the wrong shape.
    """
    payload = _object(data, "user awards")
    counts = AwardCounts(
        mastered=_int(payload.get("MasteryAwardsCount")),
        completed=_int(payload.get("CompletionAwardsCount")),
        beaten_hardcore=_int(payload.get("BeatenHardcoreAwardsCount")),
        beaten_softcore=_int(payload.get("BeatenSoftcoreAwardsCount")),
    )
    rows = payload.get("VisibleUserAwards") or []
    if not isinstance(rows, list):
        raise ApiPayloadError("user awards: 'VisibleUserAwards' is not a list")
    awards = [award for row in rows if (award := _award(_object(row, "award"))) is not None]
    return counts, awards


def parse_unlocks(data: object) -> list[Unlock]:
    """Parse ``API_GetAchievementsEarnedBetween`` (oldest first).

    Args:
        data: Decoded JSON.

    Returns:
        The unlocks; rows without an achievement ID or a date are skipped.

    Raises:
        ApiPayloadError: If the payload is not a list.
    """
    if not isinstance(data, list):
        raise ApiPayloadError("unlocks: expected a list")
    unlocks = []
    for raw in data:
        row = _object(raw, "unlock")
        achievement_id = _int(row.get("AchievementID"))
        unlocked_at = parse_time(row.get("Date"))
        if achievement_id <= 0 or unlocked_at is None:
            continue
        unlocks.append(
            Unlock(
                achievement_id=achievement_id,
                game_id=_int(row.get("GameID")),
                points=_int(row.get("Points")),
                hardcore=_int(row.get("HardcoreMode")) == 1,
                unlocked_at=unlocked_at,
                console_name=_str(row.get("ConsoleName")),
            )
        )
    return unlocks


def parse_recent_unlocks(data: object) -> list[RecentUnlock]:
    """Parse date-range unlock rows with the definitions needed for an offline feed."""
    if not isinstance(data, list):
        raise ApiPayloadError("recent unlocks: expected a list")
    entries = []
    for raw in data:
        row = _object(raw, "recent unlock")
        achievement_id, game_id = _int(row.get("AchievementID")), _int(row.get("GameID"))
        date = row.get("Date")
        if (
            achievement_id <= 0
            or achievement_id == WARNING_ACHIEVEMENT_ID
            or game_id <= 0
            or parse_time(date) is None
        ):
            continue
        hardcore = _int(row.get("HardcoreMode")) == 1
        definition = {
            **row,
            "ID": achievement_id,
            "DateEarned": None if hardcore else date,
            "DateEarnedHardcore": date if hardcore else None,
        }
        entries.append(
            RecentUnlock(
                _achievement(game_id, definition),
                _str(row.get("GameTitle")),
                _str(row.get("GameIcon")),
                _str(row.get("ConsoleName")),
            )
        )
    return entries
