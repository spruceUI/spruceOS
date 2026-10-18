"""Identify one ROM: the saved path association, else its hashes (.agents/integration.md).

Spruce has already tried its own loaded path-to-game mapping before starting the helper. A
saved association answers without loading the proxy's hasher, SQLite or network code: those
are imported only for a path that must be hashed, to keep the helper's start-up short.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from cheevos.core.identification.path_cache import PathCache
from cheevos.core.identification.result import FILE, Identification, IdentificationError

if TYPE_CHECKING:
    from cheevos.core.identification.candidates import Hasher
    from cheevos.core.identification.hash_lookup import HashResolver

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class Sources:
    """What identifying an unknown path uses, each created only when needed.

    Attributes:
        load_hasher: Loads RAOfflineProxy's hashing wrapper; raises a ``dependency`` error.
        work_dir: SD-card directory for extracting a zipped ROM.
        proxy_database: RAOfflineProxy's ``proxy.sqlite3`` (read-only).
        ra_lookup: Creates RA's hash lookup for hashes the proxy hasn't cached.
        now: Epoch seconds.
    """

    load_hasher: Callable[[], Hasher]
    work_dir: Path
    proxy_database: Path
    ra_lookup: Callable[[], HashResolver]
    now: Callable[[], float]


def identify_rom(path: str, *, cache: PathCache, sources: Sources) -> Identification:
    """Return the ROM's game, a confirmed miss or an error; save matches and misses.

    Args:
        path: The ROM's path, as Spruce passed it.
        cache: Saved path associations.
        sources: Hashing and lookup collaborators for an unknown path.

    Returns:
        The outcome. Errors are returned, not raised, and never saved.
    """
    name = Path(path).name
    cached = cache.lookup(path)
    if cached is not None:
        logger.info("Saved association for %s: %s", name, cached.status)
        return cached
    try:
        result = _identify_unknown(Path(path), sources)
    except IdentificationError as exc:
        logger.warning("Could not identify %s: %s", name, exc)
        return Identification.error(exc.reason)
    logger.info("Identified %s: %s", name, result.to_json())
    cache.remember(path, result)
    return result


def _identify_unknown(rom: Path, sources: Sources) -> Identification:
    """Hash the ROM with the proxy's hasher, then resolve its candidates."""
    try:
        if not rom.is_file():
            raise IdentificationError(FILE, "not a file")
    except OSError as exc:
        raise IdentificationError(FILE, repr(exc)) from exc
    # Loaded only for an unknown path (see the module docstring).
    from cheevos.core.identification.candidates import hash_candidates
    from cheevos.core.identification.hash_lookup import ProxyHashCache, resolve

    candidates = hash_candidates(rom, sources.load_hasher(), sources.work_dir)
    proxy_cache = ProxyHashCache(sources.proxy_database, now=sources.now)
    try:
        return resolve(candidates, proxy_cache, sources.ra_lookup)
    finally:
        proxy_cache.close()
