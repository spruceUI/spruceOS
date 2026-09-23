from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass

from . import cache_keys
from .auth import resolve_credentials
from .award_signing import public_key_base64, sign_award, verify_award
from .config import FALLBACK_USER_AGENT, MAX_PROXY_PORT, upstream_host
from .network import build_api_url, http_post
from .rom_cache import (
    CacheGameAuthError,
    CacheGameError,
    build_achievement_game_ids,
    cache_session,
    cache_unlocks,
    refresh_game_patch,
)
from .storage import (
    PENDING_AWARD_STATUS_DELETED,
    PENDING_AWARD_STATUS_FLUSHED,
    PENDING_AWARD_STATUS_PENDING,
    PENDING_AWARD_STATUS_STALE,
    Storage,
)
from .utils import (
    canonical_reason_phrase,
    extract_form_param,
    parse_form_params,
    proxy_user_agent,
    redact_query_tokens,
    replace_or_append_form_param,
    self_user_agent,
    sha256_hex,
)

MAX_RETRIES = 5
GENESIS_HASH = "genesis"
MAX_AWARD_OFFSET_SECONDS = 14 * 24 * 60 * 60
LOGGER = logging.getLogger("raofflineproxy")


@dataclass
class FlushOutcome:
    flushed: int
    total: int
    skipped_stale: int
    skipped_deleted: int = 0
    pending_remaining: int = 0
    last_error: str | None = None


def is_hardcore_award(award: dict) -> bool:
    query_params = parse_form_params(
        award["queryString"].split("?", 1)[1] if "?" in award["queryString"] else ""
    )
    if "h" in query_params:
        return query_params["h"] == "1"
    return parse_form_params(award["requestBody"]).get("h") == "1"


def canonical_payload(award: dict) -> str:
    return f"{award['achievementId']}|{award['queryString']}|{award['requestBody']}|{award['queuedAt']}"


def compute_validation_hash(
    achievement_id: int, username: str, hardcore: int, seconds_since_unlock: int
) -> str:
    md5 = __import__("hashlib").md5()
    aid = str(achievement_id)
    md5.update(aid.encode("utf-8"))
    md5.update(username.encode("utf-8"))
    md5.update(str(hardcore).encode("utf-8"))
    if seconds_since_unlock:
        md5.update(aid.encode("utf-8"))
        md5.update(str(seconds_since_unlock).encode("utf-8"))
    return md5.hexdigest()


def clamp_award_offset_seconds(raw_offset_seconds: int) -> int:
    return max(0, min(MAX_AWARD_OFFSET_SECONDS, raw_offset_seconds))


def build_award_request_body(
    award: dict, now_millis: int | None = None, current_token: str | None = None
) -> str:
    body = award["requestBody"]
    if current_token:
        body = replace_or_append_form_param(body, "t", current_token)
    current_time = now_millis or int(time.time() * 1000)
    raw_offset = int((current_time - award["queuedAt"]) / 1000)
    offset_seconds = clamp_award_offset_seconds(raw_offset)
    if offset_seconds > 0:
        achievement_id = int(extract_form_param(body, "a") or award["achievementId"])
        username = extract_form_param(body, "u") or ""
        hardcore = int(extract_form_param(body, "h") or "0")
        body = replace_or_append_form_param(
            body,
            "v",
            compute_validation_hash(achievement_id, username, hardcore, offset_seconds),
        )
        body = replace_or_append_form_param(body, "o", str(offset_seconds))

    if not award.get("payloadHash"):
        return body

    body = replace_or_append_form_param(
        body, "ra_chain_payload_hash", award["payloadHash"]
    )
    body = replace_or_append_form_param(body, "ra_chain_prev_hash", award["prevHash"])
    body = replace_or_append_form_param(body, "ra_chain_sig", award["signature"])
    body = replace_or_append_form_param(body, "ra_chain_pubkey", public_key_base64())
    return body


def award_offset_seconds(
    award: dict, now_millis: int | None = None
) -> tuple[int, bool]:
    current_time = now_millis or int(time.time() * 1000)
    raw_offset = int((current_time - award["queuedAt"]) / 1000)
    offset_seconds = clamp_award_offset_seconds(raw_offset)
    return offset_seconds, raw_offset != offset_seconds


