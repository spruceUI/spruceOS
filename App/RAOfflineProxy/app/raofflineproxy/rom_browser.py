from __future__ import annotations

import enum
import json
import logging
import tempfile
import time
import urllib.error
import zipfile
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urljoin

from . import cache_budget, cache_keys, cache_queue, rate_limit, usage_stats
from .auth import resolve_credentials
from .cache_queue import QueuedRom
from .config import FALLBACK_USER_AGENT, RA_MEDIA_HOST, image_caching_enabled, upstream_host
from .es_export import collect_cached_game_ids
from .image_cache import (
    clear_all_cached_images,
    delete_cached_images_for_game,
    download_static_image,
    extract_image_path,
    game_image_dir,
    images_downloaded_inline,
    resolve_cached_static_asset,
    schedule_image_download,
)
from .network import build_api_url, http_get
from .rom_cache import (
    CacheGameAuthError,
    cache_game,
    filter_warning_achievement_ids,
    find_achievement_game_ids,
    merge_start_session_unlock_ids,
    merged_unlock_ids as merged_unlock_ids_for_user,
    pending_unlock_achievement_ids,
)
from .rom_hashing import (
    hash_7z_entry_candidates,
    hash_rom,
    hash_rom_candidates,
    hash_rom_candidates_result,
    list_7z_entries,
    supported_rom_extensions,
)
from .storage import Storage, current_millis
from .utils import proxy_user_agent, self_user_agent

LOGGER = logging.getLogger("raofflineproxy")
SUPPORTED_ROM_EXTENSIONS = supported_rom_extensions()
SUPPORTED_ARCHIVE_EXTENSIONS = {".zip", ".7z"}
# Archives the stdlib can open. A .7z goes through the native hasher instead,
# which bundles a 7z reader (third_party/lzma-sdk), so it never reaches zipfile.
ZIP_READABLE_ARCHIVE_EXTENSIONS = {".zip"}
EXCLUDED_BROWSER_DIR_NAMES = {"Imgs"}
MAX_SCAN_ENTRIES = 5000
MAX_SCAN_DEPTH = 12
PACE_POLL_SECONDS = 1.0
# RetroAchievements adds hashes over time, so a "no match" is only cached long enough to
# stop a repeated scan of the same folder from re-querying every unsupported ROM.
GAMEID_MISS_TTL_MS = 7 * 24 * 60 * 60 * 1000


@dataclass
class CachedGameEntry:
    game_id: int
    title: str
    image_url: str | None = None


@dataclass
class AddRomResult:
    success: bool
    message: str
    game: CachedGameEntry | None = None
    already_cached: bool = False
    queued: bool = False


@dataclass(frozen=True)
class LocalGameIdAnswer:
    """A ROM's game id as far as the local gameid cache knows it, without asking RA."""

    game_id: int | None = None
    hash_value: str | None = None
    no_match: bool = False


class QueuedRomOutcome(enum.Enum):
    CACHED = "cached"
    NO_MATCH = "no_match"
    ALREADY_CACHED = "already_cached"
    FAILED = "failed"
    AUTH_REJECTED = "auth_rejected"


class DrainStop(enum.Enum):
    EMPTY = "empty"
    BUDGET_EXHAUSTED = "budget_exhausted"
    RATE_LIMITED = "rate_limited"
    PAUSED = "paused"
    FAILED = "failed"
    AUTH_REJECTED = "auth_rejected"
    BUSY = "busy"


@dataclass
class DrainResult:
    cached: int
    no_match: int
    stop: DrainStop
    next_attempt_at: int | None = None
    time_limited: bool = False


@dataclass
class BrowserEntry:
    path: Path
    name: str
    is_dir: bool
    is_cached: bool


def normalize_cached_rom_path(path: str | Path) -> str:
    normalized = str(path).replace("\\", "/").strip()
    parts = [part for part in normalized.split("/") if part]
    if not parts:
        return "/"
    if len(parts) == 1:
        return f"/{parts[0]}"
    return f"/{parts[-2]}/{parts[-1]}"


def load_cached_rom_paths(storage: Storage) -> set[str]:
    return {
        normalize_cached_rom_path(entry["sourceRomPath"])
        for entry in storage.cache_summaries_by_prefix(cache_keys.PREFIX_PATCH)
        if isinstance(entry.get("sourceRomPath"), str)
        and entry["sourceRomPath"].strip()
    }


def cached_rom_paths_by_game(storage: Storage) -> dict[int, str]:
    """The ROM each cached game was cached from, as "/<system folder>/<file>": the part that
    stays the same when the card is mounted elsewhere or moves to another device. With several
    entries for one game (one per account), the most recently cached one wins."""
    latest: dict[int, tuple[int, str]] = {}
    for entry in storage.cache_summaries_by_prefix(cache_keys.PREFIX_PATCH):
        game_id = cache_keys.parse_game_id_from_patch_key(str(entry.get("cacheKey", "")))
        path = entry.get("sourceRomPath")
        if game_id is None or not isinstance(path, str) or not path.strip():
            continue
        cached_at = int(entry.get("cachedAt") or 0)
        if game_id not in latest or cached_at > latest[game_id][0]:
            latest[game_id] = (cached_at, normalize_cached_rom_path(path))
    return {game_id: path for game_id, (_cached_at, path) in latest.items()}


def list_cached_games(storage: Storage) -> list[CachedGameEntry]:
    games = cached_games_from_meta(storage.cached_game_meta())
    return sorted(games.values(), key=lambda game: game.title.lower())


