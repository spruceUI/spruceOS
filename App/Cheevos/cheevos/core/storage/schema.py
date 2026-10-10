"""The data cache's schema and row conversions (``data.db``; see :mod:`data_cache`).

The cache is disposable: bumping :data:`SCHEMA_VERSION` recreates it on the next open, and
the next sync fills it again. There are no migrations.
"""

from __future__ import annotations

import sqlite3

from cheevos.core.models import (
    Achievement,
    AchievementType,
    Award,
    AwardKind,
    GameDetail,
    GameProgress,
)

SCHEMA_VERSION = 2  # 2: awards gained console_id and display_order
DDL = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE profile (username TEXT PRIMARY KEY, json TEXT NOT NULL, synced_at INTEGER NOT NULL);
CREATE TABLE games (
    game_id INTEGER PRIMARY KEY, title TEXT NOT NULL, console_id INTEGER NOT NULL,
    console_name TEXT NOT NULL, image_icon TEXT NOT NULL, max_possible INTEGER NOT NULL,
    num_awarded INTEGER NOT NULL, num_awarded_hc INTEGER NOT NULL,
    most_recent_awarded_at INTEGER, highest_award_kind TEXT, highest_award_at INTEGER,
    last_played_at INTEGER, detail_synced_at INTEGER, detail_fingerprint TEXT
);
CREATE TABLE achievements (
    achievement_id INTEGER PRIMARY KEY,
    game_id INTEGER NOT NULL REFERENCES games(game_id) ON DELETE CASCADE,
    title TEXT NOT NULL, description TEXT NOT NULL, points INTEGER NOT NULL,
    true_ratio INTEGER NOT NULL, badge_name TEXT NOT NULL, display_order INTEGER NOT NULL,
    type TEXT, num_awarded INTEGER NOT NULL, num_awarded_hc INTEGER NOT NULL,
    earned_at INTEGER, earned_hc_at INTEGER, unlocked_at INTEGER
);
CREATE INDEX achievements_by_game ON achievements(game_id, display_order, achievement_id);
CREATE INDEX achievements_by_unlock ON achievements(unlocked_at) WHERE unlocked_at IS NOT NULL;
CREATE TABLE game_stats (
    game_id INTEGER PRIMARY KEY REFERENCES games(game_id) ON DELETE CASCADE,
    num_distinct_players INTEGER NOT NULL, num_players_casual INTEGER NOT NULL,
    num_players_hc INTEGER NOT NULL
);
CREATE TABLE awards (
    game_id INTEGER NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL,
    console_id INTEGER NOT NULL, console_name TEXT NOT NULL, image_icon TEXT NOT NULL,
    awarded_at INTEGER, display_order INTEGER NOT NULL,
    PRIMARY KEY (game_id, kind)
);
"""


GAME_COLUMNS = (
    "game_id, title, console_id, console_name, image_icon, max_possible, num_awarded, "
    "num_awarded_hc, most_recent_awarded_at, highest_award_kind, highest_award_at, last_played_at"
)
# Later upserts win for always-known fields; a NULL never erases a value another source knew
# (recently-played games carry no award, completion progress carries no last-played time).
UPSERT_GAME = f"""
INSERT INTO games ({GAME_COLUMNS}) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(game_id) DO UPDATE SET
    title = excluded.title,
    console_id = excluded.console_id,
    console_name = excluded.console_name,
    image_icon = excluded.image_icon,
    max_possible = excluded.max_possible,
    num_awarded = excluded.num_awarded,
    num_awarded_hc = excluded.num_awarded_hc,
    most_recent_awarded_at = excluded.most_recent_awarded_at,
    highest_award_kind = excluded.highest_award_kind,
    highest_award_at = excluded.highest_award_at,
    last_played_at = COALESCE(excluded.last_played_at, last_played_at)
