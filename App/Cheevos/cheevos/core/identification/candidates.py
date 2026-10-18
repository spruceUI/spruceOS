"""A ROM's RetroAchievements hash candidates, in the order RAOfflineProxy tries them.

The hashing itself is the proxy's native rcheevos ``rc_hash`` binding, reached through the
:class:`Hasher` adapter (``cheevos.platform.proxy_hasher``). This module repeats only the proxy's
archive rules from ``rom_browser.hash_candidates_for_manual_cache``, which can't be imported
without the proxy's service graph (.agents/integration.md); ``scripts/check_proxy_compat.py``
compares the two:

- a ``.7z`` with one ROM entry is hashed by that entry's content, falling back to the
  archive's arcade hash (its file name) when the entry can't be read;
- a ``.zip`` with one ROM entry is extracted and hashed by content;
- an archive with no ROM entry is an arcade set, hashed by file name;
- an archive with several ROM entries can't be identified.

ZIP extraction streams in 64 KB chunks into a ``rom-hash-*`` directory under the work
directory on the SD card, removed afterwards (also on SIGTERM, which the helper turns into
``SystemExit``). Never read an entry into memory or extract it to RAM-backed ``/tmp``.
"""

from __future__ import annotations

import logging
import shutil
import tempfile
import zipfile
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from cheevos.core.identification.result import HASH, IdentificationError

logger = logging.getLogger(__name__)

COPY_CHUNK = 64 * 1024
SEVEN_ZIP = ".7z"
ZIP = ".zip"
# Archive reading failures: unsupported compression (NotImplementedError), encrypted entries
# (RuntimeError), corrupt data (BadZipFile on a CRC mismatch, zlib.error, EOFError).
_ZIP_ERRORS = (zipfile.BadZipFile, NotImplementedError, RuntimeError, EOFError, zlib.error)


@dataclass(frozen=True, slots=True)
class HashResult:
    """Hash candidates for one file.

    Attributes:
        candidates: Lower-case hex MD5 hashes, most specific first.
        error: The hasher's explanation when there are none, for the log.
    """

    candidates: tuple[str, ...]
    error: str | None = None


class Hasher(Protocol):
    """RAOfflineProxy's hashing wrapper, as the adapter exposes it."""

    def supported_extensions(self) -> frozenset[str]:
        """Return the lower-case ROM extensions (with dots) that pick an archive's ROM entry."""
        ...

    def hash_file(self, path: Path) -> HashResult:
        """Hash a file on disk; an archive or unknown file falls back to the arcade rule."""
        ...

    def list_7z_entries(self, path: Path) -> list[str]:
        """Return the file names inside a ``.7z``, or an empty list if it can't be read."""
        ...

    def hash_7z_entry(self, path: Path, entry: str) -> tuple[str, ...]:
        """Hash one ``.7z`` entry by content; empty when it can't be extracted."""
        ...


def select_archive_rom_names(names: list[str], extensions: frozenset[str]) -> list[str]:
    """Pick an archive's ROM entries: names with a ROM extension, or its only file.

    Args:
        names: Entry names, without directories and hidden files.
        extensions: Supported ROM extensions.

    Returns:
        The ROM entries; several mean the archive can't be identified, none an arcade set.
    """
    rom_names = [name for name in names if Path(name).suffix.lower() in extensions]
    if rom_names:
        return rom_names
    return names if len(names) == 1 else []


def _visible(name: str) -> bool:
    """Skip hidden entries such as macOS's ``._game.gba`` resource forks."""
    return not Path(name).name.startswith(".")


def zip_rom_entries(path: Path, extensions: frozenset[str]) -> list[zipfile.ZipInfo]:
    """Return a ZIP's ROM entries; an unreadable ZIP has none, like an arcade set.

    Args:
        path: The ``.zip`` file.
        extensions: Supported ROM extensions.

    Returns:
        The selected entries, in archive order.
    """
    try:
        with zipfile.ZipFile(path) as archive:
            files = [
                info for info in archive.infolist() if not info.is_dir() and _visible(info.filename)
            ]
    except (OSError, *_ZIP_ERRORS) as exc:
        logger.info("Treating %s as an arcade set: %s", path.name, exc)
        return []
    selected = set(select_archive_rom_names([info.filename for info in files], extensions))
    return [info for info in files if info.filename in selected]


def _single(entries: list[str], archive: Path) -> str | None:
    """Return the only ROM entry, ``None`` for an arcade set, or fail for several ROMs."""
    if len(entries) > 1:
        raise IdentificationError(HASH, f"{archive.name} contains {len(entries)} ROMs")
    return entries[0] if entries else None


def _from_7z(path: Path, hasher: Hasher) -> tuple[str, ...]:
    """Hash a ``.7z`` by its ROM entry, or by its file name as an arcade set."""
    names = [name for name in hasher.list_7z_entries(path) if _visible(name)]
    entry = _single(select_archive_rom_names(names, hasher.supported_extensions()), path)
    if entry is not None:
        candidates = hasher.hash_7z_entry(path, entry)
        if candidates:
            return candidates
        logger.info("Could not read %s in %s; using its arcade hash", entry, path.name)
    return _report(hasher.hash_file(path), path)


def _from_zip(path: Path, hasher: Hasher, work_dir: Path) -> tuple[str, ...]:
    """Hash a ``.zip`` by its extracted ROM entry, or by its file name as an arcade set."""
    entries = zip_rom_entries(path, hasher.supported_extensions())
    name = _single([info.filename for info in entries], path)
    if name is None:
        return _report(hasher.hash_file(path), path)
    entry = entries[0]
    work_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="rom-hash-", dir=work_dir) as scratch:
        # rc_hash picks the console by extension, so the copy keeps the entry's own file name
        # (never a directory, "." or "..": those entries aren't selected).
        target = Path(scratch) / Path(entry.filename).name
        try:
            with (
                zipfile.ZipFile(path) as archive,
                archive.open(entry) as source,
                target.open("wb") as output,
            ):
                shutil.copyfileobj(source, output, COPY_CHUNK)
        except (OSError, *_ZIP_ERRORS) as exc:
            raise IdentificationError(HASH, f"extracting {path.name}: {exc!r}") from exc
        return _report(hasher.hash_file(target), target)


def _report(result: HashResult, path: Path) -> tuple[str, ...]:
    """Return candidates, logging the hasher's reason when there are none."""
    if not result.candidates:
        logger.info("No hash for %s: %s", path.name, result.error or "unknown format")
    return result.candidates


def hash_candidates(path: Path, hasher: Hasher, work_dir: Path) -> tuple[str, ...]:
    """Return a ROM's hash candidates.

    Args:
        path: The ROM file (checked to exist by the caller).
        hasher: The proxy's hashing wrapper.
        work_dir: SD-card directory for extracting a zipped ROM.

    Returns:
        Candidates in the hasher's order (never empty).

    Raises:
        IdentificationError: ``hash`` when the ROM can't be hashed.
    """
    suffix = path.suffix.lower()
    if suffix == SEVEN_ZIP:
        candidates = _from_7z(path, hasher)
    elif suffix == ZIP:
        candidates = _from_zip(path, hasher, work_dir)
    else:
        candidates = _report(hasher.hash_file(path), path)
    if not candidates:
        raise IdentificationError(HASH, f"no hash for {path.name}")
    return candidates
