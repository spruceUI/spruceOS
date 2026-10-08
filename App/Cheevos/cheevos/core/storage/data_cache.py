"""The RA data cache (``Saves/cheevos/cache/data.db``): profile, games, achievements, awards.

Everything here is rebuildable from RetroAchievements, so the file is disposable
(.agents/sync-and-storage.md): a schema change or corruption recreates it, and so does opening
it for a different username.
Times are stored as INTEGER UTC epoch seconds and enums by their RA string values.

A :class:`DataCache` wraps one connection; use it only on the thread that opened it.
"""

from __future__ import annotations

import dataclasses
import json
import logging
import sqlite3
from collections.abc import Iterable
from pathlib import Path

from cheevos.core.models import (
    Achievement,
    Award,
    AwardCounts,
    AwardKind,
    GameDetail,
    GameProgress,
    Unlock,
    UnlockWindow,
    UserProfile,
)
from cheevos.core.storage.db import open_cache, reset_cache, select_among
from cheevos.core.storage.schema import (
    ACHIEVEMENT_COLUMNS,
    ACTIVITY_ORDER,
    AWARD_COLUMNS,
    DDL,
    GAME_COLUMNS,
    SCHEMA_VERSION,
    UPSERT_GAME,
    achievement_from_row,
    achievement_row,
    award_from_row,
    award_row,
    game_from_detail,
    game_from_row,
    game_row,
)

logger = logging.getLogger(__name__)

_USERNAME_KEY = "username"
_AWARD_COUNTS_KEY = "award_counts"
_UNLOCK_WINDOW_KEY = "unlock_window"
FIRST_HARDCORE_UNLOCK_KEY = "first_hardcore_unlock_at"


