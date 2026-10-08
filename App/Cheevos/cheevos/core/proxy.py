"""Read-only view of RAOfflineProxy's state (.agents/integration.md).

Never calls the proxy's CLI (it creates the proxy database as a side effect) and never writes:
the SQLite database is opened with ``mode=ro`` so a missing file stays missing. Any problem
(missing tables, a locked or malformed database) hides the offline features instead of raising.
"""

from __future__ import annotations

import json
import logging
import sqlite3
from collections.abc import Iterable
from dataclasses import dataclass

from cheevos.core.credentials import read_spruce_ra_setting
from cheevos.core.models import PendingAward
from cheevos.platform.paths import Paths

logger = logging.getLogger(__name__)

DATABASE_NAME = "proxy.sqlite3"
REQUIRED_COLUMNS: dict[str, frozenset[str]] = {
    "pending_awards": frozenset({"achievementId", "queuedAt", "status"}),
    "api_cache": frozenset({"cacheKey", "responseBody"}),
}
PENDING_STATUS = "pending"
PATCH_PREFIX = "patch:"


@dataclass(frozen=True, slots=True)
class _PatchInfo:
    """What the proxy's cached patch data tells us about one achievement.

    Attributes:
        game_id: RA game ID.
        game_title: Game title.
        achievement_title: Achievement title.
        points: Points, if present.
    """

    game_id: int
    game_title: str
    achievement_title: str
    points: int | None


def _patch_game_id(cache_key: str) -> int | None:
    """Return the game ID from a ``patch:<gameId>:<user>`` cache key.

    Args:
        cache_key: Cache key.

    Returns:
        The game ID, or ``None`` for other keys.
    """
    if not cache_key.startswith(PATCH_PREFIX):
        return None
    value = cache_key[len(PATCH_PREFIX) :].split(":", 1)[0]
    return int(value) if value.isdecimal() else None  # isdigit() takes "²", which int() refuses


def _patch_entries(game_id: int, body: str) -> dict[int, _PatchInfo]:
    """Index the achievements of one cached ``r=patch`` response.

    Args:
        game_id: Game ID from the cache key.
        body: The cached response body.

    Returns:
        Achievement ID to patch info; empty for unparsable bodies.
    """
    try:
        patch = json.loads(body).get("PatchData")
    except (json.JSONDecodeError, AttributeError):
        return {}
    if not isinstance(patch, dict):
        return {}
    title = patch.get("Title") or f"Game {game_id}"
    achievements = patch.get("Achievements")
    if isinstance(achievements, dict):  # the proxy accepts both shapes
        achievements = list(achievements.values())
    if not isinstance(achievements, list):
        return {}
    entries: dict[int, _PatchInfo] = {}
    for achievement in achievements:
        achievement_id = achievement.get("ID") if isinstance(achievement, dict) else None
        if not isinstance(achievement_id, int):
            continue
        points = achievement.get("Points")
        entries[achievement_id] = _PatchInfo(
            game_id=game_id,
            game_title=str(title),
            achievement_title=str(achievement.get("Title") or f"Achievement {achievement_id}"),
            points=points if isinstance(points, int) else None,
        )
    return entries


def _queued_seconds(raw: object) -> int | None:
    """Convert the proxy's ``queuedAt`` (milliseconds) to epoch seconds.

    Args:
        raw: Column value.

    Returns:
        Epoch seconds, or ``None`` when missing or not a positive number.
    """
    return int(raw) // 1000 if isinstance(raw, int) and raw > 0 else None