def verify_chain(
    awards: list[dict],
    verify_signature=verify_award,
) -> tuple[bool, str | None, int | None]:
    for index, award in enumerate(awards):
        if not award.get("payloadHash"):
            continue

        expected_payload_hash = sha256_hex(canonical_payload(award))
        if award["payloadHash"] != expected_payload_hash:
            return False, "stored payloadHash does not match recomputed hash", index

        expected_prev_hash = (
            GENESIS_HASH
            if index == 0
            else (awards[index - 1].get("payloadHash") or GENESIS_HASH)
        )
        if award["prevHash"] != expected_prev_hash:
            return False, "chain link broken", index

        sign_input = f"{award['payloadHash']}:{award['prevHash']}".encode("utf-8")
        if not verify_signature(sign_input, award["signature"]):
            return False, "invalid signature", index

    return True, None, None


def repair_pending_chain(awards: list[dict]) -> list[dict] | None:
    if not awards:
        return []

    repaired: list[dict] = []
    for index, award in enumerate(awards):
        if not award.get("payloadHash"):
            repaired.append(dict(award))
            continue

        expected_payload_hash = sha256_hex(canonical_payload(award))
        if award["payloadHash"] != expected_payload_hash:
            return None

        prev_hash = (
            GENESIS_HASH
            if index == 0
            else (repaired[index - 1].get("payloadHash") or GENESIS_HASH)
        )
        sign_input = f"{award['payloadHash']}:{prev_hash}".encode("utf-8")
        repaired_award = dict(award)
        repaired_award["prevHash"] = prev_hash
        repaired_award["signature"] = sign_award(sign_input)
        repaired_award["signedAt"] = int(time.time() * 1000)
        repaired.append(repaired_award)

    return repaired


def refresh_and_load_achievement_ids(
    storage: Storage,
    credentials: dict,
    user_agent: str,
    config_data: dict,
    awards: list[dict],
) -> tuple[set[int], list[int], dict[int, int]] | None:
    patch_entries = storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH)
    achievementsets_entries = storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS)
    achievement_game_ids = build_achievement_game_ids(patch_entries, achievementsets_entries)

    award_game_ids: dict[int, int] = {}
    game_ids: list[int] = []
    for award in awards:
        game_id = achievement_game_ids.get(int(award["achievementId"]))
        if game_id is None:
            continue
        award_game_ids[int(award["id"])] = game_id
        if game_id not in game_ids:
            game_ids.append(game_id)

    if not game_ids:
        return set(), [], achievement_game_ids

    achievement_ids: set[int] = set()
    proxied_user_agent = proxy_user_agent(user_agent)
    for game_id in game_ids:
        try:
            response_body = refresh_game_patch(
                game_id, credentials, proxied_user_agent, storage, config_data
            )
        except CacheGameAuthError as exc:
            storage.mark_token_invalid(credentials["token"])
            LOGGER.warning(
                "Flush marked token invalid: user=%s reason=%s",
                credentials["user"],
                exc,
            )
            return None
        except CacheGameError as exc:
            LOGGER.warning("Flush could not refresh patch data: %s", exc)
            return None
        storage.clear_invalid_token()
        try:
            payload = json.loads(response_body)
            achievements = payload.get("PatchData", {}).get("Achievements", [])
            for achievement in achievements:
                achievement_id = achievement.get("ID")
                if isinstance(achievement_id, int):
                    achievement_ids.add(achievement_id)
        except Exception:
            return None

    return achievement_ids, game_ids, achievement_game_ids