def cached_games_from_meta(metas: list[dict]) -> dict[int, CachedGameEntry]:
    """A game's patch names it; its achievementsets only name games cached without a patch."""
    games: dict[int, CachedGameEntry] = {}
    for meta in sorted(metas, key=lambda meta: not meta["cacheKey"].startswith(cache_keys.PREFIX_PATCH)):
        games.setdefault(
            int(meta["gameId"]),
            CachedGameEntry(
                game_id=int(meta["gameId"]),
                title=meta["title"] or f"Game {meta['gameId']}",
                image_url=normalize_preview_url(meta["imagePath"]),
            ),
        )
    return games


def list_browser_entries(current_dir: Path) -> list[Path]:
    directories: list[Path] = []
    files: list[Path] = []
    for entry in sorted(
        current_dir.iterdir(), key=lambda path: (not path.is_dir(), path.name.lower())
    ):
        if entry.name.startswith("."):
            continue
        if entry.is_dir():
            if entry.name in EXCLUDED_BROWSER_DIR_NAMES:
                continue
            if directory_has_supported_roms(entry):
                directories.append(entry)
            continue
        if is_supported_browser_file(entry):
            files.append(entry)
    return directories + files


def list_browser_entries_fast(current_dir: Path) -> list[Path]:
    directories: list[Path] = []
    files: list[Path] = []
    for entry in sorted(
        current_dir.iterdir(), key=lambda path: (not path.is_dir(), path.name.lower())
    ):
        if entry.name.startswith("."):
            continue
        if entry.is_dir():
            if entry.name in EXCLUDED_BROWSER_DIR_NAMES:
                continue
            directories.append(entry)
            continue
        if is_supported_browser_file(entry):
            files.append(entry)
    return directories + files


def describe_browser_entries_fast(current_dir: Path) -> list[BrowserEntry]:
    return [
        BrowserEntry(
            path=path,
            name=path.name,
            is_dir=path.is_dir(),
            is_cached=False,
        )
        for path in list_browser_entries_fast(current_dir)
    ]


def list_browser_files_fast(current_dir: Path) -> list[Path]:
    return [path for path in list_browser_entries_fast(current_dir) if path.is_file()]


def list_scannable_files_recursive(root: Path) -> list[Path]:
    result: list[Path] = []
    stack: list[tuple[Path, int]] = [(root, 0)]
    while stack and len(result) < MAX_SCAN_ENTRIES:
        current_dir, depth = stack.pop()
        try:
            entries = sorted(
                current_dir.iterdir(),
                key=lambda path: (not path.is_dir(), path.name.lower()),
            )
        except OSError:
            continue
        for entry in entries:
            if len(result) >= MAX_SCAN_ENTRIES:
                break
            if entry.name.startswith("."):
                continue
            if entry.is_dir():
                if entry.name in EXCLUDED_BROWSER_DIR_NAMES:
                    continue
                if depth < MAX_SCAN_DEPTH:
                    stack.append((entry, depth + 1))
            elif is_supported_browser_file(entry):
                result.append(entry)
    return result


def describe_browser_entries(current_dir: Path, storage: Storage) -> list[BrowserEntry]:
    cached_game_ids = collect_cached_game_ids(storage)
    entries: list[BrowserEntry] = []
    for path in list_browser_entries(current_dir):
        entries.append(
            BrowserEntry(
                path=path,
                name=path.name,
                is_dir=path.is_dir(),
                is_cached=not path.is_dir()
                and browser_file_is_cached(path, storage, cached_game_ids),
            )
        )
    return entries


def browser_file_is_cached(
    path: Path, storage: Storage, cached_game_ids: set[int] | None = None
) -> bool:
    if cached_game_ids is None:
        cached_game_ids = collect_cached_game_ids(storage)

    try:
        hash_candidates = hash_candidates_for_manual_cache(path)
    except Exception:
        return False

    for hash_value in hash_candidates:
        game_id = cached_game_id_for_hash(storage, hash_value)
        if game_id is not None and game_id in cached_game_ids:
            return True

    return False


def cached_game_id_for_hash(storage: Storage, hash_value: str) -> int | None:
    entry = storage.get_cache(cache_keys.game_id(hash_value))
    if entry is not None:
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            payload = {}
        game_id = payload.get("GameID")
        if isinstance(game_id, int) and game_id > 0:
            return game_id

    achievementsets_entry = storage.get_cache_by_prefix(
        f"{cache_keys.PREFIX_ACHIEVEMENTSETS}{hash_value}:"
    )
    if achievementsets_entry is None:
        return None

    try:
        payload = json.loads(achievementsets_entry["responseBody"])
    except Exception:
        return None

    game_id = payload.get("GameId")
    return game_id if isinstance(game_id, int) and game_id > 0 else None


def directory_has_supported_roms(path: Path) -> bool:
    try:
        for entry in path.iterdir():
            if entry.name.startswith("."):
                continue
            if entry.is_file() and is_supported_browser_file(entry):
                return True
            if entry.is_dir() and directory_has_supported_roms(entry):
                return True
    except Exception:
        return False

    return False


def is_supported_browser_file(path: Path) -> bool:
    suffix = path.suffix.lower()
    if suffix in SUPPORTED_ROM_EXTENSIONS:
        return True
    # Any .zip is a candidate: either a zipped single console ROM (hashed by
    # content) or an arcade/MAME set such as Neo Geo (hashed by filename via
    # rc_hash). Don't peek inside to decide — that excludes arcade sets, whose
    # internal files use non-console extensions (.p1/.c1/.v1/...).
    if suffix in SUPPORTED_ARCHIVE_EXTENSIONS:
        return True
    return False


