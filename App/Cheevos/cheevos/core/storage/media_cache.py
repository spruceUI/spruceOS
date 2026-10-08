"""The image cache (``Saves/cheevos/cache/media.db``) and its RAM scratch directory.

Badges, game icons and avatars are stored as SQLite blobs: on the SD card's FAT32 (32 KB
clusters, mounted ``dirsync``), 200 badges as files took 0.70 s and 6.3 MB of disk on a Miyoo
Mini, as blobs 0.12 s and 832 KB. PyUI loads images by path, so :meth:`MediaCache.path_for`
extracts the blobs a screen needs into a scratch directory (``/tmp/cheevos/media`` on devices,
RAM-backed) and keeps it under a size limit by evicting the least recently used files.

The database is a disposable cache (.agents/sync-and-storage.md). Use a :class:`MediaCache` only
on the thread that opened it.
"""

from __future__ import annotations

import logging
import re
import sqlite3
from collections import OrderedDict
from collections.abc import Callable, Iterable
from pathlib import Path

from cheevos.core.clock import network_clock
from cheevos.core.storage.db import open_cache, reset_cache, select_among

logger = logging.getLogger(__name__)

SCHEMA_VERSION = 1
DDL = """
CREATE TABLE media (
    key TEXT PRIMARY KEY,
    data BLOB NOT NULL,
    size INTEGER NOT NULL,
    stored_at INTEGER NOT NULL
);
"""
DEFAULT_SCRATCH_LIMIT = 4 * 1024 * 1024
PAGE = 4096  # tmpfs stores files in whole pages: a 3 KB badge takes 4 KB of RAM
_UNSAFE_NAME_CHARS = re.compile(r"[^A-Za-z0-9._-]")
_EXTENSION = ".png"


def badge_key(badge_name: str, *, locked: bool) -> str:
    """Return the cache key of a badge image.

    Args:
        badge_name: RA badge name, e.g. ``"198102"``.
        locked: The greyed-out ``_lock`` variant shown for locked achievements.

    Returns:
        E.g. ``"badge/198102_lock"``.
    """
    return f"badge/{badge_name}{'_lock' if locked else ''}"


def icon_key(game_id: int) -> str:
    """Return the cache key of a game icon.

    Args:
        game_id: RA game ID.

    Returns:
        E.g. ``"icon/519"``.
    """
    return f"icon/{game_id}"


def avatar_key(username: str) -> str:
    """Return the cache key of a user avatar (usernames are case-insensitive).

    Args:
        username: RA username.

    Returns:
        E.g. ``"avatar/balah"``.
    """
    return f"avatar/{username.casefold()}"