def send_award(award: dict, config_data: dict, credentials: dict) -> tuple[str, str]:
    url = f"{upstream_host(config_data)}{award['queryString']}"
    offset_seconds, was_clamped = award_offset_seconds(award)
    body = build_award_request_body(award, current_token=credentials.get("token"))
    user_agent = proxy_user_agent(award["userAgent"] or FALLBACK_USER_AGENT)
    LOGGER.info(
        "Flush sending: achievementId=%s offsetSeconds=%s clamped=%s userAgent=%s url=%s",
        award["achievementId"],
        offset_seconds,
        was_clamped,
        user_agent,
        redact_query_tokens(award["queryString"]),
    )
    status, _reason, response_body = http_post(
        url,
        body,
        headers={"User-Agent": user_agent},
    )

    if status in (401, 403):
        return "auth_error", f"Token rejected by server (HTTP {status})"
    if status < 200 or status >= 300:
        return "network_error", f"HTTP {status}"

    try:
        payload = json.loads(response_body)
    except Exception:
        return "network_error", "Server returned invalid JSON"

    if payload.get("Success"):
        return "success", ""

    error = payload.get("Error") or "Server returned Success:false"
    lowered = error.lower()
    if any(
        keyword in lowered for keyword in ("invalid", "token", "credentials", "user")
    ):
        return "auth_error", error
    return "network_error", error