def archive_has_supported_roms(path: Path) -> bool:
    return bool(list_archive_rom_entries(path))


def select_archive_rom_names(names: list[str]) -> list[str]:
    """Which entries of an archive count as the ROM to hash.

    Shared by the zip and 7z paths so both formats select the same way.
    """
    rom_names = [
        name for name in names if Path(name).suffix.lower() in SUPPORTED_ROM_EXTENSIONS
    ]
    if rom_names:
        return rom_names
    # No recognized ROM extension, but a single-file archive is almost certainly
    # a ROM (a system we don't enumerate, e.g. .gen). Multi-file archives with no
    # ROM extension are arcade/MAME sets.
    if len(names) == 1:
        return names
    return []


def list_archive_rom_entries(path: Path) -> list[zipfile.ZipInfo]:
    if path.suffix.lower() not in ZIP_READABLE_ARCHIVE_EXTENSIONS:
        return []

    try:
        with zipfile.ZipFile(path) as archive:
            files = [
                info
                for info in archive.infolist()
                if not info.is_dir()
                and not Path(info.filename).name.startswith(".")
            ]
            selected = set(select_archive_rom_names([info.filename for info in files]))
            return [info for info in files if info.filename in selected]
    except Exception:
        return []


def list_7z_rom_entries(path: Path) -> list[str]:
    if path.suffix.lower() != ".7z":
        return []

    names = [
        name for name in list_7z_entries(path) if not Path(name).name.startswith(".")
    ]
    return select_archive_rom_names(names)


def hash_candidates_for_7z(path: Path) -> list[str]:
    rom_entries = list_7z_rom_entries(path)

    if len(rom_entries) > 1:
        raise ValueError("archive contains multiple supported ROMs")

    if len(rom_entries) == 1:
        candidates = hash_7z_entry_candidates(path, rom_entries[0])
        if candidates:
            return candidates

    # Either an arcade/MAME set (no inner console ROM) or an entry the native
    # reader could not decompress. Both fall back to rc_hash's arcade rule,
    # which hashes the archive's own filename.
    return hash_rom_candidates(path)


def hash_candidates_for_manual_cache(path: Path) -> list[str]:
    if path.suffix.lower() == ".7z":
        return hash_candidates_for_7z(path)

    if path.suffix.lower() not in SUPPORTED_ARCHIVE_EXTENSIONS:
        if path.suffix.lower() in (".chd", ".cue", ".m3u"):
            result = hash_rom_candidates_result(path)
            if result.error is not None:
                raise ValueError(result.error)
            return result.candidates
        return hash_rom_candidates(path)

    rom_entries = list_archive_rom_entries(path)

    if len(rom_entries) > 1:
        raise ValueError("archive contains multiple supported ROMs")

    # Exactly one inner console ROM: hash its extracted content.
    if len(rom_entries) == 1:
        rom_entry = rom_entries[0]
        with zipfile.ZipFile(path) as archive:
            with archive.open(rom_entry) as source:
                rom_bytes = source.read()

        suffix = Path(rom_entry.filename).suffix
        entry_name = Path(rom_entry.filename).stem
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_name = entry_name if suffix else Path(rom_entry.filename).name
            temp_path = Path(temp_dir) / f"{temp_name}{suffix}"
            temp_path.write_bytes(rom_bytes)
            if temp_path.suffix.lower() == ".chd":
                result = hash_rom_candidates_result(temp_path)
                if result.error is not None:
                    raise ValueError(result.error)
                return result.candidates
            return hash_rom_candidates(temp_path)

    # Zero or multiple inner console ROMs: treat as an arcade/MAME set (Neo Geo,
    # CPS, etc.). rc_hash's arcade hash is MD5 of the archive's base filename, so
    # we pass the path straight through. Every .7z lands here, since its entries
    # are never enumerated.
    return hash_rom_candidates(path)


def is_cacheable_game_id_response(body: str) -> bool:
    try:
        payload = json.loads(body)
    except Exception:
        return False
    if not isinstance(payload, dict):
        return False
    return game_id_from_response(body) is not None or payload.get("Success") is True


def game_id_from_response(body: str) -> int | None:
    try:
        payload = json.loads(body)
    except Exception:
        return None
    game_id = payload.get("GameID") if isinstance(payload, dict) else None
    return game_id if isinstance(game_id, int) and game_id > 0 else None


def fetch_game_id(
    hash_value: str,
    credentials: dict,
    user_agent: str,
    config_data: dict,
    storage: Storage,
) -> int | None:
    cached = storage.get_cache(cache_keys.game_id(hash_value))
    if cached is not None:
        cached_game_id = game_id_from_response(cached["responseBody"])
        if cached_game_id is not None:
            return cached_game_id
        if current_millis() - cached["cachedAt"] < GAMEID_MISS_TTL_MS:
            return None

    url = build_api_url(
        upstream_host(config_data),
        "gameid",
        {
            "m": hash_value,
            "u": credentials["user"],
            "t": credentials["token"],
        },
    )
    response_body = http_get(url, proxy_user_agent(user_agent or FALLBACK_USER_AGENT))
    payload = json.loads(response_body)
    if is_cacheable_game_id_response(response_body):
        storage.upsert_cache(cache_keys.game_id(hash_value), response_body)
    game_id = payload.get("GameID")
    if not isinstance(game_id, int) or game_id <= 0:
        return None
    return int(game_id)


