from __future__ import annotations

import threading

from . import cache_keys
from .storage import Storage, current_millis

# Clients ping every couple of minutes per game; the exact second a game was last touched
# never matters, so collapse the writes instead of hitting storage on every request.
LAST_PLAYED_WRITE_INTERVAL_MS = 60_000
LAST_PLAYED_ACTIONS = frozenset({"ping", "startsession"})

_last_written: dict[int, int] = {}
_lock = threading.Lock()


def record_game_played(storage: Storage, game_id: int, now: int | None = None) -> None:
    if game_id <= 0:
        return
    timestamp = now if now is not None else current_millis()
    with _lock:
        previous = _last_written.get(game_id)
        if previous is not None and timestamp - previous < LAST_PLAYED_WRITE_INTERVAL_MS:
            return
        _last_written[game_id] = timestamp
    storage.upsert_cache(
        cache_keys.last_played(game_id), str(timestamp), cached_at=timestamp
    )


def recently_played_game_ids(entries: list[dict], since: int) -> set[int]:
    game_ids: set[int] = set()
    for entry in entries:
        if entry.get("cachedAt", 0) < since:
            continue
        game_id = cache_keys.parse_game_id_from_last_played_key(entry.get("cacheKey") or "")
        if game_id is not None:
            game_ids.add(game_id)
    return game_ids


def load_recently_played_game_ids(storage: Storage, since: int) -> set[int]:
    return recently_played_game_ids(
        storage.get_all_cache_by_prefix(cache_keys.PREFIX_LAST_PLAYED), since
    )


def reset_last_played_throttle_for_tests() -> None:
    with _lock:
        _last_written.clear()
