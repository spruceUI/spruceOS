from __future__ import annotations

import contextlib
import json
import logging
import os
import threading
import time
from pathlib import Path
from typing import Any

from . import cache_keys, es_export, storage_corruption
from .config import DATABASE_FILE, ensure_config_dir

try:
    import fcntl
except ModuleNotFoundError:
    fcntl = None

LOGGER = logging.getLogger("raofflineproxy")

try:
    import sqlite3
except ModuleNotFoundError:
    sqlite3 = None

JSON_STORE_FILE = DATABASE_FILE.with_suffix(".json")

PENDING_AWARD_STATUS_PENDING = "pending"
PENDING_AWARD_STATUS_DELETED = "deleted"
PENDING_AWARD_STATUS_STALE = "stale"
PENDING_AWARD_STATUS_FLUSHED = "flushed"
WARNING_ACHIEVEMENT_ID = 101000001


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
        else:
            self._initialize_json()

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
        self._after_cache_mutation(cache_key)

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

    def get_all_cache_by_prefix(self, prefix: str) -> list[dict]:
        if self._use_sqlite:
            assert self._connection is not None
            with self._lock:
                rows = self._connection.execute(
                    "SELECT * FROM api_cache WHERE cacheKey LIKE ? ORDER BY cachedAt DESC",
                    (f"{prefix}%",),
                ).fetchall()
            return [row_to_dict(row) for row in rows]

        with self._lock:
            with self._json_file_lock(exclusive=False):
                self._reload_json_state_unlocked()
                assert self._json_state is not None
                matches = [
                    dict(item)
                    for item in self._json_state["api_cache"]
                    if item["cacheKey"].startswith(prefix)
                ]
        return sorted(matches, key=lambda item: item.get("cachedAt", 0), reverse=True)

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
                    """
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
                    )
                ]
                self._write_json_state_unlocked()
        self._after_cache_mutation(None)

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
                    or item["cacheKey"].startswith(cache_keys.PREFIX_LOGIN)
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
        for entry in store.get_all_cache_by_prefix(prefix):
            old_key = entry["cacheKey"]
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
