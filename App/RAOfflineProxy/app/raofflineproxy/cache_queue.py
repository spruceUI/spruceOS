from __future__ import annotations

import contextlib
import json
import math
import time
from dataclasses import dataclass, replace
from pathlib import Path

from . import cache_budget, cache_keys
from .config import CONFIG_DIR, ensure_config_dir
from .storage import Storage

try:
    import fcntl
except ModuleNotFoundError:
    fcntl = None

CACHE_QUEUE_MAX_ATTEMPTS = 3
DRAIN_LOCK_FILE = CONFIG_DIR / "cache_queue.drain.lock"
BULK_RUN_LOCK_FILE = CONFIG_DIR / "cache_queue.bulk.lock"
LOCK_POLL_SECONDS = 0.5


@dataclass(frozen=True)
class QueuedRom:
    hashes: list[str]
    source_rom_path: str | None
    label: str
    queued_at: int
    attempts: int = 0

    @property
    def key(self) -> str:
        return cache_keys.cache_queue(self.hashes[0])

    def after_failed_attempt(self) -> QueuedRom | None:
        retry = replace(self, attempts=self.attempts + 1)
        return retry if retry.attempts < CACHE_QUEUE_MAX_ATTEMPTS else None

    def to_json(self) -> str:
        return json.dumps(
            {
                "hashes": self.hashes,
                "sourceRomPath": self.source_rom_path,
                "label": self.label,
                "queuedAt": self.queued_at,
                "attempts": self.attempts,
            },
            separators=(",", ":"),
        )

    @staticmethod
    def from_json(body: str) -> QueuedRom | None:
        try:
            payload = json.loads(body)
            hashes = [
                value
                for value in payload.get("hashes", [])
                if isinstance(value, str) and value.strip()
            ]
            if not hashes:
                return None
            source_rom_path = payload.get("sourceRomPath")
            return QueuedRom(
                hashes=hashes,
                source_rom_path=source_rom_path
                if isinstance(source_rom_path, str) and source_rom_path.strip()
                else None,
                label=str(payload.get("label") or ""),
                queued_at=int(payload.get("queuedAt", 0)),
                attempts=int(payload.get("attempts", 0)),
            )
        except Exception:
            return None


@dataclass(frozen=True)
class QueueEstimate:
    candidates: int
    cached_now: int
    newly_queued: int
    queued_after: int
    eta_minutes: int

    @property
    def needs_confirmation(self) -> bool:
        return self.newly_queued > 0 and self.queued_after > cache_budget.CACHE_BUDGET_LIMIT


def estimate_queue(
    candidates: int,
    already_known: int,
    budget_remaining: int,
    queued_now: int,
    limit: int = cache_budget.CACHE_BUDGET_LIMIT,
    window_minutes: int = cache_budget.CACHE_BUDGET_WINDOW_MS // 60_000,
) -> QueueEstimate:
    """Upper bound for what a bulk run will do, known before a single file is hashed: every
    candidate not already known by path may need RetroAchievements. ROMs RA doesn't know still
    count here, so the real queue can only turn out smaller."""
    fresh = max(0, candidates - already_known)
    cached_now = min(fresh, max(0, budget_remaining))
    newly_queued = fresh - cached_now
    queued_after = queued_now + newly_queued
    eta_minutes = math.ceil(queued_after / limit) * window_minutes
    return QueueEstimate(candidates, cached_now, newly_queued, queued_after, eta_minutes)


def enqueue(storage: Storage, rom: QueuedRom) -> bool:
    """Returns False when the ROM was already waiting in the queue."""
    if storage.get_cache(rom.key) is not None:
        return False
    storage.upsert_cache(rom.key, rom.to_json(), source_rom_path=rom.source_rom_path)
    return True


def get(storage: Storage, key: str) -> QueuedRom | None:
    entry = storage.get_cache(key)
    return QueuedRom.from_json(entry["responseBody"]) if entry is not None else None


def oldest(storage: Storage) -> QueuedRom | None:
    while True:
        entry = storage.oldest_cache_by_prefix(cache_keys.PREFIX_CACHE_QUEUE)
        if entry is None:
            return None
        rom = QueuedRom.from_json(entry["responseBody"])
        if rom is not None:
            return rom
        storage.delete_cache(entry["cacheKey"])


def update(storage: Storage, rom: QueuedRom) -> None:
    storage.upsert_cache(rom.key, rom.to_json(), source_rom_path=rom.source_rom_path)


def remove(storage: Storage, rom: QueuedRom) -> None:
    storage.delete_cache(rom.key)


def remove_keys(storage: Storage, keys) -> None:
    for key in keys:
        storage.delete_cache(key)


def count(storage: Storage) -> int:
    return storage.count_cache_by_prefix(cache_keys.PREFIX_CACHE_QUEUE)


def queued_rom_paths(storage: Storage, normalize) -> set[str]:
    return {
        normalize(entry["sourceRomPath"])
        for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_CACHE_QUEUE)
        if isinstance(entry.get("sourceRomPath"), str) and entry["sourceRomPath"].strip()
    }


class _FileLock:
    """A lock shared by every process on the device: the menu, the CLI and the proxy service
    each open their own Storage, but drain one queue within one budget."""

    def __init__(self, path: Path) -> None:
        self.path = path

    @contextlib.contextmanager
    def hold(self, shared: bool = False, blocking: bool = True, should_abort=None):
        ensure_config_dir()
        with self.path.open("a+") as handle:
            if not self._acquire(handle, shared, blocking, should_abort):
                yield False
                return
            try:
                yield True
            finally:
                if fcntl is not None:
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

    def held_elsewhere(self) -> bool:
        with self.hold(blocking=False) as acquired:
            return not acquired

    @staticmethod
    def _acquire(handle, shared: bool, blocking: bool, should_abort) -> bool:
        if fcntl is None:
            return True
        mode = (fcntl.LOCK_SH if shared else fcntl.LOCK_EX) | fcntl.LOCK_NB
        while True:
            try:
                fcntl.flock(handle.fileno(), mode)
                return True
            except OSError:
                if not blocking or (should_abort is not None and should_abort()):
                    return False
                time.sleep(LOCK_POLL_SECONDS)


# Only one caller drains at a time: a bulk run's first batch waits for it, the service's worker
# skips its round.
drain_lock = _FileLock(DRAIN_LOCK_FILE)
# Held (shared) while a bulk run hashes and runs its first batch; the service's worker stands
# down meanwhile so it never drains a queue that is still filling.
bulk_run_lock = _FileLock(BULK_RUN_LOCK_FILE)


def bulk_run_active() -> bool:
    return bulk_run_lock.held_elsewhere()
