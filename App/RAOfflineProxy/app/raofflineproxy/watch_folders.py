from __future__ import annotations

import json
import os
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path

from . import cache_budget, cache_keys
from .config import CONFIG_FILE, save_config
from .rom_browser import MAX_SCAN_ENTRIES, list_scannable_files_recursive, normalize_cached_rom_path
from .smart_cache import known_rom_paths, run_cache_paths
from .storage import Storage, current_millis

WATCHED_FOLDERS_KEY = "watched_folders"
RESCAN_INTERVAL_MS = cache_budget.CACHE_BUDGET_WINDOW_MS


@dataclass(frozen=True)
class FolderScan:
    folder: str
    files: int
    new: int
    handled: int
    queued: int

    @property
    def complete(self) -> bool:
        return self.handled == self.new


def normalize_folder(path: str | Path) -> str:
    return os.path.abspath(os.path.expanduser(str(path)))


def watched_folders(config_data: dict) -> list[str]:
    folders = config_data.get(WATCHED_FOLDERS_KEY)
    if not isinstance(folders, list):
        return []
    return [folder for folder in folders if isinstance(folder, str) and folder.strip()]


def configured_watched_folders() -> list[str]:
    """Read quietly on every service round: load_config() logs a broken file, which would
    write the same warning to the log every minute."""
    try:
        data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    return watched_folders(data) if isinstance(data, dict) else []


def watch_folder(config_data: dict, path: str | Path) -> bool:
    folder = normalize_folder(path)
    folders = watched_folders(config_data)
    if folder in folders:
        return False
    config_data[WATCHED_FOLDERS_KEY] = [*folders, folder]
    save_config(config_data)
    return True


def unwatch_folder(config_data: dict, storage: Storage, path: str | Path) -> bool:
    folder = normalize_folder(path)
    forget_seen(storage, seen_paths(storage, folder))
    forget_scan(storage, folder)
    folders = watched_folders(config_data)
    if folder not in folders:
        return False
    config_data[WATCHED_FOLDERS_KEY] = [entry for entry in folders if entry != folder]
    save_config(config_data)
    return True


def last_scans(storage: Storage) -> dict[str, int]:
    entry = storage.get_cache(cache_keys.WATCH_SCANS)
    if entry is None:
        return {}
    try:
        data = json.loads(entry["responseBody"])
    except (TypeError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {
        folder: int(scanned_at)
        for folder, scanned_at in data.items()
        if isinstance(folder, str) and isinstance(scanned_at, (int, float))
    }


def record_scan(storage: Storage, folder: str, scanned_at: int) -> None:
    scans = last_scans(storage)
    scans[folder] = scanned_at
    storage.upsert_cache(cache_keys.WATCH_SCANS, json.dumps(scans))


def forget_scan(storage: Storage, folder: str) -> None:
    scans = last_scans(storage)
    if scans.pop(folder, None) is not None:
        storage.upsert_cache(cache_keys.WATCH_SCANS, json.dumps(scans))


def due_folders(storage: Storage, folders: list[str], now: int) -> list[str]:
    scans = last_scans(storage)
    return [
        folder
        for folder in folders
        if os.path.isdir(folder) and now - scans.get(folder, 0) >= RESCAN_INTERVAL_MS
    ]


def seen_paths(storage: Storage, folder: str) -> set[str]:
    prefix = cache_keys.watch_seen(f"{folder.rstrip('/')}/")
    # The storage prefix lookup is a LIKE match, so "_" and "%" in folder names would match
    # neighbouring folders too; the startswith check keeps it to this folder.
    return {
        key[len(cache_keys.PREFIX_WATCH_SEEN):]
        for key in storage.cache_keys_by_prefix(prefix)
        if key.startswith(prefix)
    }


def mark_seen(storage: Storage, paths: Iterable[str]) -> None:
    for path in paths:
        storage.upsert_cache(cache_keys.watch_seen(path), "{}")


def forget_seen(storage: Storage, paths: Iterable[str]) -> None:
    for path in paths:
        storage.delete_cache(cache_keys.watch_seen(path))


def scan_folder(
    storage: Storage,
    config_data: dict,
    folder: str,
    should_abort: Callable[[], bool] | None = None,
) -> FolderScan:
    """Hashes and queues only the files this folder has not handled before. A file counts as
    handled once caching has an answer for it, including "no RetroAchievements match", so
    unknown files are not hashed again on every pass."""
    files = list_scannable_files_recursive(Path(folder))
    listed = {str(path) for path in files}
    seen = seen_paths(storage, folder)
    known = known_rom_paths(storage)
    unseen = [path for path in files if str(path) not in seen]
    mark_seen(storage, (str(path) for path in unseen if normalize_cached_rom_path(path) in known))
    new = [path for path in unseen if normalize_cached_rom_path(path) not in known]

    handled: list[str] = []
    result = run_cache_paths(
        storage,
        config_data,
        new,
        should_abort=should_abort,
        on_rom_result=lambda path, _status, _message: handled.append(str(path)),
        cache_now=False,
    )
    mark_seen(storage, handled)
    # A capped listing leaves files out that still exist, so their markers must survive.
    if len(files) < MAX_SCAN_ENTRIES:
        forget_seen(storage, seen - listed)

    scan = FolderScan(folder, len(files), len(new), len(handled), result.queued)
    if scan.complete:
        record_scan(storage, folder, current_millis())
    return scan
