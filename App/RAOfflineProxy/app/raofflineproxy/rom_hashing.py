from __future__ import annotations

"""RetroAchievements ROM hashing for the Linux proxy.

This is a thin ctypes binding over ``libraproxy_rchash`` — the shared library
built from rcheevos' ``rc_hash`` plus the vendored libchdr-backed CHD reader
(see ``third_party/rcheevos_glue``). All the per-format header-stripping,
sector cooking and disc parsing now lives in that one C library, shared with
the Android build, instead of being re-implemented here in Python.

``raproxy_hash_file(path, out_buffer, max_hashes)`` fills ``out_buffer`` with up
to ``max_hashes`` NUL-terminated 32-char hex hashes (33 bytes each) in rc_hash
iterator order and returns the count. We surface those as ordered candidates;
the caller tries each against the game-id lookup.

Note: ``.zip`` archives containing a single console ROM are extracted by the
caller (``rom_browser``) before hashing — rcheevos' own zip path is for
arcade/MAME images, not zipped cartridges. ``.cue`` and ``.m3u`` are resolved
natively by rc_hash from their path.

``.7z`` has no reader in rc_hash at all (it maps the extension to arcade, which
hashes the filename), so the same library exposes
``raproxy_7z_list_entries``/``raproxy_hash_7z_entry`` on top of the vendored
LZMA SDK. :func:`list_7z_entries` and :func:`hash_7z_entry_candidates` bind
those; ``rom_browser`` applies the same entry-selection rule it uses for zip.

``.rvz`` (Dolphin's compressed GameCube/Wii disc container) is the one format
rc_hash can't read directly — it expects a raw disc layout. Those go through
``raproxy_hash_disc_datasource`` instead: a random-access callback pair lets
rc_hash pull decompressed disc bytes from :mod:`rvz_datasource`, which does
the container parsing (ported from the Android app's Kotlin RVZ reader).
"""

import ctypes
import ctypes.util
import logging
import os
from dataclasses import dataclass
from pathlib import Path

from .rvz_datasource import FileReadSource, RvzDataSource

LOGGER = logging.getLogger("raofflineproxy")

_HASH_STRIDE = 33  # 32 hex chars + NUL, matching rc_hash's char[33]
_MAX_CANDIDATES = 8
_MAX_ARCHIVE_ENTRIES = 512
_ARCHIVE_NAMES_BYTES = 64 * 1024

_LIBRCHASH: ctypes.CDLL | None = None
_LIBRCHASH_ERROR: str | None = None

# raproxy_ds_size_fn / raproxy_ds_read_fn, matching rchash_glue.h.
_DS_SIZE_FN = ctypes.CFUNCTYPE(ctypes.c_longlong, ctypes.c_void_p)
_DS_READ_FN = ctypes.CFUNCTYPE(
    ctypes.c_int, ctypes.c_void_p, ctypes.c_longlong, ctypes.c_void_p, ctypes.c_int
)


@dataclass
class RomHashResult:
    candidates: list[str]
    error: str | None = None


def _candidate_library_paths() -> list[str | None]:
    names = ("libraproxy_rchash.so", "libraproxy_rchash.dylib")
    paths: list[str | None] = []

    override = os.environ.get("RAOFFLINEPROXY_RCHASH_LIB")
    if override:
        paths.append(override)

    # Bundled relative to this module. Distro bundles nest the package under
    # <base>/app/raofflineproxy/ with the native lib at <base>/lib/, so search
    # alongside the module and up at the bundle's lib/ directory.
    here = Path(__file__).resolve().parent
    module_dirs = (here, here / "lib", here.parent / "lib", here.parent.parent / "lib")
    for directory in module_dirs:
        for name in names:
            paths.append(str(directory / name))

    # Bare sonames let the dynamic linker resolve via LD_LIBRARY_PATH, which the
    # device launchers point at the bundle's lib/ regardless of install path.
    paths.extend(names)

    paths.append(ctypes.util.find_library("raproxy_rchash"))

    # Standard + device install locations (mirrors load paths used for libchdr).
    bases = (
        "/usr/lib",
        "/usr/local/lib",
        "/lib",
        "/userdata/system/lib",
        "/userdata/system/raofflineproxy/lib",
        "/mnt/SDCARD/App/RAOfflineProxy/lib",
        "/run/muos/storage/application/RAOfflineProxy/lib",
        "/storage/.local/share/raofflineproxy/lib",
        "/home/ark/raofflineproxy/lib",
    )
    for base in bases:
        for name in names:
            paths.append(f"{base}/{name}")

    return paths


