from __future__ import annotations

USER_AGENT = "ua::last"
AUTH_INVALID_TOKEN = "auth::invalid_token"

PREFIX_LOGIN = "login2::"
PREFIX_PATCH = "patch:"
PREFIX_UNLOCKS = "unlocks:"
PREFIX_STARTSESSION = "startsession:"
PREFIX_GAMEID = "gameid:"
PREFIX_ACHIEVEMENTSETS = "achievementsets:"


def login(user: str) -> str:
    return f"login2::{normalize_user(user)}"


def game_id(hash_value: str) -> str:
    return f"gameid:{normalize_hash(hash_value)}"


def patch(game_id_value: int | str, user: str) -> str:
    return f"patch:{game_id_value}:{normalize_user(user)}"


def patch_prefix(game_id_value: int | str) -> str:
    return f"patch:{game_id_value}:"


def unlocks(game_id_value: int | str, user: str) -> str:
    return f"unlocks:{game_id_value}:{normalize_user(user)}:0"


def start_session(game_id_value: int | str, user: str) -> str:
    return f"startsession:{game_id_value}:{normalize_user(user)}:0"


def achievementsets(scope: int | str, user: str) -> str:
    return f"achievementsets:{normalize_achievementsets_scope(scope)}:{normalize_user(user)}"


def normalize_hash(hash_value: str) -> str:
    return hash_value.strip().lower()


def normalize_achievementsets_scope(scope: int | str) -> str:
    return normalize_hash(str(scope))


def normalize_user(user: str) -> str:
    return user.strip().lower()


def parse_game_id_from_patch_key(cache_key: str) -> int | None:
    if not cache_key.startswith(PREFIX_PATCH):
        return None

    value = cache_key.removeprefix(PREFIX_PATCH).split(":", 1)[0]
    return int(value) if value.isdigit() else None
