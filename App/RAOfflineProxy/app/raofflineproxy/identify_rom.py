"""Identify one selected ROM without caching achievements or starting the proxy."""

from __future__ import annotations

import signal
import urllib.error
from pathlib import Path

from . import cache_keys, rate_limit
from .auth import resolve_credentials
from .network import online_check
from .rom_browser import (
    GAMEID_MISS_TTL_MS,
    GameIdLookupError,
    cached_game_id_for_hash,
    fetch_game_id,
    hash_candidates_for_manual_cache,
    parse_game_id_lookup,
)
from .storage import Storage, current_millis
from .utils import self_user_agent


def _cached_miss(storage: Storage, candidate: str) -> bool:
    entry = storage.get_cache(cache_keys.game_id(candidate))
    if entry is None or not 0 <= current_millis() - entry["cachedAt"] < GAMEID_MISS_TTL_MS:
        return False
    try:
        return parse_game_id_lookup(entry["responseBody"]) is None
    except (GameIdLookupError, ValueError, TypeError):
        return False


def identify_rom(path: Path, storage: Storage, config_data: dict) -> dict:
    """Return a match, confirmed miss or stable error code; never queue game caching."""
    if not path.is_file():
        return {"status": "error", "reason": "file"}
    try:
        candidates = hash_candidates_for_manual_cache(path)
    except Exception:
        return {"status": "error", "reason": "hash"}
    if not candidates:
        return {"status": "error", "reason": "hash"}
    try:
        with rate_limit.background():
            return _resolve(candidates, storage, config_data)
    except GameIdLookupError as error:
        return {"status": "error", "reason": error.reason}
    except urllib.error.HTTPError as error:
        reason = "auth" if error.code in (401, 403) else "network"
        if error.code == 429:
            reason = "rate_limited"
        return {"status": "error", "reason": reason}
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        return {"status": "error", "reason": "offline"}
    except rate_limit.RateLimitedError:
        return {"status": "error", "reason": "rate_limited"}
    except (ValueError, TypeError, KeyError):
        return {"status": "error", "reason": "response"}


def _resolve(candidates: list[str], storage: Storage, config_data: dict) -> dict:
    credentials = None
    user_agent = self_user_agent()
    for candidate in candidates:
        # Check each candidate in hasher order. A later cached match must not skip an
        # earlier unresolved candidate: different hashing rules can identify different games.
        game_id = cached_game_id_for_hash(storage, candidate)
        if game_id is not None:
            return {"status": "matched", "game_id": game_id}
        if _cached_miss(storage, candidate):
            continue
        if rate_limit.paused_until() is not None:
            return {"status": "error", "reason": "rate_limited"}
        if credentials is None:
            credentials = resolve_credentials(storage, config_data, user_agent)
            if credentials is None:
                if rate_limit.paused_until() is not None:
                    return {"status": "error", "reason": "rate_limited"}
                reason = "auth" if online_check(config_data) else "offline"
                return {"status": "error", "reason": reason}
        game_id = fetch_game_id(candidate, credentials, user_agent, config_data, storage)
        if game_id is not None:
            return {"status": "matched", "game_id": game_id}
    return {"status": "no_match"}


def _terminate_identification(signum: int, _frame: object) -> None:
    """Unwind extraction and storage cleanup when Spruce cancels the helper."""
    raise SystemExit(128 + signum)


def run_identification(path: str | None, config_data: dict) -> dict:
    """Run the CLI lookup with structured failures and SIGTERM cleanup."""
    if not path:
        return {"status": "error", "reason": "file"}
    previous = signal.signal(signal.SIGTERM, _terminate_identification)
    storage = None
    try:
        storage = Storage()
        return identify_rom(Path(path).expanduser(), storage, config_data)
    except Exception:
        return {"status": "error", "reason": "unavailable"}
    finally:
        try:
            if storage is not None:
                storage.close()
        finally:
            signal.signal(signal.SIGTERM, previous)