def load_rchash() -> ctypes.CDLL | None:
    global _LIBRCHASH, _LIBRCHASH_ERROR
    if _LIBRCHASH is not None:
        return _LIBRCHASH
    if _LIBRCHASH_ERROR is not None:
        return None

    for candidate in _candidate_library_paths():
        if not candidate:
            continue
        if "/" in candidate and not os.path.isfile(candidate):
            continue
        try:
            library = ctypes.CDLL(candidate)
            library.raproxy_hash_file.argtypes = [
                ctypes.c_char_p,
                ctypes.c_char_p,
                ctypes.c_int,
            ]
            library.raproxy_hash_file.restype = ctypes.c_int
            library.raproxy_hash_disc_datasource.argtypes = [
                ctypes.c_void_p,
                _DS_SIZE_FN,
                _DS_READ_FN,
                ctypes.c_char_p,
                ctypes.c_int,
            ]
            library.raproxy_hash_disc_datasource.restype = ctypes.c_int
            _LIBRCHASH = library
            LOGGER.debug("Loaded libraproxy_rchash from %s", candidate)
            return library
        except OSError as exc:
            if _LIBRCHASH_ERROR is None:
                _LIBRCHASH_ERROR = f"libraproxy_rchash load failed: {exc}"
        except AttributeError as exc:
            if _LIBRCHASH_ERROR is None:
                _LIBRCHASH_ERROR = f"libraproxy_rchash API mismatch: {exc}"

    if _LIBRCHASH_ERROR is None:
        _LIBRCHASH_ERROR = "libraproxy_rchash shared library not found"
    return None


def _extract_candidates(buffer: ctypes.Array, count: int) -> list[str]:
    candidates: list[str] = []
    for index in range(max(count, 0)):
        chunk = buffer.raw[index * _HASH_STRIDE : (index + 1) * _HASH_STRIDE]
        value = chunk.split(b"\x00", 1)[0].decode("ascii", "ignore").strip().lower()
        if value and value not in candidates:
            candidates.append(value)
    return candidates


def _generate_disc_datasource_candidates(library: ctypes.CDLL, data_source: RvzDataSource) -> list[str]:
    def size_fn(_ctx: int) -> int:
        return data_source.length

    def read_fn(_ctx: int, offset: int, out_buffer: int, num_bytes: int) -> int:
        chunk = data_source.read(offset, num_bytes)
        if not chunk:
            return -1
        ctypes.memmove(out_buffer, chunk, len(chunk))
        return len(chunk)

    buffer = ctypes.create_string_buffer(_MAX_CANDIDATES * _HASH_STRIDE)
    # ctx is required to be non-NULL by raproxy_hash_disc_datasource (used only
    # as a liveness check); the callbacks close over data_source instead.
    count = library.raproxy_hash_disc_datasource(
        ctypes.c_void_p(1), _DS_SIZE_FN(size_fn), _DS_READ_FN(read_fn), buffer, _MAX_CANDIDATES
    )
    return _extract_candidates(buffer, count)


def _generate_rvz_candidates(path: Path) -> list[str]:
    library = load_rchash()
    if library is None:
        return []

    read_source = FileReadSource(str(path))
    try:
        data_source = RvzDataSource.open(read_source)
        if data_source is None:
            LOGGER.warning("Could not open RVZ data source for %s", path)
            return []
        return _generate_disc_datasource_candidates(library, data_source)
    finally:
        read_source.close()


