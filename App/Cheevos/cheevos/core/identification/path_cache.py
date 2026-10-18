"""Remembered game IDs by ROM path: ``Saves/cheevos/cache/rom-identifications.json``.

Spruce's own path-to-game mapping comes first and never reaches this cache. Entries are keyed
by absolute path, with no fingerprints: a known association stays valid when the ROM is
patched or replaced at that path, since the menu only shows progress (.agents/integration.md).
Confirmed misses expire after seven days, because RA adds hashes over time; errors and
cancellations are never cached. The file is bounded (256 entries, 256 KB) and written
atomically, and a failed write never fails the lookup.
"""

from __future__ import annotations

import json
import logging
import os
from collections.abc import Callable
from pathlib import Path

from cheevos.core.clock import network_clock
from cheevos.core.files import write_text_atomic
from cheevos.core.identification.result import MATCHED, NO_MATCH, Identification

logger = logging.getLogger(__name__)

CACHE_VERSION = 2
READABLE_VERSIONS = (1, 2)  # version 1 also kept fingerprints, which are dropped on save
MAX_ENTRIES = 256
MAX_BYTES = 256 * 1024
MISS_TTL = 7 * 24 * 60 * 60


def path_key(path: str) -> str:
    """Return the cache key for a ROM path: its absolute, normalised form."""
    return os.path.abspath(path)  # noqa: PTH100 — the key format earlier Spruce builds wrote


class PathCache:
    """Bounded path associations, read lazily on the first lookup.

    Args:
        file: The JSON file.
        now: Epoch seconds, for the age of confirmed misses.
    """

    def __init__(self, file: Path, *, now: Callable[[], float] = network_clock.now) -> None:
        self._file = file
        self._now = now
        self._entries: dict[str, dict[str, object]] | None = None

    def lookup(self, path: str) -> Identification | None:
        """Return the saved match, or a confirmed miss younger than a week.

        Args:
            path: ROM path as Spruce passed it.

        Returns:
            The saved outcome, or ``None`` when the path must be identified.
        """
        entry = self._load().get(path_key(path))
        if entry is None:
            return None
        result = Identification.from_cache(entry.get("result"))
        if result is not None and result.status == NO_MATCH and not self._fresh(entry):
            return None
        return result

    def remember(self, path: str, result: Identification) -> None:
        """Save a match or confirmed miss as the newest entry; other outcomes are ignored.

        Args:
            path: ROM path as Spruce passed it.
            result: The helper's outcome.
        """
        if result.status not in (MATCHED, NO_MATCH):
            return
        entries = self._load()
        key = path_key(path)
        entries.pop(key, None)
        entry: dict[str, object] = {"result": result.to_json()}
        if result.status == NO_MATCH:
            entry["checked_at"] = self._now()
        entries[key] = entry
        while len(entries) > MAX_ENTRIES:
            del entries[next(iter(entries))]
        self._save(entries)

    def _fresh(self, entry: dict[str, object]) -> bool:
        """Check a confirmed miss's age; a clock that went backwards counts as stale."""
        checked_at = entry.get("checked_at")
        if not isinstance(checked_at, (int, float)) or isinstance(checked_at, bool):
            return False
        return 0 <= self._now() - checked_at < MISS_TTL

    def _load(self) -> dict[str, dict[str, object]]:
        """Read the file once; anything oversized, unknown or malformed reads as empty."""
        if self._entries is None:
            self._entries = self._read()
        return self._entries

    def _read(self) -> dict[str, dict[str, object]]:
        """Parse the file, keeping only valid results (and a miss's check time)."""
        try:
            if self._file.stat().st_size > MAX_BYTES:
                logger.warning("Ignoring oversized %s", self._file)
                return {}
            payload = json.loads(self._file.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            logger.warning("Ignoring unreadable %s: %s", self._file, exc)
            return {}
        entries = payload.get("entries") if isinstance(payload, dict) else None
        if (
            not isinstance(payload, dict)
            or payload.get("version") not in READABLE_VERSIONS
            or not isinstance(entries, dict)
            or len(entries) > MAX_ENTRIES
        ):
            logger.warning("Ignoring %s in an unknown format", self._file)
            return {}
        valid: dict[str, dict[str, object]] = {}
        for key, entry in entries.items():
            result = (
                Identification.from_cache(entry.get("result")) if isinstance(entry, dict) else None
            )
            if not isinstance(key, str) or result is None:
                continue
            valid[key] = {"result": result.to_json()}
            if result.status == NO_MATCH:
                valid[key]["checked_at"] = entry.get("checked_at")
        return valid

    def _save(self, entries: dict[str, dict[str, object]]) -> None:
        """Write atomically, dropping the oldest entries until the file fits its bound."""

        def serialise() -> str:
            """Encode the entries compactly."""
            return json.dumps({"version": CACHE_VERSION, "entries": entries}, separators=(",", ":"))

        text = serialise()
        while len(text.encode("utf-8")) > MAX_BYTES and len(entries) > 1:
            del entries[next(iter(entries))]
            text = serialise()
        if len(text.encode("utf-8")) > MAX_BYTES:
            logger.warning("Not saving %s: one path exceeds its size bound", self._file)
            return
        try:
            write_text_atomic(self._file, text)
        except OSError as exc:
            logger.warning("Could not save %s: %s", self._file, exc)