def add_rom_to_cache(path: Path, storage: Storage, config_data: dict) -> AddRomResult:
    """Caches one ROM right away if the caching budget allows it, otherwise queues it for the
    proxy service."""
    user_agent = self_user_agent()
    credentials = resolve_credentials(storage, config_data, user_agent)
    if credentials is None:
        return AddRomResult(False, "RetroAchievements login required")

    try:
        hash_candidates = hash_candidates_for_manual_cache(path)
        if not hash_candidates:
            return AddRomResult(False, "Hash failed: unsupported or unreadable ROM")
    except Exception as exc:
        return AddRomResult(False, f"Hash failed: {exc}")

    local = local_game_id_answer(storage, hash_candidates)
    if local.no_match:
        return AddRomResult(False, "No RetroAchievements match")
    if local.game_id is not None and local.game_id in cached_game_ids(storage):
        remember_source_rom_path(storage, local.game_id, credentials["user"], path)
        return already_cached_result(storage, local.game_id)

    rom = QueuedRom(
        hashes=hash_candidates,
        source_rom_path=normalize_cached_rom_path(path),
        label=path.name,
        queued_at=current_millis(),
    )
    outcomes: dict[str, tuple[QueuedRomOutcome, int | None, str]] = {}
    with cache_queue.bulk_run_lock.hold(shared=True):
        added = cache_queue.enqueue(storage, rom)
        drain = drain_cache_queue(
            storage,
            config_data,
            credentials,
            user_agent,
            wait_for_lock=True,
            keys=[rom.key],
            on_outcome=lambda queued, outcome, game_id, message: outcomes.__setitem__(
                queued.key, (outcome, game_id, message)
            ),
        )

    if rom.key not in outcomes:
        if drain.stop is DrainStop.AUTH_REJECTED:
            if added:
                cache_queue.remove(storage, rom)
            return AddRomResult(False, "RetroAchievements rejected the login")
        return AddRomResult(
            True, queued_message(rom.label, drain.next_attempt_at), queued=True
        )

    outcome, game_id, message = outcomes[rom.key]
    if outcome is QueuedRomOutcome.FAILED and added:
        cache_queue.remove(storage, rom)
    if outcome is QueuedRomOutcome.ALREADY_CACHED and game_id is not None:
        return already_cached_result(storage, game_id)
    if outcome is not QueuedRomOutcome.CACHED or game_id is None:
        return AddRomResult(False, message)
    game = find_cached_game(storage, game_id)
    if game is None:
        return AddRomResult(False, "Caching failed: patch data was not stored")
    return AddRomResult(True, f"Cached {game.title}", game=game)


def queued_message(label: str, next_attempt_at: int | None) -> str:
    if next_attempt_at is None:
        return f"Queued {label}: caching continues while the proxy is running"
    return (
        f"Queued {label}: caching continues at "
        f"{format_clock_time(next_attempt_at)} while the proxy is running"
    )


def format_clock_time(millis: int) -> str:
    return time.strftime("%H:%M", time.localtime(millis / 1000))


def find_cached_game(storage: Storage, game_id: int) -> CachedGameEntry | None:
    return cached_games_from_meta(storage.cached_game_meta(game_id)).get(game_id)


def achievementsets_keys_for_game(storage: Storage, game_id: int) -> list[str]:
    return [
        meta["cacheKey"]
        for meta in storage.cached_game_meta(game_id)
        if meta["cacheKey"].startswith(cache_keys.PREFIX_ACHIEVEMENTSETS)
    ]


def already_cached_result(storage: Storage, game_id: int) -> AddRomResult:
    game = find_cached_game(storage, game_id)
    title = game.title if game is not None else f"Game {game_id}"
    return AddRomResult(True, f"Already cached {title}", game=game, already_cached=True)


def cached_game_ids(storage: Storage) -> set[int]:
    return {
        game_id
        for game_id in (
            cache_keys.parse_game_id_from_patch_key(key)
            for key in storage.cache_keys_by_prefix(cache_keys.PREFIX_PATCH)
        )
        if game_id is not None
    }


def local_game_id_answer(
    storage: Storage, candidates: list[str], now: int | None = None
) -> LocalGameIdAnswer:
    """Walks the candidates in the same order as the RA lookup does."""
    current = now if now is not None else current_millis()
    for hash_value in candidates:
        cached = storage.get_cache(cache_keys.game_id(hash_value))
        if cached is None:
            return LocalGameIdAnswer()
        game_id = game_id_from_response(cached["responseBody"])
        if game_id is not None:
            return LocalGameIdAnswer(game_id=game_id, hash_value=hash_value)
        if current - cached["cachedAt"] >= GAMEID_MISS_TTL_MS:
            return LocalGameIdAnswer()
    return LocalGameIdAnswer(no_match=True)


def enqueue_rom_if_needed(
    storage: Storage,
    candidates: list[str],
    known_game_ids: set[int],
    path: Path,
    on_queued=None,
    now: int | None = None,
) -> QueuedRom | None:
    """Queues a hashed ROM unless the local cache already answers it: an already-cached game or
    a fresh cached no-match costs RA nothing. Returns the ROM when it is waiting in the queue;
    on_queued only hears about rows this call actually added."""
    local = local_game_id_answer(storage, candidates, now)
    if local.no_match:
        return None
    if local.game_id is not None and local.game_id in known_game_ids:
        return None
    rom = QueuedRom(
        hashes=candidates,
        source_rom_path=normalize_cached_rom_path(path),
        label=path.name,
        queued_at=now if now is not None else current_millis(),
    )
    if cache_queue.enqueue(storage, rom) and on_queued is not None:
        on_queued(rom.key)
    return rom