def flush_pending_awards(storage: Storage, config_data: dict) -> FlushOutcome:
    pending = storage.get_pending_awards()
    if not pending:
        return FlushOutcome(flushed=0, total=0, skipped_stale=0)

    LOGGER.info("Flush started: pending_awards=%s", len(pending))

    valid, reason, index = verify_chain(pending)
    if not valid:
        repaired_pending = repair_pending_chain(pending) if reason == "chain link broken" else None
        if repaired_pending is not None:
            repaired_valid, _, _ = verify_chain(repaired_pending)
            if repaired_valid:
                for award in repaired_pending:
                    storage.update_pending_award(award)
                pending = storage.get_pending_awards()
                LOGGER.info("Repaired pending award chain before flush")
            else:
                LOGGER.warning(
                    "Flush aborted: chain broken at index=%s reason=%s", index, reason
                )
                return FlushOutcome(
                    flushed=0,
                    total=len(pending),
                    skipped_stale=0,
                    pending_remaining=len(pending),
                    last_error=f"chain broken at {index}: {reason}",
                )
        else:
            LOGGER.warning(
                "Flush aborted: chain broken at index=%s reason=%s", index, reason
            )
            return FlushOutcome(
                flushed=0,
                total=len(pending),
                skipped_stale=0,
                pending_remaining=len(pending),
                last_error=f"chain broken at {index}: {reason}",
            )

    if not any(
        award.get("status", PENDING_AWARD_STATUS_PENDING)
        == PENDING_AWARD_STATUS_PENDING
        for award in pending
    ):
        skipped_deleted = sum(
            1
            for award in pending
            if award.get("status", PENDING_AWARD_STATUS_PENDING)
            == PENDING_AWARD_STATUS_DELETED
        )
        skipped_stale = sum(
            1
            for award in pending
            if award.get("status", PENDING_AWARD_STATUS_PENDING)
            == PENDING_AWARD_STATUS_STALE
        )
        purge_processed_awards_if_safe(storage)
        return FlushOutcome(
            flushed=0,
            total=len(pending),
            skipped_stale=skipped_stale,
            skipped_deleted=skipped_deleted,
            pending_remaining=0,
        )

    user_agent = self_user_agent()
    credentials = resolve_credentials(storage, config_data, user_agent)
    if credentials is None:
        LOGGER.warning("Flush aborted: no RetroAchievements credentials")
        return FlushOutcome(
            flushed=0,
            total=len(pending),
            skipped_stale=0,
            pending_remaining=len(pending),
            last_error="No RetroAchievements credentials available",
        )

    refreshed = refresh_and_load_achievement_ids(
        storage,
        credentials,
        user_agent,
        config_data,
        [
            award
            for award in pending
            if award.get("status", PENDING_AWARD_STATUS_PENDING)
            == PENDING_AWARD_STATUS_PENDING
        ],
    )
    if refreshed is None:
        LOGGER.warning("Flush aborted: could not refresh live achievement data")
        return FlushOutcome(
            flushed=0,
            total=len(pending),
            skipped_stale=0,
            pending_remaining=len(pending),
            last_error="Could not refresh achievement data from server",
        )

    known_achievement_ids, game_ids, cached_achievement_game_ids = refreshed
    flushed = 0
    skipped_deleted = 0
    skipped_stale = 0

    for award in pending:
        achievement_id = award["achievementId"]
        status = award.get("status", PENDING_AWARD_STATUS_PENDING)

        if status == PENDING_AWARD_STATUS_DELETED:
            skipped_deleted += 1
            continue

        if status == PENDING_AWARD_STATUS_STALE:
            skipped_stale += 1
            continue

        if status == PENDING_AWARD_STATUS_FLUSHED:
            continue

        if is_hardcore_award(award):
            award["status"] = PENDING_AWARD_STATUS_STALE
            award["lastError"] = (
                "Hardcore award cannot be flushed because hardcore mode is not supported"
            )
            storage.update_pending_award(award)
            LOGGER.info(
                "Flush marked hardcore pending award stale: achievementId=%s",
                achievement_id,
            )
            skipped_stale += 1
            continue

        if known_achievement_ids and achievement_id in cached_achievement_game_ids and achievement_id not in known_achievement_ids:
            award["status"] = PENDING_AWARD_STATUS_STALE
            award["lastError"] = (
                f"Achievement {achievement_id} not found in live server data"
            )
            storage.update_pending_award(award)
            skipped_stale += 1
            LOGGER.warning(
                "Flush skipped stale pending award: achievementId=%s lastError=%s",
                achievement_id,
                award["lastError"],
            )
            continue

        outcome, message = send_award(award, config_data, credentials)
        if outcome == "success":
            award["status"] = PENDING_AWARD_STATUS_FLUSHED
            award["lastError"] = None
            storage.update_pending_award(award)
            storage.clear_invalid_token()
            flushed += 1
            LOGGER.info("Flush succeeded: achievementId=%s", achievement_id)
        elif outcome == "auth_error":
            award["status"] = PENDING_AWARD_STATUS_PENDING
            award["lastError"] = message
            storage.update_pending_award(award)
            LOGGER.warning(
                "Flush auth error: achievementId=%s lastError=%s",
                achievement_id,
                message,
            )
        else:
            award["retryCount"] = int(award.get("retryCount", 0)) + 1
            award["status"] = PENDING_AWARD_STATUS_PENDING
            award["lastError"] = message
            storage.update_pending_award(award)
            if int(award["retryCount"]) >= MAX_RETRIES:
                LOGGER.warning(
                    "Flush network error reached max retries: achievementId=%s retryCount=%s lastError=%s",
                    achievement_id,
                    award["retryCount"],
                    message,
                )
            else:
                LOGGER.warning(
                    "Flush network error: achievementId=%s retryCount=%s lastError=%s",
                    achievement_id,
                    award["retryCount"],
                    message,
                )

    if flushed:
        time.sleep(3)
        proxied_user_agent = proxy_user_agent(user_agent)
        for game_id in game_ids:
            cache_unlocks(
                game_id, credentials, proxied_user_agent, config_data, storage
            )
            cache_session(game_id, credentials, storage)

    purge_processed_awards_if_safe(storage)
    pending_remaining = sum(
        1
        for award in storage.get_pending_awards()
        if award.get("status", PENDING_AWARD_STATUS_PENDING)
        == PENDING_AWARD_STATUS_PENDING
    )

    LOGGER.info(
        "Flush complete: total=%s flushed=%s skipped_deleted=%s skipped_stale=%s pending_remaining=%s",
        len(pending),
        flushed,
        skipped_deleted,
        skipped_stale,
        pending_remaining,
    )

    return FlushOutcome(
        flushed=flushed,
        total=len(pending),
        skipped_stale=skipped_stale,
        skipped_deleted=skipped_deleted,
        pending_remaining=pending_remaining,
    )


def purge_processed_awards_if_safe(storage: Storage) -> None:
    if storage.pending_awards_exist_by_status(PENDING_AWARD_STATUS_PENDING):
        return

    storage.delete_pending_awards_by_statuses(
        [
            PENDING_AWARD_STATUS_DELETED,
            PENDING_AWARD_STATUS_STALE,
            PENDING_AWARD_STATUS_FLUSHED,
        ]
    )
