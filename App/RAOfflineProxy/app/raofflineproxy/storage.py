from __future__ import annotations

import contextlib
import importlib
import json
import logging
import os
import sys
import threading
import time
from collections.abc import Iterator
from pathlib import Path
from typing import Any

from . import cache_keys, es_export, game_meta, storage_corruption
from .config import DATABASE_FILE, ensure_config_dir

try:
    import fcntl
except ModuleNotFoundError:
    fcntl = None

LOGGER = logging.getLogger("raofflineproxy")
GAME_META_INDEX_BATCH = 50
INSERT_GAME_META = (
    "INSERT OR REPLACE INTO cached_game_meta(cacheKey, gameId, title, imagePath) VALUES(?, ?, ?, ?)"
)

VENDORED_SQLITE_DIR = Path(__file__).resolve().parent.parent / "vendor" / "sqlite"


def _import_sqlite3(module_name: str = "sqlite3"):
    """The firmware's own sqlite3 wins. Some (KNULLI) ship a Python without it, so the bundle
    carries one as a last resort, appended after the standard library so it never shadows a
    working one."""
    try:
        return importlib.import_module(module_name)
    except ImportError:
        pass
    if not VENDORED_SQLITE_DIR.is_dir():
        return None
    sys.path.append(str(VENDORED_SQLITE_DIR))
    try:
        return importlib.import_module(module_name)
    except ImportError as exc:
        sys.path.remove(str(VENDORED_SQLITE_DIR))
        logging.getLogger("raofflineproxy").warning("Bundled sqlite3 does not load: %s", exc)
        return None


sqlite3 = _import_sqlite3()

JSON_STORE_FILE = DATABASE_FILE.with_suffix(".json")

PENDING_AWARD_STATUS_PENDING = "pending"
PENDING_AWARD_STATUS_DELETED = "deleted"
PENDING_AWARD_STATUS_STALE = "stale"
PENDING_AWARD_STATUS_FLUSHED = "flushed"
WARNING_ACHIEVEMENT_ID = 101000001


_EVICTION_EXEMPT_PREFIXES = (
    cache_keys.PREFIX_LOGIN,
    cache_keys.PREFIX_PATCH,
    cache_keys.PREFIX_ACHIEVEMENTSETS,
    cache_keys.PREFIX_UNLOCKS,
    cache_keys.PREFIX_STARTSESSION,
    cache_keys.PREFIX_GAMEID,
    cache_keys.PREFIX_CACHE_QUEUE,
    cache_keys.PREFIX_WATCH_SEEN,
)