def in_pages(size: int) -> int:
    """Return the memory a file of ``size`` bytes takes in the RAM scratch (whole pages).

    Args:
        size: File size in bytes.

    Returns:
        The size rounded up to :data:`PAGE`.
    """
    return -(-size // PAGE) * PAGE


def scratch_name(key: str) -> str:
    """Turn a cache key into a safe file name for the scratch directory.

    Args:
        key: Cache key, e.g. ``"badge/198102_lock"``.

    Returns:
        E.g. ``"badge__198102_lock.png"``.
    """
    return _UNSAFE_NAME_CHARS.sub("_", key.replace("/", "__")) + _EXTENSION


class MediaCache:
    """Image blobs in SQLite, extracted on demand to a size-limited scratch directory.

    Args:
        db_path: Database file.
        connection: Open connection to it (schema already verified).
        scratch_dir: Directory for extracted images.
        scratch_limit_bytes: Target maximum size of the scratch directory.
        clock: Returns the current time as epoch seconds.
    """

    def __init__(
        self,
        db_path: Path,
        connection: sqlite3.Connection,
        scratch_dir: Path,
        scratch_limit_bytes: int,
        clock: Callable[[], float],
    ) -> None:
        self._db_path = db_path
        self._db = connection
        self._scratch = scratch_dir
        self._limit = scratch_limit_bytes
        self._clock = clock
        self._lru: OrderedDict[str, int] = OrderedDict()
        self._seed_lru()

    @classmethod
    def open(
        cls,
        db_path: Path,
        scratch_dir: Path,
        *,
        scratch_limit_bytes: int = DEFAULT_SCRATCH_LIMIT,
        clock: Callable[[], float] = network_clock.now,
    ) -> MediaCache:
        """Open (or create) the image cache.

        Args:
            db_path: Database file.
            scratch_dir: Directory for extracted images (created when needed).
            scratch_limit_bytes: Target maximum size of the scratch directory.
            clock: Returns the current time as epoch seconds.

        Returns:
            The cache.
        """
        connection = open_cache(db_path, schema_version=SCHEMA_VERSION, ddl=DDL)
        return cls(db_path, connection, scratch_dir, scratch_limit_bytes, clock)

    def close(self) -> None:
        """Close the connection (extracted files stay in the scratch directory)."""
        self._db.close()

    def _seed_lru(self) -> None:
        """Track images extracted by an earlier run, oldest first by modification time."""
        if not self._scratch.is_dir():
            return
        files = [path for path in self._scratch.iterdir() if path.suffix == _EXTENSION]
        for path in sorted(files, key=lambda path: path.stat().st_mtime):
            self._lru[path.name] = in_pages(path.stat().st_size)

    # --- blobs ------------------------------------------------------------------------------

    def has(self, key: str) -> bool:
        """Report whether an image is cached.

        Args:
            key: Cache key.

        Returns:
            ``True`` if the blob is stored.
        """
        row = self._db.execute("SELECT 1 FROM media WHERE key = ?", (key,)).fetchone()
        return row is not None

    def missing(self, keys: Iterable[str]) -> list[str]:
        """Return the keys that are not cached, in input order, without duplicates.

        Args:
            keys: Cache keys to check.

        Returns:
            Keys to download.
        """
        wanted = list(dict.fromkeys(keys))
        rows = select_among(self._db, "SELECT key FROM media WHERE", wanted, column="key")
        found = {row[0] for row in rows}
        return [key for key in wanted if key not in found]

    def put(self, key: str, data: bytes) -> None:
        """Store one image, replacing any previous version.

        Args:
            key: Cache key.
            data: Image bytes.
        """
        self.put_many([(key, data)])

    def put_many(self, items: Iterable[tuple[str, bytes]]) -> None:
        """Store several images in one transaction, replacing previous versions.

        Args:
            items: ``(key, data)`` pairs.
        """
        now = int(self._clock())
        rows = [(key, sqlite3.Binary(data), len(data), now) for key, data in items]
        with self._db:
            self._db.executemany(
                "INSERT OR REPLACE INTO media (key, data, size, stored_at) VALUES (?, ?, ?, ?)",
                rows,
            )
        for key, *_ in rows:
            self._forget(scratch_name(key))

    def size_bytes(self) -> int:
        """Return the space the cache takes on the card: the database file's size, or 0 if empty.

        Not ``SUM(size)``: each ``size`` is stored after its blob, so the sum reads the whole
        file (2.4 s for 48 MB on a Miyoo Mini+), while ``stat`` takes 0.1 ms
        (.agents/sync-and-storage.md).
        """
        if self._db.execute("SELECT 1 FROM media LIMIT 1").fetchone() is None:
            return 0  # the empty schema's 12 KB isn't worth showing
        return self._db_path.stat().st_size

    def clear(self) -> None:
        """Delete every cached image and extracted file, shrinking the database file."""
        self._db.close()
        self._db = reset_cache(self._db_path, schema_version=SCHEMA_VERSION, ddl=DDL)
        for name in list(self._lru):
            self._forget(name)
        logger.info("Image cache cleared")

    # --- scratch files ----------------------------------------------------------------------

    def path_for(self, key: str) -> Path | None:
        """Return a file path for an image, extracting it to the scratch directory if needed.

        Args:
            key: Cache key.

        Returns:
            The extracted file, or ``None`` if the image is not cached.
        """
        name = scratch_name(key)
        path = self._scratch / name
        if not self._scratch.is_dir():
            self._lru.clear()  # removed externally (e.g. /tmp wiped); start over
        elif name in self._lru and path.exists():
            self._lru.move_to_end(name)
            return path
        row = self._db.execute("SELECT data FROM media WHERE key = ?", (key,)).fetchone()
        if row is None:
            return None
        data = bytes(row[0])
        self._scratch.mkdir(parents=True, exist_ok=True)
        partial = path.with_name(path.name + ".part")
        partial.write_bytes(data)
        partial.replace(path)
        self._lru[name] = in_pages(len(data))
        self._lru.move_to_end(name)
        self._evict(keep=name)
        return path

    def _forget(self, name: str) -> None:
        """Delete an extracted file and stop tracking it.

        Args:
            name: Scratch file name.
        """
        self._lru.pop(name, None)
        (self._scratch / name).unlink(missing_ok=True)

    def _evict(self, *, keep: str) -> None:
        """Delete least recently used files until the scratch directory fits the limit.

        Args:
            keep: File that must survive (the one about to be returned).
        """
        total = sum(self._lru.values())
        for name in list(self._lru):
            if total <= self._limit:
                return
            if name == keep:
                continue
            total -= self._lru[name]
            self._forget(name)
