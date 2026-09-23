from __future__ import annotations

import json
import logging
import re
import time
from dataclasses import dataclass
from pathlib import Path

from .config import detect_dolphin_config_dir, detect_ppsspp_ini
from .network import RA_MIN_REQUEST_INTERVAL_SECONDS, apply_scan_batch_cooldown
from .platform import read_retroarch_cfg_values, resolve_retroarch_cfg
from .rom_browser import (
    MAX_CACHED_GAMES,
    add_rom_to_cache,
    list_cached_games,
    list_scannable_files_recursive,
    load_cached_rom_paths,
    normalize_cached_rom_path,
)
from .storage import Storage

LOGGER = logging.getLogger("raofflineproxy")

SMART_CACHE_LIMIT = MAX_CACHED_GAMES
SMART_CACHE_DELAY_SECONDS = RA_MIN_REQUEST_INTERVAL_SECONDS
MUOS_HISTORY_DIR = Path("/run/muos/storage/info/history")
DOLPHIN_RECENT_WINDOW_SECONDS = 60 * 24 * 60 * 60
DOLPHIN_GCI_CODE_REGEX = re.compile(r"^\d{2}-([A-Za-z0-9]{4})-.*\.gci$", re.IGNORECASE)
DOLPHIN_WII_TITLE_ID_REGEX = re.compile(r"^[0-9A-Fa-f]{8}$")
DOLPHIN_WII_DISC_TITLE_HIGH_ID = "00010000"
# WiiWare/Virtual Console/DLC channels installed from a .wad live under this
# NAND high ID instead of the disc-title one above.
DOLPHIN_WII_WAD_TITLE_HIGH_ID = "00010001"
DOLPHIN_DISC_ROM_SUFFIXES = (".rvz", ".wia", ".iso", ".gcm")
# .wad (WAD installer package) has no disc header; its game code lives in the
# TMD's title ID instead. Only the near-universal RSA-2048 signature type is
# handled — every commercial Wii TMD/ticket uses it.
DOLPHIN_WAD_RSA2048_SIG_TYPE = 0x10001
DOLPHIN_WAD_RSA2048_SIG_BLOCK_SIZE = 0x140
DOLPHIN_WAD_TMD_TITLE_ID_OFFSET = 0x18C
# WIA/RVZ share the same header layout: 0x48-byte WIAHeader1 followed by
# WIAHeader2, whose disc_type/compression_type/compression_level/chunk_size
# (4 x u32 = 16 bytes) precede the embedded 0x80-byte original disc header.
DOLPHIN_WIA_RVZ_MAGICS = (b"WIA\x01", b"RVZ\x01")
DOLPHIN_WIA_RVZ_DISC_HEADER_OFFSET = 0x48 + 16


@dataclass
class SmartCacheStatus:
    found_history: bool
    total_candidates: int
    reason: str | None = None
    history_path: str | None = None


@dataclass
class SmartCacheProgress:
    scanned: int
    total: int
    cached: int
    current_label: str


@dataclass
class SmartCacheResult:
    scanned: int
    total: int
    cached: int
    skipped: int
    limit_reached: bool


def should_offer_smart_cache(
    storage: Storage,
    config_data: dict,
    *,
    is_online: bool,
    has_credentials: bool,
) -> SmartCacheStatus:
    if not is_online or not has_credentials:
        return SmartCacheStatus(
            found_history=False,
            total_candidates=0,
            reason="offline" if not is_online else "missing_credentials",
        )

    history_source = _find_history_source(config_data)
    if history_source is None:
        return SmartCacheStatus(
            found_history=False,
            total_candidates=0,
            reason="content_history_missing",
        )

    cached_rom_paths = load_cached_rom_paths(storage)
    all_paths = load_content_history_paths(config_data)
    paths = [
        path
        for path in all_paths
        if normalize_cached_rom_path(path) not in cached_rom_paths
    ]
    total_candidates = min(len(paths), SMART_CACHE_LIMIT)

    if total_candidates == 0:
        return SmartCacheStatus(
            found_history=False,
            total_candidates=0,
            reason=(
                "all_history_entries_cached"
                if all_paths and len(paths) == 0
                else "no_valid_history_entries"
            ),
            history_path=str(history_source),
        )

    return SmartCacheStatus(
        found_history=total_candidates > 0,
        total_candidates=total_candidates,
        history_path=str(history_source),
    )