class Storage:
    def __init__(self, database_path: Path = DATABASE_FILE):
        ensure_config_dir()
        self._database_path = database_path
        self._lock = threading.RLock()
        self._use_sqlite = sqlite3 is not None
        self._json_path = database_path.with_suffix(".json")
        self._json_lock_path = self._json_path.with_suffix(
            f"{self._json_path.suffix}.lock"
        )
        self._json_state: dict[str, Any] | None = None
        self._connection = None

        if self._use_sqlite:
            self._connection = sqlite3.connect(
                self._database_path, check_same_thread=False, timeout=5.0
            )
            self._connection.row_factory = sqlite3.Row
            self._initialize_sqlite()
            self._index_missing_game_meta()
            self._import_legacy_json()
        else:
            self._initialize_json()

    @property
    def backend(self) -> str:
        return "sqlite" if self._use_sqlite else "json"

    def close(self) -> None:
        with self._lock:
            if self._connection is not None:
                self._connection.close()

    def _initialize_sqlite(self) -> None:
        assert self._connection is not None
        with self._lock:
            try:
                self._connection.execute("PRAGMA journal_mode=WAL;").fetchone()
            except sqlite3.OperationalError:
                # WAL requires shared-memory/locking semantics that FAT32
                # (e.g. Miyoo Mini / Onion SD cards) doesn't provide.
                self._connection.execute("PRAGMA journal_mode=DELETE;")
            self._connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS api_cache (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    cacheKey TEXT NOT NULL UNIQUE,
                    responseBody TEXT NOT NULL,
                    sourceRomPath TEXT,
                    cachedAt INTEGER NOT NULL,
                    firstCachedAt INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS pending_awards (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    achievementId INTEGER NOT NULL UNIQUE,
                    queryString TEXT NOT NULL,
                    requestBody TEXT NOT NULL,
                    userAgent TEXT NOT NULL,
                    queuedAt INTEGER NOT NULL,
                    retryCount INTEGER NOT NULL DEFAULT 0,
                    lastError TEXT,
                    status TEXT NOT NULL DEFAULT 'pending',
                    payloadHash TEXT NOT NULL DEFAULT '',
                    prevHash TEXT NOT NULL DEFAULT '',
                    signature TEXT NOT NULL DEFAULT '',
                    signedAt INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS cached_game_meta (
                    cacheKey TEXT PRIMARY KEY,
                    gameId INTEGER,
                    title TEXT,
                    imagePath TEXT
                );
                CREATE INDEX IF NOT EXISTS cached_game_meta_game_id ON cached_game_meta(gameId);
                CREATE TRIGGER IF NOT EXISTS cached_game_meta_delete AFTER DELETE ON api_cache
                BEGIN
                    DELETE FROM cached_game_meta WHERE cacheKey = old.cacheKey;
                END;
                CREATE TRIGGER IF NOT EXISTS cached_game_meta_rename AFTER UPDATE OF cacheKey ON api_cache
                BEGIN
                    UPDATE cached_game_meta SET cacheKey = new.cacheKey WHERE cacheKey = old.cacheKey;
                END;
                """
            )
            cache_columns = {
                row["name"]
                for row in self._connection.execute(
                    "PRAGMA table_info(api_cache)"
                ).fetchall()
            }
            if "sourceRomPath" not in cache_columns:
                self._connection.execute(
                    "ALTER TABLE api_cache ADD COLUMN sourceRomPath TEXT"
                )

            columns = {
                row["name"]
                for row in self._connection.execute(
                    "PRAGMA table_info(pending_awards)"
                ).fetchall()
            }
            if "status" not in columns:
                self._connection.execute(
                    "ALTER TABLE pending_awards ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'"
                )
            self._connection.commit()

    def _import_legacy_json(self) -> None:
        """Takes over the JSON store a device used while it had no sqlite3, once. Each write to
        that store rewrote the whole file, so it also gets slower with every cached game.
        Cached games and pending awards are copied in one transaction, the counts are checked,
        and only then is the file renamed (kept as a backup, never deleted)."""
        if not self._json_path.exists():
            return
        assert self._connection is not None
        with self._lock:
            with self._json_file_lock(exclusive=True):
                if not self._json_path.exists():
                    return
                try:
                    with self._json_path.open(encoding="utf-8") as handle:
                        data = json.load(handle)
                    if not isinstance(data, dict):
                        raise ValueError(f"Invalid JSON storage file: {self._json_path}")
                except OSError as exc:
                    LOGGER.error("Cannot read %s for the sqlite import: %s", self._json_path, exc)
                    return
                except ValueError as exc:
                    LOGGER.error("Storage file %s is corrupt (%s)", self._json_path, exc)
                    self._quarantine_corrupt_json_unlocked(str(exc))
                    return

                entries = [
                    item
                    for item in data.get("api_cache", [])
                    if isinstance(item, dict) and item.get("cacheKey") is not None
                ]
                awards = [
                    item
                    for item in data.get("pending_awards", [])
                    if isinstance(item, dict) and item.get("achievementId") is not None
                ]
                try:
                    with self._connection:
                        self._connection.executemany(
                            """
                            INSERT OR IGNORE INTO api_cache(
                                cacheKey, responseBody, sourceRomPath, cachedAt, firstCachedAt
                            ) VALUES(?, ?, ?, ?, ?)
                            """,
                            [
                                (
                                    item["cacheKey"],
                                    item.get("responseBody") or "",
                                    item.get("sourceRomPath"),
                                    int(item.get("cachedAt") or 0),
                                    int(item.get("firstCachedAt") or item.get("cachedAt") or 0),
                                )
                                for item in entries
                            ],
                        )
                        self._connection.executemany(
                            """
                            INSERT OR IGNORE INTO pending_awards(
                                achievementId, queryString, requestBody, userAgent, queuedAt,
                                retryCount, lastError, status, payloadHash, prevHash,
                                signature, signedAt
                            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            [
                                (
                                    item["achievementId"],
                                    item.get("queryString") or "",
                                    item.get("requestBody") or "",
                                    item.get("userAgent") or "",
                                    int(item.get("queuedAt") or 0),
                                    int(item.get("retryCount") or 0),
                                    item.get("lastError"),
                                    item.get("status") or PENDING_AWARD_STATUS_PENDING,
                                    item.get("payloadHash") or "",
                                    item.get("prevHash") or "",
                                    item.get("signature") or "",
                                    int(item.get("signedAt") or 0),
                                )
                                for item in awards
                            ],
                        )
                        cached = self._connection.execute("SELECT COUNT(*) FROM api_cache").fetchone()[0]
                        pending = self._connection.execute("SELECT COUNT(*) FROM pending_awards").fetchone()[0]
                        if cached < len({item["cacheKey"] for item in entries}) or pending < len(
                            {item["achievementId"] for item in awards}
                        ):
                            raise sqlite3.DatabaseError("sqlite import is missing rows")
                except sqlite3.Error as exc:
                    LOGGER.error("Importing %s into sqlite failed, keeping it: %s", self._json_path, exc)
                    return

                backup = self._json_path.with_name(f"{self._json_path.name}.migrated-{current_millis()}")
                try:
                    self._json_path.replace(backup)
                except OSError as exc:
                    LOGGER.error("Imported %s but could not rename it: %s", self._json_path, exc)
                    return
                LOGGER.info(
                    "Imported %d cache entries and %d pending awards from %s into sqlite",
                    len(entries),
                    len(awards),
                    self._json_path.name,
                )
        self._index_missing_game_meta()
        es_export.export_cached_game_ids(self)

    def _index_missing_game_meta(self) -> None:
        """Indexes entries written before cached_game_meta existed, by the JSON import, or by an
        older version after a downgrade (its deletes and renames still reach the table through
        the triggers). A library of 1000 games takes about half a minute, once."""
        assert self._connection is not None
        with self._lock:
            row_ids = [
                int(row[0])
                for row in self._connection.execute(
                    """
                    SELECT id FROM api_cache
                    WHERE (cacheKey LIKE 'patch:%' OR cacheKey LIKE 'achievementsets:%')
                      AND cacheKey NOT IN (SELECT cacheKey FROM cached_game_meta)
                    """
                ).fetchall()
            ]
        if not row_ids:
            return
        LOGGER.info("Indexing %d cached game entries", len(row_ids))
        for start in range(0, len(row_ids), GAME_META_INDEX_BATCH):
            meta_rows = []
            for row_id in row_ids[start:start + GAME_META_INDEX_BATCH]:
                with self._lock:
                    row = self._connection.execute(
                        "SELECT cacheKey, responseBody FROM api_cache WHERE id = ?", (row_id,)
                    ).fetchone()
                if row is not None:
                    meta_rows.append(game_meta_row(row["cacheKey"], row["responseBody"]))
            with self._lock:
                self._connection.executemany(INSERT_GAME_META, meta_rows)
                self._connection.commit()

    def _initialize_json(self) -> None:
        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                if not self._json_path.exists():
                    self._write_json_state_unlocked()

    @contextlib.contextmanager
    def _json_file_lock(self, exclusive: bool):
        ensure_config_dir()
        self._json_lock_path.parent.mkdir(parents=True, exist_ok=True)
        with self._json_lock_path.open("a+") as handle:
            if fcntl is not None:
                mode = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
                fcntl.flock(handle.fileno(), mode)
            try:
                yield
            finally:
                if fcntl is not None:
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

    def _reload_json_state_unlocked(self) -> None:
        if self._json_path.exists():
            try:
                with self._json_path.open(encoding="utf-8") as handle:
                    data = json.load(handle)
                if not isinstance(data, dict):
                    raise ValueError(f"Invalid JSON storage file: {self._json_path}")
            except (json.JSONDecodeError, ValueError) as exc:
                LOGGER.error(
                    "Storage file %s is corrupt (%s); resetting to empty state",
                    self._json_path,
                    exc,
                )
                self._quarantine_corrupt_json_unlocked(str(exc))
                data = {"api_cache": [], "pending_awards": []}
            self._json_state = data
        else:
            self._json_state = {"api_cache": [], "pending_awards": []}

        self._json_state.setdefault("api_cache", [])
        self._json_state.setdefault("pending_awards", [])

    def _quarantine_corrupt_json_unlocked(self, reason: str) -> None:
        quarantine_path = self._json_path.with_name(
            f"{self._json_path.name}.corrupt-{current_millis()}"
        )
        try:
            size_bytes = self._json_path.stat().st_size
            self._json_path.replace(quarantine_path)
        except OSError as exc:
            LOGGER.error(
                "Failed to quarantine corrupt storage file %s: %s",
                self._json_path,
                exc,
            )
            return
        lost_pending_awards = _salvage_pending_award_count(quarantine_path)
        storage_corruption.record_incident(
            quarantine_path, reason, size_bytes, lost_pending_awards
        )

    def _write_json_state_unlocked(self) -> None:
        assert self._json_state is not None
        temp_path = self._json_path.with_suffix(
            f"{self._json_path.suffix}.tmp.{os.getpid()}"
        )
        with temp_path.open("w", encoding="utf-8") as handle:
            json.dump(self._json_state, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        temp_path.replace(self._json_path)
        self._fsync_dir_best_effort(self._json_path.parent)

    @staticmethod
    def _fsync_dir_best_effort(directory: Path) -> None:
        try:
            dir_fd = os.open(directory, os.O_RDONLY)
        except OSError:
            return
        try:
            os.fsync(dir_fd)
        except OSError:
            pass
        finally:
            os.close(dir_fd)

    def upsert_cache(
        self,
        cache_key: str,
        response_body: str,
        cached_at: int | None = None,
        source_rom_path: str | None = None,
    ) -> None:
        now = cached_at or current_millis()
        if self._use_sqlite:
            self._upsert_cache_sqlite(cache_key, response_body, source_rom_path, now)
        else:
            self._upsert_cache_json(cache_key, response_body, source_rom_path, now)
        if es_export.key_affects_cached_game_ids(cache_key):
            es_export.add_cached_game_id(self, cache_key, response_body)

    def _after_cache_mutation(self, *affected_keys: str | None) -> None:
        if any(es_export.key_affects_cached_game_ids(key) for key in affected_keys):
            es_export.export_cached_game_ids(self)

    def _upsert_cache_sqlite(
        self,
        cache_key: str,
        response_body: str,
        source_rom_path: str | None,
        now: int,
    ) -> None:
        assert self._connection is not None
        meta_row = (
            game_meta_row(cache_key, response_body)
            if cache_key.startswith(game_meta.GAME_META_PREFIXES)
            else None
        )
        with self._lock:
            row = self._connection.execute(
                "SELECT firstCachedAt, sourceRomPath FROM api_cache WHERE cacheKey = ? LIMIT 1",
                (cache_key,),
            ).fetchone()
            first_cached_at = int(row["firstCachedAt"]) if row is not None else now
            existing_source_rom_path = (
                str(row["sourceRomPath"])
                if row is not None and row["sourceRomPath"] is not None
                else None
            )
            self._connection.execute(
                """
                INSERT INTO api_cache(cacheKey, responseBody, sourceRomPath, cachedAt, firstCachedAt)
                VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(cacheKey) DO UPDATE SET
                    responseBody = excluded.responseBody,
                    sourceRomPath = COALESCE(excluded.sourceRomPath, api_cache.sourceRomPath),
                    cachedAt = excluded.cachedAt
                """,
                (
                    cache_key,
                    response_body,
                    source_rom_path or existing_source_rom_path,
                    now,
                    first_cached_at,
                ),
            )
            if meta_row is not None:
                self._connection.execute(INSERT_GAME_META, meta_row)
            self._connection.commit()

    def _upsert_cache_json(
        self,
        cache_key: str,
        response_body: str,
        source_rom_path: str | None,
        now: int,
    ) -> None:
        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                existing = next(
                    (
                        entry
                        for entry in self._json_state["api_cache"]
                        if entry["cacheKey"] == cache_key
                    ),
                    None,
                )
                if existing is None:
                    self._json_state["api_cache"].append(
                        {
                            "id": next_json_id(self._json_state["api_cache"]),
                            "cacheKey": cache_key,
                            "responseBody": response_body,
                            "sourceRomPath": source_rom_path,
                            "cachedAt": now,
                            "firstCachedAt": now,
                        }
                    )
                else:
                    existing["responseBody"] = response_body
                    if source_rom_path is not None:
                        existing["sourceRomPath"] = source_rom_path
                    existing["cachedAt"] = now
                self._write_json_state_unlocked()

    def get_cache(self, cache_key: str) -> dict | None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                row = self._connection.execute(
                    "SELECT * FROM api_cache WHERE cacheKey = ? LIMIT 1",
                    (cache_key,),
                ).fetchone()
            return row_to_dict(row)

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                entry = next(
                    (
                        item
                        for item in self._json_state["api_cache"]
                        if item["cacheKey"] == cache_key
                    ),
                    None,
                )
                return dict(entry) if entry is not None else None

    def get_cache_by_prefix(self, prefix: str) -> dict | None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                row = self._connection.execute(
                    "SELECT * FROM api_cache WHERE cacheKey LIKE ? LIMIT 1",
                    (f"{prefix}%",),
                ).fetchone()
            return row_to_dict(row)

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                entry = next(
                    (
                        item
                        for item in self._json_state["api_cache"]
                        if item["cacheKey"].startswith(prefix)
                    ),
                    None,
                )
                return dict(entry) if entry is not None else None

    def iter_cache_by_prefix(self, prefix: str) -> Iterator[dict]:
        """Yields one entry at a time. A library of thousands of games holds gigabytes of
        response bodies: loading them at once exceeds the memory of small devices, and sorting
        them fills the RAM-backed /tmp SQLite spills to (49 MB on Onion)."""
        if not self._use_sqlite:
            yield from self._json_entries_by_prefix(prefix)
            return

        assert self._connection is not None
        with self._lock:
            row_ids = [
                int(row[0])
                for row in self._connection.execute(
                    "SELECT id FROM api_cache WHERE cacheKey LIKE ?",
                    (f"{prefix}%",),
                ).fetchall()
            ]
        for row_id in row_ids:
            with self._lock:
                row = self._connection.execute(
                    "SELECT * FROM api_cache WHERE id = ?", (row_id,)
                ).fetchone()
            if row is not None:
                yield row_to_dict(row)

    def cached_game_meta(self, game_id: int | None = None) -> list[dict]:
        """Game id, title and icon of every cached patch and achievementsets entry. Kept beside
        api_cache so listing games never reads the response bodies (~230 KB per game, half a
        minute per pass over 1000 games on an SD card)."""
        if self._use_sqlite:
            assert self._connection is not None
            query = "SELECT cacheKey, gameId, title, imagePath FROM cached_game_meta WHERE gameId > 0"
            params: tuple = ()
            if game_id is not None:
                query += " AND gameId = ?"
                params = (game_id,)
            with self._lock:
                rows = self._connection.execute(query, params).fetchall()
            return [row_to_dict(row) for row in rows]

        metas = (
            game_meta.game_meta_for_entry(entry["cacheKey"], entry["responseBody"])
            for prefix in game_meta.GAME_META_PREFIXES
            for entry in self._json_entries_by_prefix(prefix)
        )
        return [
            meta
            for meta in metas
            if meta is not None and (game_id is None or meta["gameId"] == game_id)
        ]

    def cache_summaries_by_prefix(self, prefix: str) -> list[dict]:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                rows = self._connection.execute(
                    "SELECT id, cacheKey, sourceRomPath, cachedAt, firstCachedAt "
                    "FROM api_cache WHERE cacheKey LIKE ?",
                    (f"{prefix}%",),
                ).fetchall()
            return [row_to_dict(row) for row in rows]

        return [
            {key: value for key, value in entry.items() if key != "responseBody"}
            for entry in self._json_entries_by_prefix(prefix)
        ]

    def _json_entries_by_prefix(self, prefix: str) -> list[dict]:
        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                return [
                    dict(item)
                    for item in self._json_state["api_cache"]
                    if item["cacheKey"].startswith(prefix)
                ]

    def cache_keys_by_prefix(self, prefix: str) -> list[str]:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                rows = self._connection.execute(
                    "SELECT cacheKey FROM api_cache WHERE cacheKey LIKE ?",
                    (f"{prefix}%",),
                ).fetchall()
            return [str(row[0]) for row in rows]

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                return [
                    item["cacheKey"]
                    for item in self._json_state["api_cache"]
                    if item["cacheKey"].startswith(prefix)
                ]

    def count_cache_by_prefix(self, prefix: str) -> int:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                row = self._connection.execute(
                    "SELECT COUNT(*) FROM api_cache WHERE cacheKey LIKE ?",
                    (f"{prefix}%",),
                ).fetchone()
            return int(row[0])

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                return sum(
                    1
                    for item in self._json_state["api_cache"]
                    if item["cacheKey"].startswith(prefix)
                )

    def oldest_cache_by_prefix(self, prefix: str) -> dict | None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                row = self._connection.execute(
                    "SELECT * FROM api_cache WHERE cacheKey LIKE ? ORDER BY firstCachedAt, id LIMIT 1",
                    (f"{prefix}%",),
                ).fetchone()
            return row_to_dict(row)

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                matches = [
                    item
                    for item in self._json_state["api_cache"]
                    if item["cacheKey"].startswith(prefix)
                ]
                if not matches:
                    return None
                oldest = min(
                    matches,
                    key=lambda item: (item.get("firstCachedAt", 0), item.get("id", 0)),
                )
                return dict(oldest)

    def delete_cache_by_prefix(self, prefix: str) -> None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                self._connection.execute(
                    "DELETE FROM api_cache WHERE cacheKey LIKE ?", (f"{prefix}%",)
                )
                self._connection.commit()
            self._after_cache_mutation(prefix)
            return

        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                self._json_state["api_cache"] = [
                    item
                    for item in self._json_state["api_cache"]
                    if not item["cacheKey"].startswith(prefix)
                ]
                self._write_json_state_unlocked()
        self._after_cache_mutation(prefix)

    def rename_cache_key(self, old_key: str, new_key: str) -> None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                self._connection.execute(
                    "UPDATE api_cache SET cacheKey = ? WHERE cacheKey = ?",
                    (new_key, old_key),
                )
                self._connection.commit()
            self._after_cache_mutation(old_key, new_key)
            return

        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                for item in self._json_state["api_cache"]:
                    if item["cacheKey"] == old_key:
                        item["cacheKey"] = new_key
                        break
                self._write_json_state_unlocked()
        self._after_cache_mutation(old_key, new_key)

    def delete_cache(self, cache_key: str) -> None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                self._connection.execute(
                    "DELETE FROM api_cache WHERE cacheKey = ?", (cache_key,)
                )
                self._connection.commit()
            self._after_cache_mutation(cache_key)
            return

        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                self._json_state["api_cache"] = [
                    item
                    for item in self._json_state["api_cache"]
                    if item["cacheKey"] != cache_key
                ]
                self._write_json_state_unlocked()
        self._after_cache_mutation(cache_key)

    def clear_cache(self) -> None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                self._connection.execute(
                    """
                DELETE FROM api_cache
                WHERE cacheKey LIKE 'patch:%'
                       OR cacheKey LIKE 'achievementsets:%'
                       OR cacheKey LIKE 'unlocks:%'
                       OR cacheKey LIKE 'startsession:%'
                       OR cacheKey LIKE 'gameid:%'
                       OR cacheKey LIKE 'lastplayed:%'
                       OR cacheKey LIKE 'cachequeue:%'
                       OR cacheKey = ?
                    """,
                    (cache_keys.CACHE_BUDGET,),
                )
                self._connection.commit()
            self._after_cache_mutation(None)
            return

        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                self._json_state["api_cache"] = [
                    item
                    for item in self._json_state["api_cache"]
                    if not (
                        item["cacheKey"].startswith(cache_keys.PREFIX_PATCH)
                        or item["cacheKey"].startswith(
                            cache_keys.PREFIX_ACHIEVEMENTSETS
                        )
                        or item["cacheKey"].startswith(cache_keys.PREFIX_UNLOCKS)
                        or item["cacheKey"].startswith(cache_keys.PREFIX_STARTSESSION)
                        or item["cacheKey"].startswith(cache_keys.PREFIX_GAMEID)
                        or item["cacheKey"].startswith(cache_keys.PREFIX_LAST_PLAYED)
                        or item["cacheKey"].startswith(cache_keys.PREFIX_CACHE_QUEUE)
                        or item["cacheKey"] == cache_keys.CACHE_BUDGET
                    )
                ]
                self._write_json_state_unlocked()
        self._after_cache_mutation(None)

    # Cached game data is user-owned: it stays until the game is deleted or the cache is
    # cleared. Only incidental proxy responses age out, so scoping the periodic refresh to
    # recently played games can no longer silently delete a library nobody has touched.
    def evict_cache_older_than(self, before: int) -> None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                self._connection.execute(
                    """
                    DELETE FROM api_cache
                    WHERE cachedAt < ?
                      AND cacheKey NOT LIKE 'login2::%'
                      AND cacheKey != ?
                      AND cacheKey NOT LIKE 'patch:%'
                      AND cacheKey NOT LIKE 'achievementsets:%'
                      AND cacheKey NOT LIKE 'unlocks:%'
                      AND cacheKey NOT LIKE 'startsession:%'
                      AND cacheKey NOT LIKE 'gameid:%'
                      AND cacheKey NOT LIKE 'cachequeue:%'
                      AND cacheKey NOT LIKE 'watchseen:%'
                    """,
                    (before, cache_keys.USER_AGENT),
                )
                self._connection.commit()
            self._after_cache_mutation(None)
            return

        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                self._json_state["api_cache"] = [
                    item
                    for item in self._json_state["api_cache"]
                    if item["cachedAt"] >= before
                    or item["cacheKey"].startswith(_EVICTION_EXEMPT_PREFIXES)
                    or item["cacheKey"] == cache_keys.USER_AGENT
                ]
                self._write_json_state_unlocked()
        self._after_cache_mutation(None)

    def get_pending_awards(self) -> list[dict]:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                rows = self._connection.execute(
                    "SELECT * FROM pending_awards ORDER BY queuedAt ASC, id ASC"
                ).fetchall()
            return [row_to_dict(row) for row in rows]

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                awards = [dict(item) for item in self._json_state["pending_awards"]]
        return sorted(
            awards,
            key=lambda item: (item.get("queuedAt", 0), item.get("id", 0)),
        )

    def get_latest_pending_award(self) -> dict | None:
        awards = self.get_pending_awards()
        return awards[-1] if awards else None

    def pending_award_exists(self, achievement_id: int) -> bool:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                row = self._connection.execute(
                    "SELECT 1 FROM pending_awards WHERE achievementId = ? LIMIT 1",
                    (achievement_id,),
                ).fetchone()
            return row is not None

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                return any(
                    item["achievementId"] == achievement_id
                    for item in self._json_state["pending_awards"]
                )

    def upsert_pending_award(self, award: dict) -> None:
        if int(award.get("achievementId", 0) or 0) == WARNING_ACHIEVEMENT_ID:
            return

        if self._use_sqlite:
            self._upsert_pending_award_sqlite(award)
            return
        self._upsert_pending_award_json(award)

    def _upsert_pending_award_sqlite(self, award: dict) -> None:
        assert self._connection is not None
        with self._lock:
            self._connection.execute(
                """
                INSERT INTO pending_awards(
                    achievementId,
                    queryString,
                    requestBody,
                    userAgent,
                    queuedAt,
                    retryCount,
                    lastError,
                    status,
                    payloadHash,
                    prevHash,
                    signature,
                    signedAt
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(achievementId) DO UPDATE SET
                    queryString = excluded.queryString,
                    requestBody = excluded.requestBody,
                    userAgent = excluded.userAgent,
                    queuedAt = excluded.queuedAt,
                    retryCount = excluded.retryCount,
                    lastError = excluded.lastError,
                    status = excluded.status,
                    payloadHash = excluded.payloadHash,
                    prevHash = excluded.prevHash,
                    signature = excluded.signature,
                    signedAt = excluded.signedAt
                """,
                (
                    award["achievementId"],
                    award["queryString"],
                    award["requestBody"],
                    award["userAgent"],
                    award["queuedAt"],
                    award.get("retryCount", 0),
                    award.get("lastError"),
                    award.get("status", PENDING_AWARD_STATUS_PENDING),
                    award.get("payloadHash", ""),
                    award.get("prevHash", ""),
                    award.get("signature", ""),
                    award.get("signedAt", 0),
                ),
            )
            self._connection.commit()

    def _upsert_pending_award_json(self, award: dict) -> None:
        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                existing = next(
                    (
                        item
                        for item in self._json_state["pending_awards"]
                        if item["achievementId"] == award["achievementId"]
                    ),
                    None,
                )
                materialized = dict(award)
                materialized.setdefault(
                    "id", next_json_id(self._json_state["pending_awards"])
                )
                materialized.setdefault("retryCount", 0)
                materialized.setdefault("lastError", None)
                materialized.setdefault("status", PENDING_AWARD_STATUS_PENDING)
                materialized.setdefault("payloadHash", "")
                materialized.setdefault("prevHash", "")
                materialized.setdefault("signature", "")
                materialized.setdefault("signedAt", 0)
                if existing is None:
                    self._json_state["pending_awards"].append(materialized)
                else:
                    materialized["id"] = existing.get("id", materialized["id"])
                    existing.update(materialized)
                self._write_json_state_unlocked()

    def update_pending_award(self, award: dict) -> None:
        self.upsert_pending_award(award)

    def delete_pending_award(self, achievement_id: int) -> None:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                self._connection.execute(
                    "DELETE FROM pending_awards WHERE achievementId = ?",
                    (achievement_id,),
                )
                self._connection.commit()
            return

        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                self._json_state["pending_awards"] = [
                    item
                    for item in self._json_state["pending_awards"]
                    if item["achievementId"] != achievement_id
                ]
                self._write_json_state_unlocked()

    def pending_awards_exist_by_status(self, status: str) -> bool:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                row = self._connection.execute(
                    "SELECT 1 FROM pending_awards WHERE status = ? LIMIT 1",
                    (status,),
                ).fetchone()
            return row is not None

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                return any(
                    item.get("status", PENDING_AWARD_STATUS_PENDING) == status
                    for item in self._json_state["pending_awards"]
                )

    def delete_pending_awards_by_statuses(self, statuses: list[str]) -> None:
        if self._use_sqlite:
            assert self._connection is not None
            placeholders = ",".join("?" for _ in statuses)
            with self._lock:
                self._connection.execute(
                    f"DELETE FROM pending_awards WHERE status IN ({placeholders})",
                    tuple(statuses),
                )
                self._connection.commit()
            return

        with self._lock:
            with self._json_file_lock(exclusive=True):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                status_set = set(statuses)
                self._json_state["pending_awards"] = [
                    item
                    for item in self._json_state["pending_awards"]
                    if item.get("status", PENDING_AWARD_STATUS_PENDING)
                    not in status_set
                ]
                self._write_json_state_unlocked()

    def load_login_credentials(self) -> dict | None:
        entry = self.get_cache_by_prefix(cache_keys.PREFIX_LOGIN)
        if entry is None:
            return None

        try:
            payload = json.loads(entry["responseBody"])
        except json.JSONDecodeError:
            return None

        user = payload.get("User")
        token = payload.get("Token")
        if not user or not token:
            return None
        return {"user": user, "token": token}

    def mark_token_invalid(self, token: str) -> None:
        self.upsert_cache(cache_keys.AUTH_INVALID_TOKEN, token)

    def is_token_invalid(self, token: str) -> bool:
        entry = self.get_cache(cache_keys.AUTH_INVALID_TOKEN)
        return entry is not None and entry.get("responseBody") == token

    def clear_invalid_token(self) -> None:
        self.delete_cache(cache_keys.AUTH_INVALID_TOKEN)


def _salvage_pending_award_count(quarantined_path: Path) -> int | None:
    # "Extra data" corruption (a valid document with garbage appended after it,
    # the pattern actually seen in the field) still has an intact JSON value at
    # the start of the file — raw_decode() reads just that and ignores the
    # trailing bytes that made json.load() fail. Other corruption shapes (a
    # truncated write, interleaved writes) won't parse even this far; the
    # caller treats None as "unknown", not "zero".
    try:
        text = quarantined_path.read_text(encoding="utf-8")
        data, _ = json.JSONDecoder().raw_decode(text)
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    pending_awards = data.get("pending_awards")
    if not isinstance(pending_awards, list):
        return None
    return len(pending_awards)


def migrate_user_case_in_cache_keys(store: Storage) -> None:
    prefixes = [
        cache_keys.PREFIX_PATCH,
        cache_keys.PREFIX_ACHIEVEMENTSETS,
        cache_keys.PREFIX_UNLOCKS,
        cache_keys.PREFIX_STARTSESSION,
    ]
    for prefix in prefixes:
        for old_key in store.cache_keys_by_prefix(prefix):
            new_key = _lowercased_user_key(old_key, prefix)
            if new_key is None or new_key == old_key:
                continue
            if store.get_cache(new_key) is not None:
                store.delete_cache(old_key)
            else:
                store.rename_cache_key(old_key, new_key)


def _lowercased_user_key(key: str, prefix: str) -> str | None:
    if prefix == cache_keys.PREFIX_ACHIEVEMENTSETS:
        rest = key.removeprefix(prefix)
        last_colon = rest.rfind(":")
        if last_colon < 0:
            return None
        scope = rest[:last_colon]
        user = rest[last_colon + 1:]
        if not scope or not user:
            return None
        return f"{prefix}{scope}:{user.lower()}"

    rest = key.removeprefix(prefix)
    parts = rest.split(":")
    if len(parts) < 2 or not parts[0] or not parts[1]:
        return None
    game_id = parts[0]
    user = parts[1]
    suffix = (":" + ":".join(parts[2:])) if len(parts) > 2 else ""
    return f"{prefix}{game_id}:{user.lower()}{suffix}"


def game_meta_row(cache_key: str, response_body: str) -> tuple:
    """Parsed before the write transaction starts: the menu and the proxy service share the
    database, and on FAT32 there is no WAL, so a held write lock blocks the other process."""
    meta = game_meta.game_meta_for_entry(cache_key, response_body) or {}
    return (cache_key, meta.get("gameId"), meta.get("title"), meta.get("imagePath"))


def current_millis() -> int:
    return int(time.time() * 1000)


def next_json_id(items: list[dict]) -> int:
    if not items:
        return 1
    return max(int(item.get("id", 0)) for item in items) + 1


def row_to_dict(row: Any | None) -> dict | None:
    if row is None:
        return None
    return dict(row)