def drain_cache_queue(
    storage: Storage,
    config_data: dict,
    credentials: dict,
    user_agent: str,
    *,
    should_pause=None,
    wait_for_lock: bool = False,
    keys: list[str] | None = None,
    on_item=None,
    on_outcome=None,
) -> DrainResult:
    """The single place that sends RA requests for bulk caching: works through the queue oldest
    first (or through keys, in order) within the caching budget. A window allows
    CACHE_BUDGET_LIMIT cached games; ROMs RetroAchievements doesn't know don't count. After the
    first CACHE_BURST_GAMES of a window, ROMs that need RetroAchievements start
    CACHE_PACE_SECONDS apart, so the rest of the budget is spread over the window; the lock is
    free while it waits. A batch ends
    after CACHE_BATCH_MAX_MS at the latest and leaves the rest for the next window. A 429 stops
    the queue for at least RATE_LIMIT_PAUSE_MS. Only one caller drains at a time; without
    wait_for_lock a concurrent call returns BUSY at once. A failed ROM keeps its place and is
    retried on a later round instead of back to back. on_item reports progress in games within
    the current window."""
    pause = should_pause or (lambda: False)
    with cache_queue.drain_lock.hold(blocking=wait_for_lock, should_abort=pause) as lock:
        if not lock:
            return DrainResult(0, 0, DrainStop.BUSY)
        with cache_queue.draining_lock.hold(shared=True), rate_limit.background():
            return _drain_locked(
                storage,
                config_data,
                credentials,
                user_agent,
                lock,
                pause,
                None if keys is None else list(dict.fromkeys(keys)),
                on_item,
                on_outcome,
            )


def past_burst(storage: Storage, requested: int) -> bool:
    """Lookups for ROMs RetroAchievements doesn't know never fill the budget, so a drain's own
    requests count as well."""
    burst = cache_budget.CACHE_BURST_GAMES
    return requested >= burst or cache_budget.used(storage) >= burst


def wait_for_pace(ready_at: float, should_pause) -> bool:
    """Waits until the monotonic clock reaches ready_at; False when should_pause asks to stop
    first, so a paused drain lets a game cached by hand go ahead within a second."""
    while True:
        if should_pause():
            return False
        left = ready_at - time.monotonic()
        if left <= 0:
            return True
        time.sleep(min(PACE_POLL_SECONDS, left))


def _drain_locked(
    storage: Storage,
    config_data: dict,
    credentials: dict,
    user_agent: str,
    lock,
    should_pause,
    pending_keys: list[str] | None,
    on_item,
    on_outcome,
) -> DrainResult:
    cached = 0
    no_match = 0
    requested = 0
    next_request_at = 0.0
    paced = False
    started_at = current_millis()
    stop_at = started_at + cache_budget.CACHE_BATCH_MAX_MS
    known_game_ids = cached_game_ids(storage)

    def result(
        stop: DrainStop, next_attempt_at: int | None = None, time_limited: bool = False
    ) -> DrainResult:
        drained = DrainResult(cached, no_match, stop, next_attempt_at, time_limited)
        usage_stats.record_batch(
            cached, no_match, stop.value, time_limited, current_millis() - started_at
        )
        return drained

    def rate_limited() -> DrainResult | None:
        until = rate_limit.paused_until()
        if until is None:
            return None
        cache_budget.pause_until(storage, until)
        LOGGER.warning("Cache queue paused: RetroAchievements answered 429")
        return result(DrainStop.RATE_LIMITED, until)

    def next_rom() -> QueuedRom | None:
        if pending_keys is None:
            return cache_queue.oldest(storage)
        while pending_keys:
            rom = cache_queue.get(storage, pending_keys[0])
            if rom is not None:
                return rom
            pending_keys.pop(0)
        return None

    def report(rom: QueuedRom, outcome: QueuedRomOutcome, game_id: int | None, message: str) -> None:
        if on_outcome is not None:
            on_outcome(rom, outcome, game_id, message)

    while True:
        if should_pause():
            return result(DrainStop.PAUSED)
        stopped = rate_limited()
        if stopped is not None:
            return stopped
        if current_millis() >= stop_at:
            LOGGER.info("Cache queue: batch time limit reached")
            return result(
                DrainStop.BUDGET_EXHAUSTED,
                cache_budget.next_available_at(storage),
                time_limited=True,
            )
        rom = next_rom()
        if rom is None:
            return result(DrainStop.EMPTY)

        local = local_game_id_answer(storage, rom.hashes)
        if local.no_match:
            cache_queue.remove(storage, rom)
            no_match += 1
            report(rom, QueuedRomOutcome.NO_MATCH, None, "No RetroAchievements match")
            continue
        if local.game_id is not None and local.game_id in known_game_ids:
            remember_source_rom_path(storage, local.game_id, credentials["user"], rom.source_rom_path)
            cache_queue.remove(storage, rom)
            report(rom, QueuedRomOutcome.ALREADY_CACHED, local.game_id, "")
            continue

        games_left = cache_budget.remaining(storage)
        if games_left == 0:
            return result(DrainStop.BUDGET_EXHAUSTED, cache_budget.next_available_at(storage))
        if requested > 0 and not paced and past_burst(storage, requested):
            # Another caller, e.g. a game cached by hand, may drain while this one waits, so
            # everything is checked again afterwards.
            with lock.released(should_pause):
                ready = wait_for_pace(next_request_at, should_pause)
            if not ready or not lock:
                return result(DrainStop.PAUSED)
            known_game_ids.update(cached_game_ids(storage))
            paced = True
            continue
        paced = False
        next_request_at = time.monotonic() + cache_budget.CACHE_PACE_SECONDS
        if on_item is not None:
            queued = len(pending_keys) if pending_keys is not None else cache_queue.count(storage)
            on_item(cached + 1, window_progress_total(cached, queued, games_left), rom.label)
        requested += 1
        outcome, game_id, message = cache_queued_rom(
            storage, config_data, credentials, user_agent, rom, local, known_game_ids
        )
        if outcome is QueuedRomOutcome.CACHED:
            cache_budget.charge_game(storage)
        stopped = rate_limited()
        if stopped is not None:
            return stopped

        if outcome is QueuedRomOutcome.AUTH_REJECTED:
            LOGGER.warning("Cache queue paused: RetroAchievements rejected the login")
            return result(DrainStop.AUTH_REJECTED)
        if outcome is QueuedRomOutcome.FAILED:
            record_failed_attempt(storage, rom)
            report(rom, outcome, game_id, message)
            return result(DrainStop.FAILED)

        cache_queue.remove(storage, rom)
        if outcome is QueuedRomOutcome.CACHED:
            cached += 1
            if game_id is not None:
                known_game_ids.add(game_id)
        elif outcome is QueuedRomOutcome.NO_MATCH:
            no_match += 1
        report(rom, outcome, game_id, message)