def run_smart_cache(
    storage: Storage,
    config_data: dict,
    limit: int = SMART_CACHE_LIMIT,
    should_abort=None,
    on_progress=None,
) -> SmartCacheResult:
    cached_rom_paths = load_cached_rom_paths(storage)
    return run_cache_paths(
        storage,
        config_data,
        [
            path
            for path in load_content_history_paths(config_data)
            if normalize_cached_rom_path(path) not in cached_rom_paths
        ],
        limit=limit,
        should_abort=should_abort,
        on_progress=on_progress,
    )


def run_folder_cache(
    storage: Storage,
    config_data: dict,
    current_dir: Path,
    paths: list[Path] | None = None,
    should_abort=None,
    on_progress=None,
) -> SmartCacheResult:
    return run_cache_paths(
        storage,
        config_data,
        list_scannable_files_recursive(current_dir) if paths is None else paths,
        limit=MAX_CACHED_GAMES,
        should_abort=should_abort,
        on_progress=on_progress,
    )


def run_cache_paths(
    storage: Storage,
    config_data: dict,
    paths: list[Path],
    *,
    limit: int,
    should_abort=None,
    on_progress=None,
) -> SmartCacheResult:
    total = min(len(paths), limit, MAX_CACHED_GAMES)
    cached = 0
    scanned = 0

    for path in paths[:total]:
        if should_abort is not None and should_abort():
            break

        if len(list_cached_games(storage)) >= MAX_CACHED_GAMES or cached >= limit:
            break

        scanned += 1

        if on_progress is not None:
            on_progress(
                SmartCacheProgress(
                    scanned=scanned,
                    total=total,
                    cached=cached,
                    current_label=path.name,
                )
            )

        result = add_rom_to_cache(path, storage, config_data)
        if result.success:
            cached += 1

        if should_abort is not None and should_abort():
            break

        if scanned < total and not apply_scan_batch_cooldown(scanned):
            time.sleep(SMART_CACHE_DELAY_SECONDS)

    skipped = max(0, scanned - cached)
    limit_reached = (
        cached >= limit or len(list_cached_games(storage)) >= MAX_CACHED_GAMES
    )
    return SmartCacheResult(
        scanned=scanned,
        total=total,
        cached=cached,
        skipped=skipped,
        limit_reached=limit_reached,
    )


def load_content_history_paths(config_data: dict) -> list[Path]:
    if MUOS_HISTORY_DIR.exists():
        paths = _load_muos_history_paths()
    else:
        paths = _load_retroarch_history_paths(config_data)

    seen = {str(path) for path in paths}
    for extra_path in (
        *_load_ppsspp_recent_paths(config_data),
        *_load_dolphin_recent_paths(config_data),
    ):
        normalized = str(extra_path)
        if normalized in seen:
            continue
        seen.add(normalized)
        paths.append(extra_path)

    return paths

