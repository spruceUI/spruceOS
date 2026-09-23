from __future__ import annotations

import json
import logging
import time
import urllib.error

from . import cache_keys
from .config import FALLBACK_USER_AGENT, proxy_host, proxy_port, upstream_host
from .image_cache import rewrite_image_urls, schedule_image_download
from .network import build_api_url, http_get
from .storage import PENDING_AWARD_STATUS_PENDING, Storage
from .utils import is_hardcore_request, parse_form_params

LOGGER = logging.getLogger("raofflineproxy")
WARNING_ACHIEVEMENT_ID = 101000001
RC_ACHIEVEMENT_FLAG_CORE = 3  # rcheevos: official/core achievements only


class CacheGameError(RuntimeError):
    pass


class CacheGameAuthError(CacheGameError):
    pass


def api_error_message(action: str, payload: dict) -> str:
    message = payload.get("Error") or payload.get("Message") or payload.get("error")
    if message:
        return f"{action} failed: {message}"
    return f"{action} failed"


def filter_warning_achievement_ids(ids: list[int]) -> list[int]:
    return [achievement_id for achievement_id in ids if achievement_id > 0 and achievement_id != WARNING_ACHIEVEMENT_ID]


def filter_warning_achievement_definitions(payload: dict) -> dict:
    filtered_payload = json.loads(json.dumps(payload))

    sets = filtered_payload.get("Sets")
    if isinstance(sets, list):
        for achievement_set in sets:
            if not isinstance(achievement_set, dict):
                continue

            achievements = achievement_set.get("Achievements")
            if not isinstance(achievements, list):
                continue

            achievement_set["Achievements"] = [
                achievement
                for achievement in achievements
                if isinstance(achievement, dict)
                and achievement.get("Flags", RC_ACHIEVEMENT_FLAG_CORE) == RC_ACHIEVEMENT_FLAG_CORE
            ]

    return filtered_payload


def filter_warning_achievement_from_patch_payload(payload: dict) -> dict:
    # Legacy "patch" responses don't reliably flag official vs. unofficial
    # achievements the way "achievementsets" does, so only the synthetic
    # warning achievement is stripped here — filtering by Flags would also
    # drop legitimate achievement sets (e.g. homebrew/test-kit ROMs).
    filtered_payload = json.loads(json.dumps(payload))

    patch_data = filtered_payload.get("PatchData")
    if isinstance(patch_data, dict):
        achievements = patch_data.get("Achievements")
        if isinstance(achievements, list):
            patch_data["Achievements"] = [
                achievement
                for achievement in achievements
                if isinstance(achievement, dict)
                and achievement.get("ID") != WARNING_ACHIEVEMENT_ID
            ]
        elif isinstance(achievements, dict):
            patch_data["Achievements"] = {
                key: achievement
                for key, achievement in achievements.items()
                if isinstance(achievement, dict)
                and achievement.get("ID") != WARNING_ACHIEVEMENT_ID
            }

    return filtered_payload


def filter_warning_achievement_from_start_session_payload(payload: dict) -> dict:
    filtered_payload = json.loads(json.dumps(payload))
    unlocks = filtered_payload.get("Unlocks")
    if not isinstance(unlocks, list):
        return filtered_payload
    filtered_payload["Unlocks"] = [
        entry
        for entry in unlocks
        if isinstance(entry, dict) and entry.get("ID") != WARNING_ACHIEVEMENT_ID
    ]
    return filtered_payload


def filter_warning_achievements_for_action(action: str | None, response_body: str) -> str:
    if action not in ("patch", "achievementsets", "unlocks", "startsession"):
        return response_body
    try:
        payload = json.loads(response_body)
    except Exception:
        return response_body
    if action == "unlocks":
        payload = filter_warning_achievement_from_unlocks_payload(payload)
    elif action == "startsession":
        payload = filter_warning_achievement_from_start_session_payload(payload)
    elif action == "patch":
        payload = filter_warning_achievement_from_patch_payload(payload)
    else:
        payload = filter_warning_achievement_definitions(payload)
    return json.dumps(payload, separators=(",", ":"))


def filter_warning_achievement_from_unlocks_payload(payload: dict) -> dict:
    filtered_payload = json.loads(json.dumps(payload))
    unlock_ids = filtered_payload.get("UserUnlocks")
    if not isinstance(unlock_ids, list):
        return filtered_payload

    filtered_payload["UserUnlocks"] = filter_warning_achievement_ids(
        [achievement_id for achievement_id in unlock_ids if isinstance(achievement_id, int)]
    )
    return filtered_payload