def _generate_candidates(path: Path) -> list[str]:
    if path.suffix.lower() == ".rvz":
        return _generate_rvz_candidates(path)

    library = load_rchash()
    if library is None:
        return []

    buffer = ctypes.create_string_buffer(_MAX_CANDIDATES * _HASH_STRIDE)
    count = library.raproxy_hash_file(
        str(path).encode("utf-8"), buffer, _MAX_CANDIDATES
    )
    return _extract_candidates(buffer, count)


def hash_rom_candidates_result(path: Path) -> RomHashResult:
    path = Path(path)
    candidates = _generate_candidates(path)
    if candidates:
        return RomHashResult(candidates)

    if _LIBRCHASH_ERROR is not None:
        return RomHashResult([], _LIBRCHASH_ERROR)
    return RomHashResult([], f"Could not hash {path.name}")


def list_7z_entries(path: Path) -> list[str]:
    """Names of the files inside a .7z, or [] if it could not be read."""
    library = load_rchash()
    if library is None:
        return []

    buffer = ctypes.create_string_buffer(_ARCHIVE_NAMES_BYTES)
    count = library.raproxy_7z_list_entries(
        str(path).encode("utf-8"), buffer, _ARCHIVE_NAMES_BYTES, _MAX_ARCHIVE_ENTRIES
    )
    if count <= 0:
        return []

    names = buffer.raw.split(b"\x00")[:count]
    return [name.decode("utf-8", "replace") for name in names]


def hash_7z_entry_candidates(path: Path, entry_name: str) -> list[str]:
    """Hash candidates for one file inside a .7z, hashed by its own content.

    Empty when the entry cannot be extracted — an unsupported codec (the reader
    covers LZMA, LZMA2, PPMd and stored entries) or an entry above the native
    size cap. Callers fall back to the arcade hash of the archive name.
    """
    library = load_rchash()
    if library is None:
        return []

    buffer = ctypes.create_string_buffer(_MAX_CANDIDATES * _HASH_STRIDE)
    count = library.raproxy_hash_7z_entry(
        str(path).encode("utf-8"),
        entry_name.encode("utf-8"),
        buffer,
        _MAX_CANDIDATES,
    )
    return _extract_candidates(buffer, count)


def hash_rom_candidates(path: Path) -> list[str]:
    return hash_rom_candidates_result(path).candidates


def hash_rom(path: Path) -> str | None:
    candidates = hash_rom_candidates(path)
    return candidates[0] if candidates else None


def supported_rom_extensions() -> set[str]:
    # Extensions recognized as ROMs for browsing and for picking the file out of
    # an archive. rc_hash hashes most cartridge systems as a plain whole-file
    # MD5, so even extensions it doesn't map by name (e.g. .sms/.gen/.smd) still
    # produce the correct RetroAchievements hash. A single-file archive is also
    # treated as a ROM regardless of extension (see list_archive_rom_entries),
    # so this list does not need to be exhaustive.
    return {
        # Nintendo
        ".nes", ".fds", ".smc", ".sfc", ".fig", ".swc", ".bs",
        ".gb", ".gbc", ".gba", ".nds",
        ".n64", ".z64", ".v64", ".ndd",
        # Sega
        ".md", ".gen", ".smd", ".32x", ".sms", ".gg", ".sg", ".gdi",
        # NEC
        ".pce", ".sgx",
        # Atari
        ".a26", ".a78", ".lnx", ".jag", ".j64",
        # Other cartridge consoles
        ".col", ".int", ".vec", ".vb", ".ws", ".wsc",
        ".ngp", ".ngc", ".min", ".sv", ".chf",
        # Disc / playlist / misc
        ".iso", ".bin", ".chd", ".pbp", ".cue", ".m3u", ".cart", ".rvz", ".wad",
    }