def cache_queued_rom(
    storage: Storage,
    config_data: dict,
    credentials: dict,
    user_agent: str,
    rom: QueuedRom,
    local: LocalGameIdAnswer,
    known_game_ids: set[int],
) -> tuple[QueuedRomOutcome, int | None, str]:
    game_id = local.game_id
    used_hash = local.hash_value
    if game_id is None:
        for hash_value in rom.hashes:
            try:
                candidate_game_id = fetch_game_id(
                    hash_value, credentials, user_agent, config_data, storage
                )
            except urllib.error.HTTPError as exc:
                outcome = (
                    QueuedRomOutcome.AUTH_REJECTED
                    if exc.code in (401, 403)
                    else QueuedRomOutcome.FAILED
                )
                return outcome, None, f"Game lookup failed: {exc}"
            except Exception as exc:
                return QueuedRomOutcome.FAILED, None, f"Game lookup failed: {exc}"
            if candidate_game_id is None:
                continue
            game_id = candidate_game_id
            used_hash = hash_value
            break
    if game_id is None:
        return QueuedRomOutcome.NO_MATCH, None, "No RetroAchievements match"

    persist_game_id_aliases(storage, rom.hashes, used_hash, game_id)
    if game_id in known_game_ids:
        remember_source_rom_path(storage, game_id, credentials["user"], rom.source_rom_path)
        return QueuedRomOutcome.ALREADY_CACHED, game_id, ""

    try:
        with images_downloaded_inline():
            cache_game(
                game_id,
                used_hash,
                credentials,
                proxy_user_agent(user_agent),
                storage,
                config_data,
                cache_images=image_caching_enabled(config_data),
                source_rom_path=rom.source_rom_path,
            )
    except CacheGameAuthError as exc:
        return QueuedRomOutcome.AUTH_REJECTED, game_id, f"Caching failed: {exc}"
    except Exception as exc:
        return QueuedRomOutcome.FAILED, game_id, f"Caching failed: {exc}"

    patch_entry = storage.get_cache(cache_keys.patch(game_id, credentials["user"]))
    if patch_entry is None:
        return QueuedRomOutcome.FAILED, game_id, "Caching failed: patch data was not stored"
    if rom.source_rom_path and patch_entry.get("sourceRomPath") != rom.source_rom_path:
        remember_source_rom_path(storage, game_id, credentials["user"], rom.source_rom_path)
    if not image_caching_enabled(config_data):
        cache_game_icon(game_id, patch_entry["responseBody"], proxy_user_agent(user_agent))
    return QueuedRomOutcome.CACHED, game_id, ""


def cache_game_icon(game_id: int, patch_body: str, user_agent: str) -> None:
    """Saves the cover the menu shows even where badge images are not cached (Onion): fetching
    it here, while the batch runs anyway, keeps the download off the menu's single core."""
    try:
        patch_data = json.loads(patch_body).get("PatchData") or {}
    except Exception:
        return
    image_path = extract_image_path(patch_data.get("ImageIcon") or "")
    if image_path is None or resolve_cached_static_asset(image_path) is not None:
        return
    download_static_image(f"{RA_MEDIA_HOST}{image_path}", image_path, user_agent, game_id)


def window_progress_total(cached_before: int, queued_including_current: int, games_left: int) -> int:
    """Games this drain can still cache in the current window, counting the one in progress:
    bounded by what is queued and by the games left in the budget."""
    return cached_before + max(1, min(queued_including_current, games_left))


def record_failed_attempt(storage: Storage, rom: QueuedRom) -> None:
    retry = rom.after_failed_attempt()
    if retry is None:
        LOGGER.warning(
            "Cache queue dropped %s after %d failed attempts",
            rom.label,
            cache_queue.CACHE_QUEUE_MAX_ATTEMPTS,
        )
        cache_queue.remove(storage, rom)
    else:
        cache_queue.update(storage, retry)