class ProxyReader:
    """Read-only access to RAOfflineProxy's files.

    Args:
        paths: Resolved paths.
    """

    def __init__(self, paths: Paths) -> None:
        self._paths = paths
        self._warned: set[str] = set()

    def _warn_once(self, reason: str, *args: object) -> None:
        """Log a warning the first time a given problem is seen.

        Args:
            reason: %-style message; also the de-duplication key.
            *args: Message arguments.
        """
        if reason not in self._warned:
            self._warned.add(reason)
            logger.warning(reason, *args)

    def installed(self) -> bool:
        """Report whether the RAOfflineProxy app is installed."""
        return self._paths.proxy_data_dir.parent.is_dir()

    def enabled(self) -> bool:
        """Report whether "Offline Achievements" is switched on in Spruce's settings."""
        return read_spruce_ra_setting(self._paths, "enableOfflineProxy") == "True"

    def online(self) -> bool | None:
        """Return the proxy's last connectivity verdict.

        Returns:
            ``True``/``False`` from ``online_state.json``, or ``None`` when unknown.
        """
        path = self._paths.proxy_data_dir / "online_state.json"
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            return None
        return bool(data.get("online")) if isinstance(data, dict) else None

    def cached_game_ids(self) -> set[int]:
        """Return the game IDs the proxy has cached for offline play.

        Returns:
            IDs from ``cached_game_ids.txt``; junk lines are skipped.
        """
        path = self._paths.proxy_data_dir / "cached_game_ids.txt"
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return set()
        return {int(line.strip()) for line in lines if line.strip().isdecimal()}

    def pending_awards(self, username: str) -> list[PendingAward]:
        """Return unlocks queued for submission, oldest first.

        Args:
            username: RA username, used to prefer this account's cached patch data.

        Returns:
            Pending awards; empty when the proxy has no database or it can't be read.
        """
        database = self._paths.proxy_data_dir / DATABASE_NAME
        if not database.is_file():
            return []
        try:
            uri = database.resolve().as_uri() + "?mode=ro"  # mode=ro never creates files
            connection = sqlite3.connect(uri, uri=True, timeout=1.0)
        except sqlite3.Error as exc:
            self._warn_once("Cannot open RAOfflineProxy database: %s", exc)
            return []
        try:
            return self._read_pending(connection, username)
        except sqlite3.Error as exc:
            self._warn_once("Cannot read RAOfflineProxy database: %s", exc)
            return []
        except Exception as exc:  # noqa: BLE001 — data from a proxy version we don't know
            self._warn_once("Unexpected RAOfflineProxy data; hiding its queue: %r", exc)
            return []
        finally:
            connection.close()

    def _read_pending(self, connection: sqlite3.Connection, username: str) -> list[PendingAward]:
        """Query pending awards and decorate them with cached patch data.

        Args:
            connection: Read-only connection.
            username: RA username.

        Returns:
            Pending awards, oldest first.
        """
        if not self._schema_ok(connection):
            return []
        rows = connection.execute(
            "SELECT achievementId, queuedAt, status FROM pending_awards "
            "ORDER BY queuedAt ASC, id ASC"
        ).fetchall()
        pending = [
            (achievement_id, queued_at)
            for achievement_id, queued_at, status in rows
            if (status or PENDING_STATUS) == PENDING_STATUS and isinstance(achievement_id, int)
        ]
        if not pending:
            return []
        patches = self._patch_index(connection, username)
        return [self._award(aid, queued, patches.get(aid)) for aid, queued in pending]

    def _schema_ok(self, connection: sqlite3.Connection) -> bool:
        """Check that the tables and columns we read exist.

        Args:
            connection: Read-only connection.

        Returns:
            ``True`` when the schema matches what this reader understands.
        """
        for table, required in REQUIRED_COLUMNS.items():
            columns = {row[1] for row in connection.execute(f"PRAGMA table_info({table})")}
            if not required <= columns:
                self._warn_once(
                    "RAOfflineProxy schema changed (%s lacks %s); hiding offline data",
                    table,
                    ", ".join(sorted(required - columns)),
                )
                return False
        return True

    @staticmethod
    def _patch_index(connection: sqlite3.Connection, username: str) -> dict[int, _PatchInfo]:
        """Index cached patch data by achievement, preferring this account's entries.

        Patch data is the same for every account, so other accounts' entries fill gaps.

        Args:
            connection: Read-only connection.
            username: RA username.

        Returns:
            Achievement ID to patch info.
        """
        rows: Iterable[tuple[str, str]] = connection.execute(
            "SELECT cacheKey, responseBody FROM api_cache WHERE cacheKey LIKE 'patch:%'"
        ).fetchall()
        suffix = ":" + username.strip().lower()
        own: dict[int, _PatchInfo] = {}
        other: dict[int, _PatchInfo] = {}
        for cache_key, body in rows:
            game_id = _patch_game_id(cache_key)
            if game_id is None or not isinstance(body, str):
                continue
            target = own if cache_key.endswith(suffix) else other
            target.update(_patch_entries(game_id, body))
        return {**other, **own}

    @staticmethod
    def _award(achievement_id: int, queued_at: object, info: _PatchInfo | None) -> PendingAward:
        """Build a pending award from a queue row and optional patch info.

        Args:
            achievement_id: RA achievement ID.
            queued_at: ``queuedAt`` column (milliseconds).
            info: Cached patch data for the achievement, if any.

        Returns:
            The pending award.
        """
        return PendingAward(
            achievement_id=achievement_id,
            game_id=info.game_id if info else None,
            game_title=info.game_title if info else "",
            achievement_title=info.achievement_title if info else "",
            points=info.points if info else None,
            queued_at=_queued_seconds(queued_at),
        )