class DataCache:
    """Typed access to ``data.db`` for one RA account.

    Args:
        path: Database file.
        connection: Open connection to it (schema already verified).
    """

    def __init__(self, path: Path, connection: sqlite3.Connection) -> None:
        self._path = path
        self._db = connection

    @classmethod
    def open(cls, path: Path, username: str) -> DataCache:
        """Open (or create) the cache for ``username``.

        A cache that belongs to another username (compared case-insensitively) is reset,
        because its contents describe a different account.

        Args:
            path: Database file.
            username: RA account the cache is for.

        Returns:
            The cache.
        """
        connection = open_cache(path, schema_version=SCHEMA_VERSION, ddl=DDL)
        cache = cls(path, connection)
        stored = cache.get_meta(_USERNAME_KEY)
        if stored is not None and stored.casefold() != username.casefold():
            logger.info("Cache %s belongs to another account; resetting", path)
            connection.close()
            cache = cls(path, reset_cache(path, schema_version=SCHEMA_VERSION, ddl=DDL))
        cache.set_meta(_USERNAME_KEY, username)
        return cache

    def close(self) -> None:
        """Close the connection."""
        self._db.close()

    def version(self) -> tuple[int, int]:
        """Return a token that changes whenever the database changes, through any connection.

        Reads no table, so a screen can check it on every visit to skip rebuilding from
        unchanged data. Writes on other connections (the sync thread, the game worker) change
        SQLite's ``data_version``; this connection's own writes change ``total_changes``.

        Returns:
            The token; compare it for equality only.
        """
        (data_version,) = self._db.execute("PRAGMA data_version").fetchone()
        return int(data_version), self._db.total_changes

    # --- meta -------------------------------------------------------------------------------

    def get_meta(self, key: str) -> str | None:
        """Return a meta value.

        Args:
            key: Meta key.

        Returns:
            The value, or ``None`` if unset.
        """
        row = self._db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        return None if row is None else str(row["value"])

    def set_meta(self, key: str, value: str | None) -> None:
        """Set a meta value; ``None`` deletes it.

        Args:
            key: Meta key.
            value: New value, or ``None`` to delete.
        """
        with self._db:
            if value is None:
                self._db.execute("DELETE FROM meta WHERE key = ?", (key,))
            else:
                self._db.execute(
                    "INSERT INTO meta (key, value) VALUES (?, ?) "
                    "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    (key, value),
                )

    # --- profile ----------------------------------------------------------------------------

    def save_profile(self, profile: UserProfile, synced_at: int) -> None:
        """Store the account profile.

        Args:
            profile: Profile from RA.
            synced_at: When it was fetched.
        """
        payload = json.dumps(dataclasses.asdict(profile))
        with self._db:
            self._db.execute("DELETE FROM profile")
            self._db.execute(
                "INSERT INTO profile (username, json, synced_at) VALUES (?, ?, ?)",
                (profile.username, payload, synced_at),
            )

    def load_profile(self) -> UserProfile | None:
        """Return the stored profile.

        Returns:
            The profile, or ``None`` if none is stored or it cannot be decoded.
        """
        row = self._db.execute("SELECT json FROM profile LIMIT 1").fetchone()
        if row is None:
            return None
        try:
            data = json.loads(row["json"])
            names = {field.name for field in dataclasses.fields(UserProfile)}
            return UserProfile(**{name: data.get(name) for name in names})
        except (TypeError, ValueError, AttributeError):
            logger.warning("Stored profile is unreadable; ignoring it")
            return None

    # --- games ------------------------------------------------------------------------------

    def upsert_games(self, games: Iterable[GameProgress]) -> None:
        """Insert or update list-level game data, keeping each game's detail-sync state.

        Args:
            games: Games from completion progress and/or recently played.
        """
        with self._db:
            self._db.executemany(UPSERT_GAME, [game_row(game) for game in games])

    def games(self) -> list[GameProgress]:
        """Return all games, most recent activity (unlock or play) first, then by title."""
        rows = self._db.execute(
            f"SELECT {GAME_COLUMNS} FROM games ORDER BY {ACTIVITY_ORDER}"  # noqa: S608
        ).fetchall()
        return [game_from_row(row) for row in rows]

    def game_counts(self) -> tuple[int, int]:
        """Count the games, and the ones with an award, without reading them (home summary).

        Returns:
            ``(games, games with an award)``.
        """
        row = self._db.execute("SELECT COUNT(*), COUNT(highest_award_kind) FROM games").fetchone()
        return int(row[0]), int(row[1])

    def game_titles(self, game_ids: Iterable[int]) -> dict[int, str]:
        """Return the titles of these games, without reading every game.

        Args:
            game_ids: Game IDs (e.g. of recent unlocks; repeats are fine).

        Returns:
            Game ID to title, for the games in the list.
        """
        query = "SELECT game_id, title FROM games WHERE"
        rows = select_among(self._db, query, set(game_ids), column="game_id")
        return {row[0]: row[1] for row in rows}

    def game(self, game_id: int) -> GameProgress | None:
        """Return one game.

        Args:
            game_id: RA game ID.

        Returns:
            The game, or ``None`` if unknown.
        """
        row = self._db.execute(
            f"SELECT {GAME_COLUMNS} FROM games WHERE game_id = ?",  # noqa: S608
            (game_id,),
        ).fetchone()
        return None if row is None else game_from_row(row)

    def detail_state(self, game_id: int) -> tuple[str | None, int | None]:
        """Return the fingerprint and time of a game's last detail fetch.

        Args:
            game_id: RA game ID.

        Returns:
            ``(fingerprint, synced_at)``; both ``None`` if never fetched or unknown.
        """
        row = self._db.execute(
            "SELECT detail_fingerprint, detail_synced_at FROM games WHERE game_id = ?",
            (game_id,),
        ).fetchone()
        return (None, None) if row is None else (row[0], row[1])

    def detail_states(self) -> dict[int, tuple[str | None, int | None]]:
        """Return ``(fingerprint, synced_at)`` of the last detail fetch for every game."""
        rows = self._db.execute(
            "SELECT game_id, detail_fingerprint, detail_synced_at FROM games"
        ).fetchall()
        return {row[0]: (row[1], row[2]) for row in rows}

    # --- game detail ------------------------------------------------------------------------

    def save_game_detail(self, detail: GameDetail, *, fingerprint: str, synced_at: int) -> None:
        """Replace a game's achievements and statistics in one transaction.

        Creates a minimal game row first if the game is not in the list yet.

        Args:
            detail: The game's detail from RA.
            fingerprint: The game's :attr:`GameProgress.fingerprint` at fetch time.
            synced_at: When it was fetched.
        """
        game_id = detail.game_id
        insert = (
            f"INSERT INTO achievements ({ACHIEVEMENT_COLUMNS}, unlocked_at) "  # noqa: S608
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )
        with self._db:
            exists = self._db.execute("SELECT 1 FROM games WHERE game_id = ?", (game_id,))
            if exists.fetchone() is None:
                self._db.execute(UPSERT_GAME, game_row(game_from_detail(detail)))
            self._db.execute("DELETE FROM achievements WHERE game_id = ?", (game_id,))
            self._db.executemany(insert, [achievement_row(a) for a in detail.achievements])
            stats = (detail.num_distinct_players, detail.num_players_casual)
            self._db.execute(
                "INSERT OR REPLACE INTO game_stats (game_id, num_distinct_players, "
                "num_players_casual, num_players_hc) VALUES (?, ?, ?, ?)",
                (game_id, *stats, detail.num_players_hardcore),
            )
            self._db.execute(
                "UPDATE games SET detail_fingerprint = ?, detail_synced_at = ? WHERE game_id = ?",
                (fingerprint, synced_at, game_id),
            )

    def game_detail(self, game_id: int) -> GameDetail | None:
        """Return a game's stored detail.

        Args:
            game_id: RA game ID.

        Returns:
            The detail, or ``None`` if it has never been fetched.
        """
        game = self._db.execute(
            "SELECT g.title, g.console_name, g.image_icon, s.num_distinct_players, "
            "s.num_players_casual, s.num_players_hc FROM games g "
            "JOIN game_stats s ON s.game_id = g.game_id "
            "WHERE g.game_id = ? AND g.detail_synced_at IS NOT NULL",
            (game_id,),
        ).fetchone()
        if game is None:
            return None
        rows = self._db.execute(
            f"SELECT {ACHIEVEMENT_COLUMNS} FROM achievements WHERE game_id = ? "  # noqa: S608
            "ORDER BY display_order, achievement_id",
            (game_id,),
        ).fetchall()
        return GameDetail(
            game_id=game_id,
            title=game["title"],
            console_name=game["console_name"],
            image_icon=game["image_icon"],
            num_distinct_players=game["num_distinct_players"],
            num_players_casual=game["num_players_casual"],
            num_players_hardcore=game["num_players_hc"],
            achievements=tuple(achievement_from_row(row) for row in rows),
        )

    def recent_unlocks(self, limit: int) -> list[Achievement]:
        """Return the most recently unlocked achievements across all games.

        Args:
            limit: Maximum number of achievements.

        Returns:
            Achievements unlocked in any mode, newest first.
        """
        rows = self._db.execute(
            f"SELECT {ACHIEVEMENT_COLUMNS} FROM achievements "  # noqa: S608
            "WHERE unlocked_at IS NOT NULL ORDER BY unlocked_at DESC, achievement_id DESC "
            "LIMIT ?",
            (limit,),
        ).fetchall()
        return [achievement_from_row(row) for row in rows]

    def nth_newest_unlock(self, n: int) -> int | None:
        """Return when the ``n``-th newest cached unlock happened (any mode).

        Args:
            n: Rank, 1 for the newest.

        Returns:
            The time, or ``None`` when fewer than ``n`` unlocks are cached.
        """
        row = self._db.execute(
            "SELECT unlocked_at FROM achievements WHERE unlocked_at IS NOT NULL "
            "ORDER BY unlocked_at DESC LIMIT 1 OFFSET ?",
            (max(n - 1, 0),),
        ).fetchone()
        return None if row is None else row[0]

    # --- awards -----------------------------------------------------------------------------

    def save_awards(self, counts: AwardCounts, awards: list[Award]) -> None:
        """Replace the stored awards and award counters.

        Args:
            counts: Counters from RA.
            awards: Visible game awards from RA.
        """
        insert = (
            f"INSERT OR REPLACE INTO awards ({AWARD_COLUMNS}) "  # noqa: S608
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        )
        with self._db:
            self._db.execute("DELETE FROM awards")
            self._db.executemany(insert, [award_row(award) for award in awards])
            self._db.execute(
                "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
                (_AWARD_COUNTS_KEY, json.dumps(dataclasses.asdict(counts))),
            )

    def award_counts(self) -> AwardCounts | None:
        """Return RA's award counters, without reading the awards (home summary).

        Returns:
            The counters, or ``None`` if awards were never synced.
        """
        raw = self.get_meta(_AWARD_COUNTS_KEY)
        if raw is None:
            return None
        try:
            return AwardCounts(**json.loads(raw))
        except (TypeError, ValueError):
            logger.warning("Stored award counts are unreadable; ignoring them")
            return None

    def awards(self, kind: AwardKind | None = None) -> tuple[AwardCounts | None, list[Award]]:
        """Return the award counters and awards, newest award first.

        Args:
            kind: Only awards of this kind. Reading 3,904 awards takes 0.27 s on a Miyoo
                Mini+, so the profile reads only the ones its stats use.

        Returns:
            ``(counts, awards)``; counts is ``None`` if awards were never synced.
        """
        counts = self.award_counts()
        where, params = ("WHERE kind = ? ", (kind.value,)) if kind else ("", ())
        rows = self._db.execute(
            f"SELECT {AWARD_COLUMNS} FROM awards {where}"  # noqa: S608 — only "?" marks
            "ORDER BY COALESCE(awarded_at, 0) DESC, title COLLATE NOCASE",
            params,
        ).fetchall()
        return counts, [award_from_row(row) for row in rows]

    def unlocked_among(self, achievement_ids: Iterable[int]) -> set[int]:
        """Return which of these achievements the cache knows as unlocked.

        Args:
            achievement_ids: Achievement IDs (e.g. RAOfflineProxy's queue).

        Returns:
            The unlocked ones.
        """
        query = "SELECT achievement_id FROM achievements WHERE unlocked_at IS NOT NULL AND"
        rows = select_among(self._db, query, achievement_ids, column="achievement_id")
        return {row[0] for row in rows}

    def achievement_games(self, achievement_ids: Iterable[int]) -> dict[int, int]:
        """Return the game of each of these achievements, for those in synced games.

        Args:
            achievement_ids: Achievement IDs (e.g. RAOfflineProxy's queue).

        Returns:
            Achievement ID to game ID.
        """
        query = "SELECT achievement_id, game_id FROM achievements WHERE"
        rows = select_among(self._db, query, achievement_ids, column="achievement_id")
        return {row[0]: row[1] for row in rows}

    # --- player statistics ------------------------------------------------------------------

    def save_first_hardcore_unlock(self, at: int) -> None:
        """Store when the first hardcore unlock happened (fetched once, with "See more").

        Args:
            at: Its time.
        """
        self.set_meta(FIRST_HARDCORE_UNLOCK_KEY, str(at))

    def first_hardcore_unlock(self) -> int | None:
        """Return when the first hardcore unlock happened (for points per week).

        The cache doesn't hold every game's achievements, so this comes from RA once (see
        :meth:`save_first_hardcore_unlock`), not from the cached unlocks.

        Returns:
            The time, or ``None`` until it has been fetched.
        """
        raw = self.get_meta(FIRST_HARDCORE_UNLOCK_KEY)
        try:
            return int(raw) if raw is not None else None
        except ValueError:
            return None

    def save_unlock_window(self, window: UnlockWindow) -> None:
        """Store the last fetched window of unlocks (points in the last 7/30 days).

        Args:
            window: The window and its unlocks.
        """
        payload = {
            "start": window.start,
            "end": window.end,
            "unlocks": [dataclasses.astuple(unlock) for unlock in window.unlocks],
        }
        self.set_meta(_UNLOCK_WINDOW_KEY, json.dumps(payload))

    def unlock_window(self) -> UnlockWindow | None:
        """Return the last fetched window of unlocks.

        Returns:
            The window, or ``None`` if never fetched (or unreadable).
        """
        raw = self.get_meta(_UNLOCK_WINDOW_KEY)
        if raw is None:
            return None
        try:
            data = json.loads(raw)
            unlocks = tuple(Unlock(*row) for row in data["unlocks"])
            return UnlockWindow(int(data["start"]), int(data["end"]), unlocks)
        except (TypeError, ValueError, KeyError):
            logger.warning("Stored unlock window is unreadable; ignoring it")
            return None
