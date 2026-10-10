from __future__ import annotations

import json
import re

from . import cache_keys

GAME_META_PREFIXES = (cache_keys.PREFIX_PATCH, cache_keys.PREFIX_ACHIEVEMENTSETS)

_LEADING_GAME_ID = re.compile(r'\{\s*"Success"\s*:\s*(?:true|false)\s*,\s*"GameId"\s*:\s*(\d+)')


def achievementsets_game_id(response_body: str) -> int | None:
    """RA and our own rewrite both start the body with Success and GameId, so the id is read
    without parsing up to 200 KB of JSON per game; anything else falls back to a full parse."""
    match = _LEADING_GAME_ID.match(response_body)
    if match is not None:
        game_id = int(match.group(1))
        return game_id if game_id > 0 else None
    try:
        game_id = json.loads(response_body).get("GameId")
    except Exception:
        return None
    return game_id if isinstance(game_id, int) and game_id > 0 else None


def game_meta_for_entry(cache_key: str, response_body: str) -> dict | None:
    if cache_key.startswith(cache_keys.PREFIX_PATCH):
        return _patch_meta(cache_key, response_body)
    if cache_key.startswith(cache_keys.PREFIX_ACHIEVEMENTSETS):
        return _achievementsets_meta(cache_key, response_body)
    return None


def _patch_meta(cache_key: str, response_body: str) -> dict | None:
    game_id = cache_keys.parse_game_id_from_patch_key(cache_key)
    if game_id is None:
        return None
    try:
        patch_data = json.loads(response_body).get("PatchData") or {}
    except Exception:
        patch_data = {}
    return {
        "cacheKey": cache_key,
        "gameId": game_id,
        "title": patch_data.get("Title") or f"Game {game_id}",
        "imagePath": patch_data.get("ImageIcon") or patch_data.get("ImageBoxArt"),
    }


def _achievementsets_meta(cache_key: str, response_body: str) -> dict | None:
    try:
        payload = json.loads(response_body)
    except Exception:
        return None
    game_id = payload.get("GameId")
    if not isinstance(game_id, int) or game_id <= 0:
        return None
    return {
        "cacheKey": cache_key,
        "gameId": game_id,
        "title": payload.get("Title") or f"Game {game_id}",
        "imagePath": payload.get("ImageIcon") or payload.get("ImageIconUrl"),
    }