def remember_source_rom_path(
    storage: Storage, game_id: int, user: str, path: str | Path | None
) -> None:
    if path is None:
        return
    patch_entry = storage.get_cache(cache_keys.patch(game_id, user))
    if patch_entry is not None:
        storage.upsert_cache(
            cache_keys.patch(game_id, user),
            patch_entry["responseBody"],
            source_rom_path=normalize_cached_rom_path(path),
        )


def persist_game_id_aliases(
    storage: Storage,
    hash_candidates: list[str],
    used_hash: str | None,
    game_id: int,
) -> None:
    response_body = json.dumps({"GameID": game_id}, separators=(",", ":"))
    for hash_value in hash_candidates:
        if hash_value == used_hash:
            continue
        storage.upsert_cache(cache_keys.game_id(hash_value), response_body)


def remove_cached_game(storage: Storage, game_id: int) -> None:
    storage.delete_cache_by_prefix(cache_keys.patch_prefix(game_id))
    storage.delete_cache_by_prefix(f"{cache_keys.PREFIX_UNLOCKS}{game_id}:")
    storage.delete_cache_by_prefix(f"{cache_keys.PREFIX_STARTSESSION}{game_id}:")
    storage.delete_cache(cache_keys.last_played(game_id))
    remove_achievementsets_for_game(storage, game_id)
    remove_gameid_aliases_for_game(storage, game_id)
    delete_cached_images_for_game(game_id)


def remove_achievementsets_for_game(storage: Storage, game_id: int) -> None:
    for cache_key in achievementsets_keys_for_game(storage, game_id):
        storage.delete_cache(cache_key)


def remove_gameid_aliases_for_game(storage: Storage, game_id: int) -> None:
    for entry in storage.iter_cache_by_prefix(cache_keys.PREFIX_GAMEID):
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        if payload.get("GameID") != game_id:
            continue

        cache_key = entry.get("cacheKey")
        if isinstance(cache_key, str) and cache_key:
            storage.delete_cache(cache_key)


def cached_unlock_count(storage: Storage, game_id: int) -> int | None:
    unlock_ids = merged_unlock_ids(storage, game_id)
    if unlock_ids is None:
        return None
    return len(unlock_ids)


def cached_unlock_counts(storage: Storage) -> dict[int, int]:
    pending_awards = storage.get_pending_awards()
    achievement_game_ids = find_achievement_game_ids(
        storage, pending_unlock_achievement_ids(pending_awards)
    )
    counts: dict[int, int] = {}

    for entry in storage.iter_cache_by_prefix(cache_keys.PREFIX_UNLOCKS):
        game_id = parse_game_id_from_unlock_key(entry.get("cacheKey", ""))
        user = parse_user_from_unlocks_key(entry.get("cacheKey", ""))
        if game_id is None or user is None:
            continue

        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        value = payload.get("UserUnlocks")
        if not isinstance(value, list):
            continue

        merged_ids = merge_start_session_unlock_ids(
            cached_unlock_ids=[item for item in value if isinstance(item, int)],
            pending_awards=pending_awards,
            achievement_game_ids=achievement_game_ids,
            game_id=game_id,
            user=user,
        )
        counts[game_id] = len(merged_ids)

    for entry in storage.iter_cache_by_prefix(cache_keys.PREFIX_STARTSESSION):
        game_id = parse_game_id_from_start_session_key(entry.get("cacheKey", ""))
        user = parse_user_from_start_session_key(entry.get("cacheKey", ""))
        if game_id is None or user is None or game_id in counts:
            continue

        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        cached_unlock_ids = [
            int(item.get("ID", 0))
            for item in payload.get("Unlocks", [])
            if isinstance(item, dict) and int(item.get("ID", 0) or 0) > 0
        ]
        merged_ids = merge_start_session_unlock_ids(
            cached_unlock_ids=cached_unlock_ids,
            pending_awards=pending_awards,
            achievement_game_ids=achievement_game_ids,
            game_id=game_id,
            user=user,
        )
        counts[game_id] = len(merged_ids)

    return counts


def cached_unlock_titles(storage: Storage, game_id: int) -> list[str]:
    unlock_ids = merged_unlock_ids(storage, game_id)
    if unlock_ids is None:
        return []

    title_by_id = {
        achievement_id: achievement.get("Title")
        for achievement_id, achievement in cached_achievements_by_id(
            storage, game_id
        ).items()
        if isinstance(achievement.get("Title"), str)
    }

    titles = [
        title_by_id[achievement_id]
        for achievement_id in unlock_ids
        if achievement_id in title_by_id
    ]
    return titles


def merged_unlock_ids(storage: Storage, game_id: int) -> list[int] | None:
    cached_unlock_ids: list[int] | None = None
    unlock_user: str | None = None
    for entry in storage.iter_cache_by_prefix(f"{cache_keys.PREFIX_UNLOCKS}{game_id}:"):
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        value = payload.get("UserUnlocks")
        if not isinstance(value, list):
            continue

        cached_unlock_ids = filter_warning_achievement_ids(
            [item for item in value if isinstance(item, int)]
        )
        unlock_user = parse_user_from_unlocks_key(entry.get("cacheKey", ""))
        break

    if unlock_user is None:
        start_session_entry = storage.get_cache_by_prefix(
            f"{cache_keys.PREFIX_STARTSESSION}{game_id}:"
        )
        if start_session_entry is None:
            return None

        unlock_user = parse_user_from_start_session_key(
            start_session_entry.get("cacheKey", "")
        )
        if unlock_user is None:
            return None

        try:
            payload = json.loads(start_session_entry["responseBody"])
        except Exception:
            payload = {}

        cached_unlock_ids = filter_warning_achievement_ids([
            int(item.get("ID", 0))
            for item in payload.get("Unlocks", [])
            if isinstance(item, dict) and int(item.get("ID", 0) or 0) > 0
        ])

    pending_awards = storage.get_pending_awards()
    return merge_start_session_unlock_ids(
        cached_unlock_ids=cached_unlock_ids or [],
        pending_awards=pending_awards,
        achievement_game_ids=find_achievement_game_ids(
            storage,
            pending_unlock_achievement_ids(pending_awards, unlock_user),
            likely_game_id=game_id,
        ),
        game_id=game_id,
        user=unlock_user,
    )


