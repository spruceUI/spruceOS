from __future__ import annotations

import json
import logging
import os

from . import cache_keys
from .config import CONFIG_DIR

CACHED_IDS_FILE = CONFIG_DIR / "cached_game_ids.txt"
LOGGER = logging.getLogger("raofflineproxy")

_RELEVANT_PREFIXES = (cache_keys.PREFIX_PATCH, cache_keys.PREFIX_ACHIEVEMENTSETS)


def key_affects_cached_game_ids(cache_key: str | None) -> bool:
    if cache_key is None:
        return True
    return cache_key.startswith(_RELEVANT_PREFIXES)


def collect_cached_game_ids(storage) -> set[int]:
    ids: set[int] = set()

    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH):
        game_id = cache_keys.parse_game_id_from_patch_key(entry.get("cacheKey") or "")
        if game_id is not None and game_id > 0:
            ids.add(game_id)

    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS):
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue
        game_id = payload.get("GameId")
        if isinstance(game_id, int) and game_id > 0:
            ids.add(game_id)

    return ids


def export_cached_game_ids(storage) -> None:
    try:
        content = "".join(
            f"{game_id}\n" for game_id in sorted(collect_cached_game_ids(storage))
        )
        try:
            if CACHED_IDS_FILE.read_text() == content:
                return
        except OSError:
            pass

        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        tmp_path = CACHED_IDS_FILE.with_name(CACHED_IDS_FILE.name + ".tmp")
        tmp_path.write_text(content)
        os.replace(tmp_path, CACHED_IDS_FILE)
    except Exception:
        LOGGER.exception("Failed to export cached game ids")