def _load_retroarch_history_paths(config_data: dict) -> list[Path]:
    history_path = find_content_history_lpl(config_data)
    if history_path is None or not history_path.exists():
        return []

    try:
        payload = json.loads(history_path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return []

    items = payload.get("items")
    if not isinstance(items, list):
        return []

    unique_paths: list[Path] = []
    seen: set[str] = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        raw_path = item.get("path")
        if not isinstance(raw_path, str) or not raw_path.strip():
            continue

        path = Path(raw_path).expanduser()
        normalized = str(path)
        if normalized in seen or not path.exists() or not path.is_file():
            continue
        seen.add(normalized)
        unique_paths.append(path)

    return unique_paths


def _find_history_source(config_data: dict) -> Path | None:
    """Returns the muOS history dir, content_history.lpl, ppsspp.ini, or Dolphin.ini, whichever is available."""
    if MUOS_HISTORY_DIR.exists():
        return MUOS_HISTORY_DIR

    retroarch_source = find_content_history_lpl(config_data)
    if retroarch_source is not None:
        return retroarch_source

    ppsspp_ini = detect_ppsspp_ini(config_data)
    if ppsspp_ini is not None and Path(ppsspp_ini).exists():
        return Path(ppsspp_ini)

    dolphin_ini = _dolphin_ini_path(config_data)
    if dolphin_ini is not None and dolphin_ini.exists():
        return dolphin_ini

    return None


def _load_ppsspp_recent_paths(config_data: dict) -> list[Path]:
    ini_path = detect_ppsspp_ini(config_data)
    if ini_path is None:
        return []

    target = Path(ini_path)
    if not target.exists():
        return []

    try:
        content = target.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []

    return parse_ppsspp_recent_paths(content)


def parse_ppsspp_recent_paths(content: str) -> list[Path]:
    """Read ROM paths from the [Recent] section of ppsspp.ini.

    Entries are keyed FileName0, FileName1, ... with 0 being most recent;
    sort by that index the same way PPSSPP's own recent list is ordered.
    """
    in_recent = False
    seen: set[str] = set()
    candidates: list[tuple[int, Path]] = []

    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_recent = stripped == "[Recent]"
            continue
        if not in_recent:
            continue

        separator = stripped.find("=")
        if separator == -1:
            continue
        key = stripped[:separator].strip()
        if not key.startswith("FileName"):
            continue
        index_text = key[len("FileName") :]
        if not index_text.isdigit():
            continue

        raw_path = stripped[separator + 1 :].strip()
        if not raw_path:
            continue

        path = Path(raw_path).expanduser()
        normalized = str(path)
        if normalized in seen or not path.exists() or not path.is_file():
            continue
        seen.add(normalized)
        candidates.append((int(index_text), path))

    candidates.sort(key=lambda item: item[0])
    return [path for _, path in candidates]


def _dolphin_ini_path(config_data: dict) -> Path | None:
    config_dir = detect_dolphin_config_dir(config_data)
    if config_dir is None:
        return None
    return Path(config_dir) / "Dolphin.ini"


def _load_dolphin_recent_paths(config_data: dict) -> list[Path]:
    """Infer recently played GameCube/Wii games from save-file mtimes.

    Dolphin (desktop/standalone) has no "recent files" list of its own here —
    ROCKNIX launches each game headlessly via -e, which doesn't go through the
    Qt frontend's recent-files tracking. Instead, mirror the Android approach:
    find GameCube memory-card saves (.gci) and Wii NAND disc-title save
    folders modified within the last 60 days, and match their embedded game
    codes against a library built by reading the disc header of ROM files
    under the configured ISO search paths.
    """
    config_dir = detect_dolphin_config_dir(config_data)
    if config_dir is None:
        return []

    config_dir_path = Path(config_dir)
    ini_path = config_dir_path / "Dolphin.ini"
    if not ini_path.exists():
        return []

    try:
        ini_content = ini_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []

    # ISOPath0.. / ISOPaths live under [General]; the memory-card / GCI
    # folder paths live under [Core].
    general_values = _read_dolphin_ini_section(ini_content, "[General]")
    core_values = _read_dolphin_ini_section(ini_content, "[Core]")

    recent_codes: dict[str, float] = {}
    for key in ("GCIFolderAPath", "GCIFolderBPath"):
        gci_dir = core_values.get(key, "").strip()
        if gci_dir:
            _merge_recent_codes(recent_codes, _scan_dolphin_gci_codes(Path(gci_dir)))

    wii_title_dir = config_dir_path / "Wii" / "title" / DOLPHIN_WII_DISC_TITLE_HIGH_ID
    _merge_recent_codes(recent_codes, _scan_dolphin_wii_title_codes(wii_title_dir))

    wii_wad_title_dir = config_dir_path / "Wii" / "title" / DOLPHIN_WII_WAD_TITLE_HIGH_ID
    _merge_recent_codes(recent_codes, _scan_dolphin_wii_title_codes(wii_wad_title_dir))

    if not recent_codes:
        return []

    cutoff = time.time() - DOLPHIN_RECENT_WINDOW_SECONDS
    recent_codes = {
        code: mtime for code, mtime in recent_codes.items() if mtime >= cutoff
    }
    if not recent_codes:
        return []

    iso_dirs = _dolphin_iso_search_dirs(general_values)
    if not iso_dirs:
        return []

    library = _scan_dolphin_disc_library(iso_dirs)
    for code, path in _scan_dolphin_wad_library(iso_dirs).items():
        library.setdefault(code, path)
    if not library:
        return []

    ordered_codes = sorted(recent_codes.items(), key=lambda item: item[1], reverse=True)
    seen: set[str] = set()
    matched: list[Path] = []
    for code, _mtime in ordered_codes:
        path = library.get(code)
        if path is None:
            continue
        normalized = str(path)
        if normalized in seen:
            continue
        seen.add(normalized)
        matched.append(path)

    return matched


def _read_dolphin_ini_section(content: str, section: str) -> dict[str, str]:
    values: dict[str, str] = {}
    in_section = False
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_section = stripped == section
            continue
        if not in_section:
            continue
        separator = stripped.find("=")
        if separator == -1:
            continue
        key = stripped[:separator].strip()
        value = stripped[separator + 1 :].strip()
        values[key] = value
    return values


def _dolphin_iso_search_dirs(general_values: dict[str, str]) -> list[Path]:
    try:
        count = int(general_values.get("ISOPaths", "0"))
    except ValueError:
        count = 0

    dirs: list[Path] = []
    for index in range(count):
        raw = general_values.get(f"ISOPath{index}", "").strip()
        if not raw:
            continue
        candidate = Path(raw).expanduser()
        if candidate.is_dir():
            dirs.append(candidate)
    return dirs


def _merge_recent_codes(target: dict[str, float], source: dict[str, float]) -> None:
    for code, mtime in source.items():
        if mtime > target.get(code, float("-inf")):
            target[code] = mtime


def _scan_dolphin_gci_codes(root: Path) -> dict[str, float]:
    if not root.is_dir():
        return {}

    codes: dict[str, float] = {}
    for path in root.rglob("*.gci"):
        if not path.is_file():
            continue
        match = DOLPHIN_GCI_CODE_REGEX.match(path.name)
        if match is None:
            continue
        code = match.group(1).upper()
        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue
        if mtime > codes.get(code, float("-inf")):
            codes[code] = mtime
    return codes


def _scan_dolphin_wii_title_codes(root: Path) -> dict[str, float]:
    if not root.is_dir():
        return {}

    codes: dict[str, float] = {}
    try:
        entries = list(root.iterdir())
    except OSError:
        return {}

    for entry in entries:
        if not entry.is_dir() or not DOLPHIN_WII_TITLE_ID_REGEX.match(entry.name):
            continue
        code = _decode_wii_title_id_to_game_code(entry.name)
        if code is None:
            continue
        try:
            mtime = entry.stat().st_mtime
        except OSError:
            continue
        if mtime > codes.get(code, float("-inf")):
            codes[code] = mtime
    return codes


def _decode_wii_title_id_to_game_code(title_id_suffix: str) -> str | None:
    try:
        raw = bytes.fromhex(title_id_suffix)
    except ValueError:
        return None
    if len(raw) != 4 or not all(0x20 <= byte <= 0x7E for byte in raw):
        return None
    return raw.decode("ascii").upper()


def _scan_dolphin_disc_library(iso_dirs: list[Path]) -> dict[str, Path]:
    library: dict[str, Path] = {}
    for iso_dir in iso_dirs:
        for path in iso_dir.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in DOLPHIN_DISC_ROM_SUFFIXES:
                continue
            code = _read_dolphin_disc_code(path)
            if code is None or code in library:
                continue
            library[code] = path
    return library


def _read_dolphin_disc_code(path: Path) -> str | None:
    try:
        with path.open("rb") as handle:
            header = handle.read(DOLPHIN_WIA_RVZ_DISC_HEADER_OFFSET + 6)
    except OSError:
        return None

    if len(header) >= 4 and header[:4] in DOLPHIN_WIA_RVZ_MAGICS:
        code_bytes = header[
            DOLPHIN_WIA_RVZ_DISC_HEADER_OFFSET : DOLPHIN_WIA_RVZ_DISC_HEADER_OFFSET + 6
        ]
    else:
        code_bytes = header[:6]

    if len(code_bytes) < 6:
        return None
    try:
        code = code_bytes.decode("ascii")
    except UnicodeDecodeError:
        return None
    if not code.isalnum() or not code.isupper():
        return None
    return code[:4]


def _scan_dolphin_wad_library(iso_dirs: list[Path]) -> dict[str, Path]:
    library: dict[str, Path] = {}
    for iso_dir in iso_dirs:
        for path in iso_dir.rglob("*.wad"):
            if not path.is_file():
                continue
            code = _read_wad_game_code(path)
            if code is None or code in library:
                continue
            library[code] = path
    return library


def _read_wad_game_code(path: Path) -> str | None:
    """Extracts the 4-char game code from a WAD's embedded TMD title ID.

    A WAD has no disc header (it's an installer package, not a disc image);
    the title ID lives in the TMD, whose offset depends on the sizes of the
    sections before it (cert chain, CRL, ticket), each padded to a 64-byte
    boundary. Only the near-universal RSA-2048 TMD signature type is handled.
    """
    try:
        with path.open("rb") as handle:
            header = handle.read(0x20)
            if len(header) < 0x20:
                return None
            cert_chain_size = int.from_bytes(header[0x08:0x0C], "big")
            crl_size = int.from_bytes(header[0x0C:0x10], "big")
            ticket_size = int.from_bytes(header[0x10:0x14], "big")

            cert_start = _align_up_64(0x20)
            crl_start = _align_up_64(cert_start + cert_chain_size)
            ticket_start = _align_up_64(crl_start + crl_size)
            tmd_start = _align_up_64(ticket_start + ticket_size)

            handle.seek(tmd_start)
            sig_type = int.from_bytes(handle.read(4), "big")
            if sig_type != DOLPHIN_WAD_RSA2048_SIG_TYPE:
                return None

            handle.seek(tmd_start + DOLPHIN_WAD_TMD_TITLE_ID_OFFSET)
            title_id = handle.read(8)
    except OSError:
        return None

    if len(title_id) != 8:
        return None
    return _decode_wii_title_id_to_game_code(title_id[4:8].hex())


def _align_up_64(value: int) -> int:
    return (value + 63) & ~63


def _load_muos_history_paths() -> list[Path]:
    """Read ROM paths from muOS per-game history cfg files in MUOS_HISTORY_DIR.

    Each .cfg file has three lines:
        line 1 — absolute path to the ROM file
        line 2 — platform/system name (e.g. "gba")
        line 3 — display name (no trailing newline)
    """
    unique_paths: list[Path] = []
    seen: set[str] = set()
    try:
        entries = sorted(MUOS_HISTORY_DIR.iterdir())
    except OSError:
        return []
    for cfg_file in entries:
        if not cfg_file.name.endswith(".cfg"):
            continue
        try:
            lines = cfg_file.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        if not lines:
            continue
        path = Path(lines[0].strip())
        normalized = str(path)
        if normalized in seen or not path.exists() or not path.is_file():
            continue
        seen.add(normalized)
        unique_paths.append(path)
    return unique_paths


def find_content_history_lpl(config_data: dict) -> Path | None:
    cfg_path = Path(resolve_retroarch_cfg(config_data))
    cfg_values = read_retroarch_cfg_values(cfg_path)

    candidates: list[Path] = []

    # Honour the explicit path RetroArch writes in its own config (e.g. muOS sets
    # content_history_path = "/opt/muos/share/emulator/retroarch/content_history.lpl").
    # RetroArch may store it relative to its home with a leading ~ (ROCKNIX uses
    # "~/playlists/builtin/content_history.lpl"), so expand it.
    explicit = cfg_values.get("content_history_path", "").strip().strip('"')
    if explicit and explicit != "default":
        candidates.append(Path(explicit).expanduser())

    # Derive from the playlist directory when set (also possibly ~-relative).
    playlist_dir = cfg_values.get("playlist_directory", "").strip().strip('"')
    if playlist_dir and playlist_dir != "default":
        playlist_base = Path(playlist_dir).expanduser()
        candidates.append(playlist_base / "content_history.lpl")
        candidates.append(playlist_base / "builtin" / "content_history.lpl")

    candidates += [
        cfg_path.parent / "content_history.lpl",
        cfg_path.parent / "playlists" / "content_history.lpl",
        cfg_path.parent / "playlists" / "builtin" / "content_history.lpl",
        cfg_path.parent.parent / "playlists" / "content_history.lpl",
        cfg_path.parent.parent.parent
        / "Saves"
        / "CurrentProfile"
        / "lists"
        / "content_history.lpl",
    ]

    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None