def parse_user_from_unlocks_key(cache_key: str) -> str | None:
    if not cache_key.startswith(cache_keys.PREFIX_UNLOCKS):
        return None

    parts = cache_key.split(":")
    if len(parts) != 4:
        return None

    user = parts[2].strip()
    return user or None


def parse_game_id_from_unlock_key(cache_key: str) -> int | None:
    if not cache_key.startswith(cache_keys.PREFIX_UNLOCKS):
        return None

    parts = cache_key.split(":")
    if len(parts) != 4:
        return None

    game_id = int(parts[1]) if parts[1].isdigit() else 0
    return game_id if game_id > 0 else None


def parse_user_from_start_session_key(cache_key: str) -> str | None:
    if not cache_key.startswith(cache_keys.PREFIX_STARTSESSION):
        return None

    parts = cache_key.split(":")
    if len(parts) != 4:
        return None

    user = parts[2].strip()
    return user or None


def parse_game_id_from_start_session_key(cache_key: str) -> int | None:
    if not cache_key.startswith(cache_keys.PREFIX_STARTSESSION):
        return None

    parts = cache_key.split(":")
    if len(parts) != 4:
        return None

    game_id = int(parts[1]) if parts[1].isdigit() else 0
    return game_id if game_id > 0 else None


def cached_unlock_badge_paths(storage: Storage, game_id: int) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for achievement in cached_achievements_by_id(storage, game_id).values():
        if not isinstance(achievement, dict):
            continue
        title = achievement.get("Title")
        if not isinstance(title, str) or not title:
            continue
        badge_name = achievement.get("BadgeName")
        if not isinstance(badge_name, str) or not badge_name:
            continue
        badge_path = resolve_cached_static_asset(f"/Badge/{badge_name}.png")
        if badge_path is not None:
            result[title] = badge_path
    return result


def cached_achievements_by_id(storage: Storage, game_id: int) -> dict[int, dict]:
    achievements_by_id: dict[int, dict] = {}
    merge_cached_achievement_entries(
        achievements_by_id,
        storage.iter_cache_by_prefix(cache_keys.patch_prefix(game_id)),
        lambda payload: payload.get("PatchData", {}).get("Achievements"),
    )
    merge_cached_achievement_entries(
        achievements_by_id,
        (
            entry
            for entry in map(storage.get_cache, achievementsets_keys_for_game(storage, game_id))
            if entry is not None
        ),
        lambda payload: achievementsets_payload_achievements(payload, game_id),
    )
    return achievements_by_id


def merge_cached_achievement_entries(
    achievements_by_id: dict[int, dict], entries: Iterable[dict], select_achievements
) -> None:
    for entry in entries:
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        achievements = select_achievements(payload)
        values = (
            achievements.values() if isinstance(achievements, dict) else achievements
        )
        if not isinstance(values, list) and not hasattr(values, "__iter__"):
            continue

        for achievement in values:
            if not isinstance(achievement, dict):
                continue
            achievement_id = achievement.get("ID")
            if not isinstance(achievement_id, int) or achievement_id <= 0:
                continue

            existing = achievements_by_id.get(achievement_id, {})
            merged = dict(achievement)
            merged.update(existing)
            achievements_by_id[achievement_id] = merged


def achievementsets_payload_achievements(
    payload: dict, game_id: int
) -> list[dict] | dict | None:
    if payload.get("GameId") != game_id:
        return None

    direct_achievements = payload.get("Achievements")
    if isinstance(direct_achievements, (list, dict)):
        return direct_achievements

    sets = payload.get("Sets")
    if not isinstance(sets, list):
        return None

    achievements: list[dict] = []
    for achievement_set in sets:
        if not isinstance(achievement_set, dict):
            continue

        set_achievements = achievement_set.get("Achievements")
        values = (
            set_achievements.values()
            if isinstance(set_achievements, dict)
            else set_achievements
        )
        if not isinstance(values, list) and not hasattr(values, "__iter__"):
            continue

        for achievement in values:
            if isinstance(achievement, dict):
                achievements.append(achievement)

    return achievements


def clear_cached_games(storage: Storage) -> None:
    storage.clear_cache()
    clear_all_cached_images()


def ensure_game_preview(
    game: CachedGameEntry,
    storage: Storage,
    config_data: dict,
) -> Path | None:
    if not game.image_url:
        return None

    image_path = extract_image_path(game.image_url)
    if image_path:
        cached = resolve_cached_static_asset(image_path)
        if cached is not None:
            return cached

    user_agent = self_user_agent()

    if image_path:
        media_url = f"{RA_MEDIA_HOST}{image_path}"
        schedule_image_download(media_url, image_path, user_agent)

    return None


def normalize_preview_url(image_path: str | None) -> str | None:
    if not image_path:
        return None
    return urljoin(upstream_host({}) + "/", image_path.lstrip("/"))