def refresh_game_patch(
    game_id: int,
    credentials: dict,
    user_agent: str,
    storage: Storage,
    config_data: dict,
    cache_images: bool = True,
) -> str | None:
    url = build_api_url(
        upstream_host(config_data),
        "patch",
        {
            "g": str(game_id),
            "u": credentials["user"],
            "t": credentials["token"],
        },
    )

    try:
        response_body = http_get(url, user_agent)
        payload = json.loads(response_body)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise CacheGameAuthError(f"patch request failed: {exc}") from exc
        raise CacheGameError(f"patch request failed: {exc}") from exc
    except Exception as exc:
        raise CacheGameError(f"patch request failed: {exc}") from exc

    if not payload.get("Success"):
        raise CacheGameError(api_error_message("patch", payload))

    payload = filter_warning_achievement_from_patch_payload(payload)
    response_body = json.dumps(payload, separators=(",", ":"))

    storage.upsert_cache(cache_keys.patch(game_id, credentials["user"]), response_body)

    if cache_images:
        proxy_base_url = f"http://{proxy_host(config_data)}:{proxy_port(config_data)}"
        _, downloads = rewrite_image_urls("patch", response_body, proxy_base_url)
        for orig_url, img_path in downloads:
            schedule_image_download(orig_url, img_path, user_agent, game_id)

    return response_body


def cache_unlocks(
    game_id: int,
    credentials: dict,
    user_agent: str,
    config_data: dict,
    storage: Storage | None = None,
) -> str | None:
    url = build_api_url(
        upstream_host(config_data),
        "unlocks",
        {
            "g": str(game_id),
            "h": "0",
            "u": credentials["user"],
            "t": credentials["token"],
        },
    )
    try:
        response_body = http_get(url, user_agent)
        payload = json.loads(response_body)
    except Exception:
        return None

    if not payload.get("Success"):
        return None

    payload = filter_warning_achievement_from_unlocks_payload(payload)
    response_body = json.dumps(payload, separators=(",", ":"))

    if storage is not None:
        storage.upsert_cache(
            cache_keys.unlocks(game_id, credentials["user"]),
            response_body,
        )

    return response_body


def cache_achievementsets(
    hash_value: str,
    credentials: dict,
    user_agent: str,
    config_data: dict,
    storage: Storage | None = None,
    game_id: int | None = None,
    cache_images: bool = True,
) -> str | None:
    url = build_api_url(
        upstream_host(config_data),
        "achievementsets",
        {
            "m": hash_value,
            "u": credentials["user"],
            "t": credentials["token"],
        },
    )
    try:
        response_body = http_get(url, user_agent)
        payload = json.loads(response_body)
    except Exception:
        return None

    if not payload.get("Success"):
        return None

    payload = filter_warning_achievement_definitions(payload)
    response_body = json.dumps(payload, separators=(",", ":"))

    if storage is not None:
        storage.upsert_cache(
            cache_keys.achievementsets(hash_value, credentials["user"]),
            response_body,
        )

    if cache_images:
        proxy_base_url = f"http://{proxy_host(config_data)}:{proxy_port(config_data)}"
        _, downloads = rewrite_image_urls("achievementsets", response_body, proxy_base_url)
        for orig_url, img_path in downloads:
            schedule_image_download(orig_url, img_path, user_agent, game_id)

    return response_body


def build_unlocks_array(
    storage: Storage, game_id: int, user: str, server_now: int
) -> list[dict]:
    unlock_ids = merged_unlock_ids(storage, game_id, user)
    return [{"ID": achievement_id, "When": server_now} for achievement_id in unlock_ids]


def merged_unlock_ids(storage: Storage, game_id: int, user: str) -> list[int]:
    entry = storage.get_cache(cache_keys.unlocks(game_id, user))
    cached_unlock_ids: list[int] = []
    if entry is not None:
        try:
            payload = json.loads(entry["responseBody"])
            unlock_ids = payload.get("UserUnlocks") or []
            cached_unlock_ids = filter_warning_achievement_ids([
                achievement_id
                for achievement_id in unlock_ids
                if isinstance(achievement_id, int) and achievement_id > 0
            ])
        except Exception:
            cached_unlock_ids = []

    achievement_game_ids = build_achievement_game_ids(
        storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH),
        storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS),
    )
    return merge_start_session_unlock_ids(
        cached_unlock_ids=cached_unlock_ids,
        pending_awards=storage.get_pending_awards(),
        achievement_game_ids=achievement_game_ids,
        game_id=game_id,
        user=user,
    )


