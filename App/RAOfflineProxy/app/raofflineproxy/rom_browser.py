from __future__ import annotations

import json
import logging
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urljoin

from . import cache_keys
from .auth import resolve_credentials
from .config import FALLBACK_USER_AGENT, RA_MEDIA_HOST, image_caching_enabled, upstream_host
from .image_cache import (
    STATIC_DIR,
    clear_all_cached_images,
    delete_cached_images_for_game,
    extract_image_path,
    game_image_dir,
    resolve_cached_static_asset,
    schedule_image_download,
)
from .network import build_api_url, http_get
from .rom_cache import (
    build_achievement_game_ids,
    cache_game,
    filter_warning_achievement_ids,
    merge_start_session_unlock_ids,
    merged_unlock_ids as merged_unlock_ids_for_user,
)
from .rom_hashing import (
    hash_7z_entry_candidates,
    hash_rom,
    hash_rom_candidates,
    hash_rom_candidates_result,
    list_7z_entries,
    supported_rom_extensions,
)
from .storage import Storage
from .utils import proxy_user_agent, self_user_agent

LOGGER = logging.getLogger("raofflineproxy")
SUPPORTED_ROM_EXTENSIONS = supported_rom_extensions()
SUPPORTED_ARCHIVE_EXTENSIONS = {".zip", ".7z"}
# Archives the stdlib can open. A .7z goes through the native hasher instead,
# which bundles a 7z reader (third_party/lzma-sdk), so it never reaches zipfile.
ZIP_READABLE_ARCHIVE_EXTENSIONS = {".zip"}
EXCLUDED_BROWSER_DIR_NAMES = {"Imgs"}
MAX_CACHED_GAMES = 100
MAX_SCAN_ENTRIES = 5000
MAX_SCAN_DEPTH = 12


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
        for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH)
        if isinstance(entry.get("sourceRomPath"), str)
        and entry["sourceRomPath"].strip()
    }


def list_cached_games(storage: Storage) -> list[CachedGameEntry]:
    games: dict[int, CachedGameEntry] = {}
    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH):
        game_id = cache_keys.parse_game_id_from_patch_key(entry["cacheKey"])
        if game_id is None:
            continue
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        patch_data = payload.get("PatchData") or {}
        title = patch_data.get("Title") or f"Game {game_id}"
        image_path = patch_data.get("ImageIcon") or patch_data.get("ImageBoxArt")
        games[game_id] = CachedGameEntry(
            game_id=game_id,
            title=title,
            image_url=normalize_preview_url(image_path),
        )

    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS):
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        game_id = payload.get("GameId")
        if not isinstance(game_id, int) or game_id <= 0:
            continue

        title = payload.get("Title") or f"Game {game_id}"
        image_path = payload.get("ImageIcon") or payload.get("ImageIconUrl")
        if game_id not in games:
            games[game_id] = CachedGameEntry(
                game_id=game_id,
                title=title,
                image_url=normalize_preview_url(image_path),
            )

    return sorted(games.values(), key=lambda game: game.title.lower())


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
    cached_game_ids = {game.game_id for game in list_cached_games(storage)}
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
        cached_game_ids = {game.game_id for game in list_cached_games(storage)}

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


def fetch_game_id(
    hash_value: str,
    credentials: dict,
    user_agent: str,
    config_data: dict,
    storage: Storage,
) -> int | None:
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
    game_id = payload.get("GameID")
    if not isinstance(game_id, int) or game_id <= 0:
        return None

    storage.upsert_cache(cache_keys.game_id(hash_value), response_body)
    return int(game_id)


def add_rom_to_cache(path: Path, storage: Storage, config_data: dict) -> AddRomResult:
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

    game_id = None
    used_hash = None
    for hash_value in hash_candidates:
        try:
            candidate_game_id = fetch_game_id(
                hash_value, credentials, user_agent, config_data, storage
            )
        except Exception as exc:
            return AddRomResult(False, f"Game lookup failed: {exc}")

        if candidate_game_id is None:
            continue

        game_id = candidate_game_id
        used_hash = hash_value
        break

    if game_id is None:
        return AddRomResult(False, "No RetroAchievements match")

    cached_games = list_cached_games(storage)
    if len(cached_games) >= MAX_CACHED_GAMES and not any(
        game.game_id == game_id for game in cached_games
    ):
        return AddRomResult(
            False, f"Cache limit reached: {MAX_CACHED_GAMES} / {MAX_CACHED_GAMES}"
        )

    persist_game_id_aliases(storage, hash_candidates, used_hash, game_id)

    try:
        cache_game(
            game_id,
            used_hash,
            credentials,
            proxy_user_agent(user_agent),
            storage,
            config_data,
            cache_images=image_caching_enabled(config_data),
        )
    except Exception as exc:
        return AddRomResult(False, f"Caching failed: {exc}")

    patch_entry = storage.get_cache(cache_keys.patch(game_id, credentials["user"]))
    if patch_entry is not None:
        storage.upsert_cache(
            cache_keys.patch(game_id, credentials["user"]),
            patch_entry["responseBody"],
            source_rom_path=normalize_cached_rom_path(path),
        )

    game = next(
        (entry for entry in list_cached_games(storage) if entry.game_id == game_id),
        None,
    )
    if game is None:
        return AddRomResult(False, "Caching failed: patch data was not stored")

    return AddRomResult(True, f"Cached {game.title}", game=game)


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
    remove_achievementsets_for_game(storage, game_id)
    remove_gameid_aliases_for_game(storage, game_id)
    delete_cached_images_for_game(game_id)


def remove_achievementsets_for_game(storage: Storage, game_id: int) -> None:
    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS):
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        if payload.get("GameId") != game_id:
            continue

        cache_key = entry.get("cacheKey")
        if isinstance(cache_key, str) and cache_key:
            storage.delete_cache(cache_key)


def remove_gameid_aliases_for_game(storage: Storage, game_id: int) -> None:
    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_GAMEID):
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
    achievement_game_ids = build_achievement_game_ids(
        storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH),
        storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS),
    )
    pending_awards = storage.get_pending_awards()
    counts: dict[int, int] = {}

    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_UNLOCKS):
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

    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_STARTSESSION):
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
    for entry in storage.get_all_cache_by_prefix(
        f"{cache_keys.PREFIX_UNLOCKS}{game_id}:"
    ):
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

    achievement_game_ids = build_achievement_game_ids(
        storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH),
        storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS),
    )
    return merge_start_session_unlock_ids(
        cached_unlock_ids=cached_unlock_ids or [],
        pending_awards=storage.get_pending_awards(),
        achievement_game_ids=achievement_game_ids,
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
        badge_path = STATIC_DIR / "Badge" / f"{badge_name}.png"
        if badge_path.exists():
            result[title] = badge_path
    return result


def cached_achievements_by_id(storage: Storage, game_id: int) -> dict[int, dict]:
    achievements_by_id: dict[int, dict] = {}
    merge_cached_achievement_entries(
        achievements_by_id,
        storage.get_all_cache_by_prefix(cache_keys.patch_prefix(game_id)),
        lambda payload: payload.get("PatchData", {}).get("Achievements"),
    )
    merge_cached_achievement_entries(
        achievements_by_id,
        storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS),
        lambda payload: achievementsets_payload_achievements(payload, game_id),
    )
    return achievements_by_id


def merge_cached_achievement_entries(
    achievements_by_id: dict[int, dict], entries: list[dict], select_achievements
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
