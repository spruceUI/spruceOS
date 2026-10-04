from __future__ import annotations

import json
import logging

from . import cache_keys
from .config import (
    FALLBACK_USER_AGENT,
    detect_retroarch_cfg,
    detect_rocknix_system_cfg,
    upstream_host,
)
from .network import build_api_url, http_get
from .retroarch_cfg import (
    cheevos_append_cfg_path,
    load_retroarch_password_credentials,
    load_retroarch_token_credentials,
    load_rocknix_system_password_credentials,
    load_rocknix_system_token_credentials,
    load_spruce_credentials,
)
from .storage import Storage
from .utils import proxy_user_agent

LOGGER = logging.getLogger("raofflineproxy")


def resolve_credentials(
    storage: Storage,
    config_data: dict | None = None,
    user_agent: str = FALLBACK_USER_AGENT,
) -> dict | None:
    config_data = config_data or {}
    cfg_path = str(config_data.get("retroarch_cfg") or detect_retroarch_cfg())
    # Also check the cheevos appendconfig — muOS stores credentials there
    cheevos_cfg = str(cheevos_append_cfg_path(cfg_path)) if cfg_path else None
    # ROCKNIX goes further: setsettings.sh deletes cheevos_username/cheevos_password
    # from retroarch.cfg on every game launch, so EmulationStation's own settings are
    # the only place its credentials live.
    rocknix_system_cfg = detect_rocknix_system_cfg(config_data)

    token_credentials = (
        load_retroarch_token_credentials(cfg_path)
        or load_retroarch_token_credentials(cheevos_cfg)
        or load_rocknix_system_token_credentials(rocknix_system_cfg)
    )
    if token_credentials is not None:
        return cache_token_credentials(storage, token_credentials)

    cached = storage.load_login_credentials()
    if cached is not None and not storage.is_token_invalid(cached["token"]):
        return cached

    # spruce keeps its credentials in its own settings file and only copies them into
    # the RetroArch config when a game launches, so before the first launch that file is
    # the only source.
    password_credentials = (
        load_retroarch_password_credentials(cfg_path)
        or load_retroarch_password_credentials(cheevos_cfg)
        or load_rocknix_system_password_credentials(rocknix_system_cfg)
        or load_spruce_credentials()
    )
    if password_credentials is not None:
        refreshed = login_and_cache_token(
            storage, config_data, password_credentials, user_agent
        )
        if refreshed is not None:
            return refreshed

    return cached


def cache_token_credentials(storage: Storage, credentials: dict) -> dict | None:
    user = credentials.get("user")
    token = credentials.get("token")
    if not user or not token:
        return None

    body = json.dumps({"Success": True, "User": user, "Token": token})
    storage.upsert_cache(cache_keys.login(user), body)
    return {"user": user, "token": token}


def login_and_cache_token(
    storage: Storage,
    config_data: dict,
    credentials: dict,
    user_agent: str,
) -> dict | None:
    url = build_api_url(
        upstream_host(config_data),
        "login2",
        {
            "u": credentials["user"],
            "p": credentials["password"],
        },
    )
    try:
        response_body = http_get(
            url, proxy_user_agent(user_agent or FALLBACK_USER_AGENT)
        )
        payload = json.loads(response_body)
    except Exception as exc:
        LOGGER.warning("login2 request failed: %s", exc)
        return None

    user = payload.get("User") or credentials["user"]
    token = payload.get("Token")
    if not payload.get("Success") or not user or not token:
        LOGGER.warning("login2 rejected credentials for user=%s", credentials["user"])
        return None

    storage.upsert_cache(cache_keys.login(user), response_body)
    return {"user": user, "token": token}