def merge_start_session_unlock_ids(
    *,
    cached_unlock_ids: list[int],
    pending_awards: list[dict],
    achievement_game_ids: dict[int, int],
    game_id: int,
    user: str,
) -> list[int]:
    merged_ids: list[int] = []
    seen_ids: set[int] = set()

    for achievement_id in cached_unlock_ids:
        if achievement_id <= 0 or achievement_id in seen_ids:
            continue
        merged_ids.append(achievement_id)
        seen_ids.add(achievement_id)

    for award in pending_awards:
        if (
            award.get("status", PENDING_AWARD_STATUS_PENDING)
            != PENDING_AWARD_STATUS_PENDING
        ):
            continue

        achievement_id = int(award.get("achievementId", 0) or 0)
        if achievement_id <= 0 or achievement_id in seen_ids:
            continue

        if is_hardcore_request(
            award.get("queryString", ""), award.get("requestBody", "")
        ):
            continue

        if pending_award_user(award) != user:
            continue

        if achievement_game_ids.get(achievement_id) != game_id:
            continue

        merged_ids.append(achievement_id)
        seen_ids.add(achievement_id)

    return merged_ids


def _iter_achievementsets_achievements(payload: dict):
    direct = payload.get("Achievements")
    if isinstance(direct, dict):
        yield from (a for a in direct.values() if isinstance(a, dict))
        return
    if isinstance(direct, list):
        yield from (a for a in direct if isinstance(a, dict))
        return
    sets = payload.get("Sets")
    if not isinstance(sets, list):
        return
    for achievement_set in sets:
        if not isinstance(achievement_set, dict):
            continue
        achievements = achievement_set.get("Achievements")
        if isinstance(achievements, list):
            yield from (a for a in achievements if isinstance(a, dict))


def build_achievement_game_ids(
    patch_entries: list[dict],
    achievementsets_entries: list[dict] = (),
) -> dict[int, int]:
    achievement_game_ids: dict[int, int] = {}

    for entry in patch_entries:
        game_id = cache_keys.parse_game_id_from_patch_key(entry.get("cacheKey", ""))
        if game_id is None:
            continue

        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        patch_data = payload.get("PatchData") or {}
        achievements = patch_data.get("Achievements", [])
        entries = (
            achievements.values() if isinstance(achievements, dict) else achievements
        )
        for achievement in entries:
            achievement_id = achievement.get("ID")
            if isinstance(achievement_id, int) and achievement_id > 0:
                achievement_game_ids.setdefault(achievement_id, game_id)

    for entry in achievementsets_entries:
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        game_id = payload.get("GameId")
        if not isinstance(game_id, int) or game_id <= 0:
            continue

        for achievement in _iter_achievementsets_achievements(payload):
            achievement_id = achievement.get("ID")
            if isinstance(achievement_id, int) and achievement_id > 0:
                achievement_game_ids.setdefault(achievement_id, game_id)

    return achievement_game_ids


def pending_award_user(award: dict) -> str | None:
    query_params = parse_form_params(
        award.get("queryString", "").split("?", 1)[1]
        if "?" in award.get("queryString", "")
        else ""
    )
    return query_params.get("u") or parse_form_params(award.get("requestBody", "")).get(
        "u"
    )


def cache_session(game_id: int, credentials: dict, storage: Storage) -> str:
    server_now = int(time.time())
    payload = {
        "Success": True,
        "ServerNow": server_now,
        "HardcoreUnlocks": [],
        "Unlocks": build_unlocks_array(
            storage, game_id, credentials["user"], server_now
        ),
    }
    response_body = json.dumps(payload, separators=(",", ":"))
    storage.upsert_cache(
        cache_keys.start_session(game_id, credentials["user"]), response_body
    )
    return response_body


def cache_game(
    game_id: int,
    hash_value: str,
    credentials: dict,
    user_agent: str,
    storage: Storage,
    config_data: dict,
    cache_images: bool = True,
) -> None:
    patch_body = refresh_game_patch(
        game_id,
        credentials,
        user_agent or FALLBACK_USER_AGENT,
        storage,
        config_data,
        cache_images=cache_images,
    )
    if patch_body is None:
        raise CacheGameError("patch failed")

    cache_unlocks(
        game_id,
        credentials,
        user_agent or FALLBACK_USER_AGENT,
        config_data,
        storage,
    )
    cache_achievementsets(
        hash_value,
        credentials,
        user_agent or FALLBACK_USER_AGENT,
        config_data,
        storage,
        cache_images=cache_images,
    )
    cache_session(game_id, credentials, storage)