"""  # noqa: S608 — column list is a module constant, values are bound parameters
ACHIEVEMENT_COLUMNS = (
    "achievement_id, game_id, title, description, points, true_ratio, badge_name, "
    "display_order, type, num_awarded, num_awarded_hc, earned_at, earned_hc_at"
)
# Same order as the model's fields.
AWARD_COLUMNS = (
    "game_id, title, console_name, image_icon, kind, awarded_at, console_id, display_order"
)
ACTIVITY_ORDER = (
    "MAX(COALESCE(most_recent_awarded_at, 0), COALESCE(last_played_at, 0)) DESC, "
    "title COLLATE NOCASE, game_id"
)


def game_row(game: GameProgress) -> tuple[object, ...]:
    """Flatten a game into ``GAME_COLUMNS`` order.

    Args:
        game: List-level game data.

    Returns:
        Values for an insert.
    """
    return (
        game.game_id,
        game.title,
        game.console_id,
        game.console_name,
        game.image_icon,
        game.max_possible,
        game.earned,
        game.earned_hardcore,
        game.last_unlock_at,
        game.highest_award.value if game.highest_award else None,
        game.highest_award_at,
        game.last_played_at,
    )


def game_from_row(row: sqlite3.Row) -> GameProgress:
    """Build a game from a ``games`` row.

    Args:
        row: Row selected with ``GAME_COLUMNS`` (same order as the model's fields).

    Returns:
        The game.
    """
    kind = row["highest_award_kind"]
    award = AwardKind(kind) if kind else None
    r = row
    return GameProgress(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], award, r[10], r[11])


def achievement_row(achievement: Achievement) -> tuple[object, ...]:
    """Flatten an achievement into ``ACHIEVEMENT_COLUMNS`` order plus ``unlocked_at``.

    Args:
        achievement: The achievement.

    Returns:
        Values for an insert.
    """
    return (
        achievement.achievement_id,
        achievement.game_id,
        achievement.title,
        achievement.description,
        achievement.points,
        achievement.retro_points,
        achievement.badge_name,
        achievement.display_order,
        achievement.type.value if achievement.type else None,
        achievement.num_awarded,
        achievement.num_awarded_hardcore,
        achievement.earned_at,
        achievement.earned_hardcore_at,
        achievement.unlocked_at,
    )


def achievement_from_row(row: sqlite3.Row) -> Achievement:
    """Build an achievement from an ``achievements`` row.

    Args:
        row: Row selected with ``ACHIEVEMENT_COLUMNS`` (same order as the model's fields).

    Returns:
        The achievement.
    """
    kind = row["type"]
    tag = AchievementType(kind) if kind else None
    r = row
    return Achievement(
        r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], tag, r[9], r[10], r[11], r[12]
    )


def award_row(award: Award) -> tuple[object, ...]:
    """Flatten an award into ``AWARD_COLUMNS`` order.

    Args:
        award: The award.

    Returns:
        Values for an insert.
    """
    return (
        award.game_id,
        award.title,
        award.console_name,
        award.image_icon,
        award.kind.value,
        award.awarded_at,
        award.console_id,
        award.display_order,
    )


def award_from_row(row: sqlite3.Row) -> Award:
    """Build an award from an ``awards`` row selected with ``AWARD_COLUMNS``.

    Args:
        row: The row.

    Returns:
        The award.
    """
    r = row
    return Award(r[0], r[1], r[2], r[3], AwardKind(r[4]), r[5], r[6], r[7])


def game_from_detail(detail: GameDetail) -> GameProgress:
    """Derive list-level data for a game known only from its detail fetch.

    Args:
        detail: The game's detail.

    Returns:
        A game row with counts computed from the achievements (console ID unknown: 0).
    """
    unlock_times = [a.unlocked_at for a in detail.achievements if a.unlocked_at is not None]
    return GameProgress(
        game_id=detail.game_id,
        title=detail.title,
        console_id=0,
        console_name=detail.console_name,
        image_icon=detail.image_icon,
        max_possible=len(detail.achievements),
        earned=sum(1 for a in detail.achievements if a.unlocked),
        earned_hardcore=sum(1 for a in detail.achievements if a.hardcore),
        last_unlock_at=max(unlock_times) if unlock_times else None,
        highest_award=None,
        highest_award_at=None,
    )
